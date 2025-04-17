-- lua/nai/api.lua
-- API interactions for AI providers

local M = {}
local config = require('nai.config')
local error_utils = require('nai.utils.error')

-- Handle chat API request
function M.chat_request(messages, on_complete, on_error, chat_config)
  -- Generate a unique request ID
  local request_id = tostring(os.time()) .. "_" .. tostring(math.random(10000))

  -- Use chat-specific provider if available, otherwise use global config
  local provider = chat_config and chat_config.provider or config.options.active_provider

  -- Get the provider's base config
  local provider_config = config.options.providers[provider] or config.get_provider_config()

  local api_key = config.get_api_key(provider)

  if not api_key then
    vim.schedule(function()
      on_error("API key not found for " .. provider)
    end)
    return
  end

  -- Get the model
  local model = chat_config and chat_config.model or provider_config.model
  local max_tokens_value = chat_config and chat_config.max_tokens or provider_config.max_tokens

  -- Create data structure based on provider and model
  local data = {}

  if provider == "ollama" then
    data = {
      model = model,
      messages = messages,
      options = {
        temperature = chat_config and chat_config.temperature or provider_config.temperature,
        num_predict = max_tokens_value,
      },
      stream = false
    }
  elseif provider == "openai" and (model == "o3" or model:match("^o3:")) then
    -- Special case for OpenAI's o3 model
    data = {
      model = model,
      messages = messages,
      max_completion_tokens = max_tokens_value
      -- Omit temperature for o3 model as it only supports the default value
    }
  else
    -- Default case for other models
    data = {
      model = model,
      messages = messages,
      temperature = chat_config and chat_config.temperature or provider_config.temperature,
      max_tokens = max_tokens_value
    }
  end

  -- Register this request in our state
  local state = require('nai.state')
  local events = require('nai.events')

  state.register_request(request_id, {
    id = request_id,
    type = 'chat',
    status = 'pending',
    start_time = os.time(),
    provider = provider,
    model = data.model,
    messages = messages,
    config = chat_config
  })

  -- Emit event
  events.emit('request:start', request_id, provider, data.model)

  local json_data = vim.json.encode(data)
  local endpoint_url = provider_config.endpoint
  local auth_header = "Authorization: Bearer " .. api_key

  -- Detect platform
  local path = require('nai.utils.path')
  local is_windows = path.is_windows

  -- Function to handle the API response
  local function process_response(obj)
    -- Check if this request was cancelled
    local state = require('nai.state')
    if not state.get_active_requests()[request_id] then
      -- Request was cancelled or removed
      return
    end

    if obj.code ~= 0 then
      vim.schedule(function()
        on_error(error_utils.log("Request failed with code " .. obj.code, error_utils.LEVELS.ERROR, {
          provider = provider,
          endpoint = endpoint_url
        }))
      end)
      return
    end

    local response = obj.stdout
    if not response or response == "" then
      vim.schedule(function()
        on_error(error_utils.log("Empty response from API", error_utils.LEVELS.ERROR, {
          provider = provider
        }))
      end)
      return
    end

    local success, parsed = pcall(vim.json.decode, response)
    if not success then
      vim.schedule(function()
        on_error(error_utils.log("Failed to parse API response", error_utils.LEVELS.ERROR, {
          provider = provider,
          response_preview = string.sub(response, 1, 100)
        }))
      end)
      return
    end

    if parsed.error then
      vim.schedule(function()
        on_error(error_utils.handle_api_error(response, provider))
      end)
      return
    end

    -- Extract content based on provider format
    local content = nil

    if provider == "ollama" then
      -- Ollama format handling with deferred logging
      if parsed.message then
        if parsed.message.content then
          content = parsed.message.content
        else
        end
      else
      end
    else
      -- Standard OpenAI format
      if parsed.choices and #parsed.choices > 0 and parsed.choices[1].message then
        content = parsed.choices[1].message.content
      end
    end

    if content then
      -- Update state
      state.update_request(request_id, {
        status = 'completed',
        end_time = os.time(),
        response = content
      })

      -- Emit event
      events.emit('request:complete', request_id, content)

      vim.schedule(function()
        on_complete(content)
        -- Clear request from state after callback completes
        state.clear_request(request_id)
      end)
    else
      -- On error, update state and emit event
      state.update_request(request_id, {
        status = 'error',
        end_time = os.time(),
        error = "No valid content in API response"
      })

      events.emit('request:error', request_id, "No valid content in API response")

      vim.schedule(function()
        on_error("No valid content in API response: " .. vim.inspect(parsed))
        -- Clear request from state after callback completes
        state.clear_request(request_id)
      end)
    end
  end

  local handle

  -- On Windows with large payloads, use a temporary file approach
  if is_windows and #json_data > 8000 then -- Windows has command line length limits
    local temp_file = path.tmpname()
    local file = io.open(temp_file, "w")

    if file then
      file:write(json_data)
      file:close()

      handle = vim.system({
        "curl",
        "-s",
        "-X", "POST",
        endpoint_url,
        "-H", "Content-Type: application/json",
        "-H", auth_header,
        "-d", "@" .. temp_file
      }, { text = true }, function(obj)
        -- Clean up temp file
        os.remove(temp_file)
        process_response(obj)
      end)
    else
      -- Fall back to direct approach if temp file creation fails
      vim.schedule(function()
        on_error("Failed to create temporary file for API request")
      end)
      return
    end
  else
    -- Standard approach for Unix or smaller payloads on Windows
    if config.options.debug and config.options.debug.enabled then
      vim.notify("DEBUG: API request data for " .. provider .. "/" .. model .. ":\n" .. json_data, vim.log.levels.DEBUG)
    end

    handle = vim.system({
      "curl",
      "-s",
      "-X", "POST",
      endpoint_url,
      "-H", "Content-Type: application/json",
      "-H", auth_header,
      "-d", json_data
    }, { text = true }, process_response)
  end

  -- Store the request ID with the handle for cancellation
  if handle then
    handle.request_id = request_id
  end

  return {
    handle = request_id,
    terminate = function()
      if handle then
        if vim.system and handle.terminate then
          handle:terminate()
        elseif not vim.system and handle.close then
          handle:close()
        end
      end
    end
  }
end

function M.cancel_request(handle)
  if handle and handle.request_id then
    local state = require('nai.state')
    local events = require('nai.events')

    -- Update state
    state.update_request(handle.request_id, {
      status = 'cancelled',
      end_time = os.time()
    })

    -- Emit event
    events.emit('request:cancel', handle.request_id)

    -- Clear request after a short delay (to allow event handlers to access it)
    vim.defer_fn(function()
      state.clear_request(handle.request_id)
    end, 100)
  end

  -- Attempt to terminate the process
  if handle then
    if vim.system and handle.terminate then
      handle:terminate()
    elseif not vim.system and handle.close then
      handle:close()
    end
  end
end

return M
