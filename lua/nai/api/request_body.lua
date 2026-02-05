-- lua/nai/api/request_body.lua
-- Build provider-specific request body for API calls

local M = {}

function M.build(provider, model, messages, chat_config, provider_config)
  local max_tokens_value = chat_config and chat_config.max_tokens or provider_config.max_tokens
  local temperature = chat_config and chat_config.temperature or provider_config.temperature

  if provider == "ollama" then
    return {
      model = model,
      messages = messages,
      options = {
        temperature = temperature,
        num_predict = max_tokens_value,
      },
      stream = false
    }
  elseif provider == "google" then
    local contents = {}
    for _, msg in ipairs(messages) do
      local role = "user"
      if msg.role == "assistant" then
        role = "model"
      end
      table.insert(contents, {
        role = role,
        parts = { { text = msg.content } }
      })
    end

    return {
      contents = contents,
      generationConfig = {
        temperature = temperature,
        maxOutputTokens = max_tokens_value
      }
    }
  elseif provider == "openai" and (model == "o3" or model:match("^o3:")) then
    return {
      model = model,
      messages = messages,
      max_completion_tokens = max_tokens_value
    }
  else
    return {
      model = model,
      messages = messages,
      temperature = temperature,
      max_tokens = max_tokens_value
    }
  end
end

return M
