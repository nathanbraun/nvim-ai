-- lua/nai/api.lua
-- API interactions for AI providers

local M = {}
local config = require('nai.config')
local request_body = require('nai.api.request_body')
local response_parser = require('nai.api.response_parser')
local session_utils = require('nai.utils.session')

-- Build curl args common to both Windows temp-file and standard paths
local function build_curl_args(endpoint_url, auth_header, extra_args)
  local args = {
    "curl",
    "-s",
    "-X", "POST",
    endpoint_url,
    "-H", "Content-Type: application/json",
  }

  if auth_header then
    table.insert(args, "-H")
    table.insert(args, auth_header)
  end

  for _, arg in ipairs(extra_args) do
    table.insert(args, arg)
  end

  return args
end

-- Handle chat API request
function M.chat_request(messages, on_complete, on_error, chat_config)
  local request_id = session_utils.generate_request_id()

  local provider = chat_config and chat_config.provider or config.options.active_provider
  local provider_config = config.options.providers[provider] or config.get_provider_config()

  -- Standard API path (OpenAI, OpenRouter, Google, Ollama, etc.)
  local api_key = config.get_api_key(provider)

  if not api_key then
    vim.schedule(function()
      local error_request_id = session_utils.generate_request_id("error")

      local state = require('nai.state')
      state.register_request(error_request_id, {
        id = error_request_id,
        type = 'chat',
        status = 'error',
        start_time = os.time(),
        end_time = os.time(),
        provider = provider,
        error = "API key not found for " .. provider
      })

      local events = require('nai.events')
      events.emit('request:error', error_request_id, "API key not found")
      on_error("API key not found for " .. provider)
      state.clear_request(error_request_id)
    end)
    return
  end

  local model = chat_config and chat_config.model or config.options.active_model
  local data = request_body.build(provider, model, messages, chat_config, provider_config)

  -- Register request in state
  local state = require('nai.state')
  local events = require('nai.events')

  state.register_request(request_id, {
    id = request_id,
    type = 'chat',
    status = 'pending',
    start_time = os.time(),
    provider = provider,
    model = model,
    messages = messages,
    config = chat_config
  })

  events.emit('request:start', request_id, provider, model)

  -- Prepare endpoint URL and auth header
  local endpoint_url = provider_config.endpoint
  local auth_header = nil

  if provider == "google" then
    endpoint_url = provider_config.endpoint .. model .. ":generateContent?key=" .. api_key
  else
    auth_header = "Authorization: Bearer " .. api_key
  end

  local json_data = vim.json.encode(data)

  -- Build response handler
  local function process_response(obj)
    local state = require('nai.state')
    if not state.get_active_requests()[request_id] then
      return
    end

    local error_handler = require('nai.utils.error_handler')

    if obj.code ~= 0 then
      error_handler.handle_request_error({
        request_id = request_id,
        error_msg = "Request failed with code " .. obj.code,
        callback = on_error,
        context = { provider = provider, endpoint = endpoint_url }
      })
      return
    end

    local response = obj.stdout
    if not response or response == "" then
      error_handler.handle_request_error({
        request_id = request_id,
        error_msg = "Empty response from API",
        callback = on_error,
        context = { provider = provider }
      })
      return
    end

    local success, parsed = pcall(vim.json.decode, response)
    if not success then
      error_handler.handle_request_error({
        request_id = request_id,
        error_msg = "Failed to parse API response",
        callback = on_error,
        context = { provider = provider, response_preview = string.sub(response, 1, 100) }
      })
      return
    end

    if parsed.error then
      error_handler.handle_api_error({
        response = response,
        provider = provider,
        request_id = request_id,
        callback = on_error,
        endpoint = endpoint_url
      })
      return
    end

    local content = response_parser.extract_content(parsed, provider)

    if content then
      state.update_request(request_id, {
        status = 'completed',
        end_time = os.time(),
        response = content
      })

      local events = require('nai.events')
      events.emit('request:complete', request_id, content)

      vim.schedule(function()
        on_complete(content)
        state.clear_request(request_id)
      end)
    else
      error_handler.handle_request_error({
        request_id = request_id,
        error_msg = "No valid content in API response",
        callback = on_error,
        context = { provider = provider, parsed_response = vim.inspect(parsed) }
      })
    end
  end

  -- Debug logging
  local extra_curl_args = {}
  local debug_enabled = config.options.debug and config.options.debug.enabled
  local verbose_debug = debug_enabled and config.options.debug.verbose

  if debug_enabled then
    vim.notify("DEBUG: API request URL: " .. endpoint_url, vim.log.levels.DEBUG)
    vim.notify("DEBUG: API request data for " .. provider .. "/" .. model .. ":\n" .. json_data, vim.log.levels.DEBUG)
    if verbose_debug then
      table.insert(extra_curl_args, "-v")

      local original_process_response = process_response
      process_response = function(obj)
        vim.notify("VERBOSE DEBUG: Curl exit code: " .. obj.code, vim.log.levels.DEBUG)
        vim.notify("VERBOSE DEBUG: Curl stdout:\n" .. (obj.stdout or "Empty"), vim.log.levels.DEBUG)
        vim.notify("VERBOSE DEBUG: Curl stderr:\n" .. (obj.stderr or "Empty"), vim.log.levels.DEBUG)
        original_process_response(obj)
      end
    end
  end

  -- Execute request
  local handle
  local path = require('nai.utils.path')

  if path.is_windows and #json_data > 8000 then
    local temp_file = path.tmpname()
    local file = io.open(temp_file, "w")

    if file then
      file:write(json_data)
      file:close()

      local curl_args = build_curl_args(endpoint_url, auth_header, extra_curl_args)
      table.insert(curl_args, "-d")
      table.insert(curl_args, "@" .. temp_file)

      handle = vim.system(curl_args, { text = true }, function(obj)
        os.remove(temp_file)
        process_response(obj)
      end)
    else
      vim.schedule(function()
        on_error("Failed to create temporary file for API request")
      end)
      return
    end
  else
    local curl_args = build_curl_args(endpoint_url, auth_header, extra_curl_args)
    table.insert(curl_args, "-d")
    table.insert(curl_args, json_data)

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
  local error_handler = require('nai.utils.error_handler')

  if handle and handle.request_id then
    error_handler.handle_request_cancellation(handle.request_id)
  end

  if handle then
    if vim.system and handle.terminate then
      handle:terminate()
    elseif not vim.system and handle.close then
      handle:close()
    end
  end
end

return M
