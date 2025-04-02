-- lua/nai/api.lua
-- API interactions for AI providers

local M = {}
local config = require('nai.config')

-- Handle chat API request
function M.chat_request(messages, on_complete, on_error)
  local provider_config = config.get_provider_config()
  local api_key = provider_config.api_key

  -- Debug print the messages
  print("Messages being sent to API:")
  for i, msg in ipairs(messages) do
    print(i, msg.role, msg.content:sub(1, 100) .. (msg.content:len() > 100 and "..." or ""))
  end

  if not api_key then
    vim.schedule(function()
      on_error("API key not found for " .. config.options.provider)
    end)
    return
  end

  local data = {
    model = provider_config.model,
    messages = messages,
    temperature = provider_config.temperature,
    max_tokens = provider_config.max_tokens,
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

  return handle
end

return M
