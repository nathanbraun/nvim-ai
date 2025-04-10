-- lua/nai/api.lua
-- API interactions for AI providers

local M = {}
local config = require('nai.config')
M.cancelled_requests = {}

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

  -- Merge global config with chat-specific config
  local data = {
    model = chat_config and chat_config.model or provider_config.model,
    messages = messages,
    temperature = chat_config and chat_config.temperature or provider_config.temperature,
    max_tokens = chat_config and chat_config.max_tokens or provider_config.max_tokens,
  }


  local json_data = vim.json.encode(data)
  local endpoint_url = provider_config.endpoint

  local auth_header = "Authorization: Bearer " .. api_key

  local handle = vim.system({
    "curl",
    "-s",
    "-X", "POST",
    endpoint_url,
    "-H", "Content-Type: application/json",
    "-H", auth_header,
    "-d", json_data
  }, { text = true }, function(obj)
    -- Check if this request was cancelled
    if M.cancelled_requests[request_id] then
      M.cancelled_requests[request_id] = nil
      return
    end

    if obj.code ~= 0 then
      vim.schedule(function()
        on_error("Request failed with code " .. obj.code)
      end)
      return
    end

    local response = obj.stdout
    if not response or response == "" then
      vim.schedule(function()
        on_error("Empty response from API")
      end)
      return
    end

    local success, parsed = pcall(vim.json.decode, response)
    if not success then
      vim.schedule(function()
        on_error("Failed to parse API response: " .. parsed)
      end)
      return
    end

    if parsed.error then
      vim.schedule(function()
        on_error("API Error: " .. (parsed.error.message or "Unknown error"))
      end)
      return
    end

    if parsed and parsed.choices and #parsed.choices > 0 then
      local content = parsed.choices[1].message.content
      vim.schedule(function()
        on_complete(content)
      end)
    else
      vim.schedule(function()
        on_error("No valid content in API response")
      end)
    end
  end)

  -- Store the request ID with the handle for cancellation
  handle.request_id = request_id

  return handle
end

function M.cancel_request(handle)
  if handle and handle.request_id then
    M.cancelled_requests[handle.request_id] = true
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
