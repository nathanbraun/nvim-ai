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
      -- Create a dummy request ID for tracking this error
      local error_request_id = "error_" .. tostring(os.time()) .. "_" .. tostring(math.random(10000))

      -- Register and immediately update the request state
      state.register_request(error_request_id, {
        id = error_request_id,
        type = 'chat',
        status = 'error',
        start_time = os.time(),
        end_time = os.time(),
        provider = provider,
        error = "API key not found for " .. provider
      })

      -- Emit event
      events.emit('request:error', error_request_id, "API key not found")

      on_error("API key not found for " .. provider)

      -- Clear request from state after callback completes
      state.clear_request(error_request_id)
    end)
    return
  end

  -- Get the model - use chat-specific, active_model, or default
  local model = chat_config and chat_config.model or config.options.active_model
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
  elseif provider == "google" then
    -- Special case for Google's Gemini models
    -- For Google, we need a simpler structure
    local parts = {}

    -- Add each message as a separate part
    for _, msg in ipairs(messages) do
      local prefix = ""
      if msg.role == "system" then
        prefix = "System: "
      elseif msg.role == "user" then
        prefix = "Human: "
      elseif msg.role == "assistant" then
        prefix = "Assistant: "
      end

      -- Add to parts array
      table.insert(parts, { text = prefix .. msg.content })
    end

    -- Build the final data structure
    data = {
      contents = {
        {
          parts = { { text = messages[#messages].content } }
        }
      },
      generationConfig = {
        temperature = chat_config and chat_config.temperature or provider_config.temperature,
        maxOutputTokens = max_tokens_value
      }
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

  -- Prepare the endpoint URL and auth header
  local endpoint_url = provider_config.endpoint
  local auth_header = nil

  -- Handle provider-specific URL and auth
  if provider == "google" then
    -- For Google, construct the URL with the model and API key
    endpoint_url = provider_config.endpoint .. model .. ":generateContent?key=" .. api_key
    -- No auth header needed for Google when using API key in URL
  else
    -- For other providers, use bearer token auth
    auth_header = "Authorization: Bearer " .. api_key
  end

  local json_data = vim.json.encode(data)

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
      -- Update state to error and clear the request
      state.update_request(request_id, {
        status = 'error',
        end_time = os.time(),
        error = "Request failed with code " .. obj.code
      })

      -- Emit event
      events.emit('request:error', request_id, "Request failed with code " .. obj.code)

      vim.schedule(function()
        on_error(error_utils.log("Request failed with code " .. obj.code, error_utils.LEVELS.ERROR, {
          provider = provider,
          endpoint = endpoint_url
        }))

        -- Clear request from state after callback completes
        state.clear_request(request_id)
      end)
      return
    end

    local response = obj.stdout
    if not response or response == "" then
      -- Update state to error
      state.update_request(request_id, {
        status = 'error',
        end_time = os.time(),
        error = "Empty response from API"
      })

      -- Emit event
      events.emit('request:error', request_id, "Empty response from API")

      vim.schedule(function()
        on_error(error_utils.log("Empty response from API", error_utils.LEVELS.ERROR, {
          provider = provider
        }))

        -- Clear request from state after callback completes
        state.clear_request(request_id)
      end)
      return
    end

    local success, parsed = pcall(vim.json.decode, response)
    if not success then
      -- Update state to error
      state.update_request(request_id, {
        status = 'error',
        end_time = os.time(),
        error = "Failed to parse API response"
      })

      -- Emit event
      events.emit('request:error', request_id, "Failed to parse API response")

      vim.schedule(function()
        on_error(error_utils.log("Failed to parse API response", error_utils.LEVELS.ERROR, {
          provider = provider,
          response_preview = string.sub(response, 1, 100)
        }))

        -- Clear request from state after callback completes
        state.clear_request(request_id)
      end)
      return
    end

    if parsed.error then
      -- Update state to error
      state.update_request(request_id, {
        status = 'error',
        end_time = os.time(),
        error = "API error: " .. (parsed.error.message or "Unknown error")
      })

      -- Emit event
      events.emit('request:error', request_id, "API error")

      vim.schedule(function()
        -- For Google, the error format is different
        if provider == "google" then
          local error_message = parsed.error.message or "Unknown Google API error"
          on_error(error_utils.log("Google API Error: " .. error_message, error_utils.LEVELS.ERROR, {
            provider = provider,
            error_detail = parsed.error
          }))
        else
          on_error(error_utils.handle_api_error(response, provider))
        end

        -- Clear request from state after callback completes
        state.clear_request(request_id)
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
        end
      end
    elseif provider == "google" then
      -- Google format handling
      if parsed.candidates and #parsed.candidates > 0 and
          parsed.candidates[1].content and
          parsed.candidates[1].content.parts and
          #parsed.candidates[1].content.parts > 0 then
        content = parsed.candidates[1].content.parts[1].text
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

  -- Enable debug for this request
  local debug_enabled = config.options.debug and config.options.debug.enabled
  local verbose_debug = debug_enabled and config.options.debug.verbose

  if debug_enabled then
    vim.notify("DEBUG: API request URL: " .. endpoint_url, vim.log.levels.DEBUG)
    vim.notify("DEBUG: API request data for " .. provider .. "/" .. model .. ":\n" .. json_data, vim.log.levels.DEBUG)
    if verbose_debug then
      -- Add verbose debug for curl
      table.insert(curl_args, "-v")

      -- Replace the process_response function with one that logs everything
      local original_process_response = process_response
      process_response = function(obj)
        if verbose_debug then
          vim.notify("VERBOSE DEBUG: Curl exit code: " .. obj.code, vim.log.levels.DEBUG)
          vim.notify("VERBOSE DEBUG: Curl stdout:\n" .. (obj.stdout or "Empty"), vim.log.levels.DEBUG)
          vim.notify("VERBOSE DEBUG: Curl stderr:\n" .. (obj.stderr or "Empty"), vim.log.levels.DEBUG)
        end

        -- Call the original handler
        original_process_response(obj)
      end
    end
  end

  -- On Windows with large payloads, use a temporary file approach
  if is_windows and #json_data > 8000 then -- Windows has command line length limits
    local temp_file = path.tmpname()
    local file = io.open(temp_file, "w")

    if file then
      file:write(json_data)
      file:close()

      local curl_args = {
        "curl",
        "-s",
        "-X", "POST",
        endpoint_url,
        "-H", "Content-Type: application/json",
      }

      -- Only add auth header if it exists (not for Google)
      if auth_header then
        table.insert(curl_args, "-H")
        table.insert(curl_args, auth_header)
      end

      -- Add data from file
      table.insert(curl_args, "-d")
      table.insert(curl_args, "@" .. temp_file)

      handle = vim.system(curl_args, { text = true }, function(obj)
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
    local curl_args = {
      "curl",
      "-s",
      "-X", "POST",
      endpoint_url,
      "-H", "Content-Type: application/json",
    }

    -- Only add auth header if it exists (not for Google)
    if auth_header then
      table.insert(curl_args, "-H")
      table.insert(curl_args, auth_header)
    end

    -- Add data
    table.insert(curl_args, "-d")
    table.insert(curl_args, json_data)

    -- For debugging
    if debug_enabled then
      local curl_cmd = "curl -s -X POST \"" .. endpoint_url .. "\" -H \"Content-Type: application/json\""
      if auth_header then
        curl_cmd = curl_cmd .. " -H \"" .. auth_header .. "\""
      end
      curl_cmd = curl_cmd .. " -d '" .. json_data:gsub("'", "'\\''") .. "'"
      vim.notify("DEBUG: Equivalent curl command:\n" .. curl_cmd, vim.log.levels.DEBUG)
    end

    handle = vim.system(curl_args, { text = true }, process_response)
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
