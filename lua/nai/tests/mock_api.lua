-- lua/nai/tests/mock_api.lua
local M = {}

-- Store original functions
M.original_functions = {}

-- Mock responses for different providers
M.mock_responses = {
  openai = {
    success = {
      choices = {
        {
          message = {
            content = "This is a mock response from OpenAI."
          }
        }
      }
    },
    error = {
      error = {
        message = "Mock API error from OpenAI"
      }
    }
  },
  openrouter = {
    success = {
      choices = {
        {
          message = {
            content = "This is a mock response from OpenRouter."
          }
        }
      }
    },
    error = {
      error = {
        message = "Mock API error from OpenRouter"
      }
    }
  }
}

-- Install API mocks
function M.install_mocks(should_succeed)
  local api = require('nai.api')

  -- Save original function
  M.original_functions.chat_request = api.chat_request

  -- Replace with mock
  api.chat_request = function(messages, on_complete, on_error, chat_config)
    -- Get provider from config
    local config = require('nai.config')
    local provider = chat_config and chat_config.provider or config.options.active_provider

    -- Simulate network delay
    vim.defer_fn(function()
      if should_succeed then
        -- Get mock response for this provider
        local response = vim.json.encode(M.mock_responses[provider].success)
        on_complete(M.mock_responses[provider].success.choices[1].message.content)
      else
        -- Get mock error for this provider
        local error_msg = M.mock_responses[provider].error.error.message
        on_error(error_msg)
      end
    end, 100) -- 100ms delay to simulate network

    -- Return a mock handle
    return {
      request_id = "mock_request_" .. os.time(),
      terminate = function() end
    }
  end
end

-- Restore original functions
function M.restore_originals()
  if M.original_functions.chat_request then
    local api = require('nai.api')
    api.chat_request = M.original_functions.chat_request
  end
end

return M
