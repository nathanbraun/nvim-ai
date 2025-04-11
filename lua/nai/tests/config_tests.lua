-- lua/nai/tests/config_tests.lua
local M = {}
local framework = require('nai.tests.framework')
local config = require('nai.config')

-- Test configuration loading
function M.test_config_loading()
  return framework.run_test("Config: Basic loading", function()
    -- Test with minimal configuration
    local test_config = {
      active_provider = "openai"
    }

    local result = config.setup(test_config)

    local success, err = framework.assert_equals(config.options.active_provider, "openai",
      "Provider should be set correctly")
    if not success then return false, err end

    -- Reset to defaults
    config.setup({})

    return true
  end)
end

-- Test API key management
function M.test_api_key_management()
  return framework.run_test("Config: API key management", function()
    -- Store original env var value if it exists
    local original_env = vim.env.OPENAI_API_KEY

    -- Set mock environment variable
    vim.env.OPENAI_API_KEY = "test_openai_key"

    -- Test key retrieval
    local key = config.get_api_key("openai")

    -- Restore original env var
    if original_env then
      vim.env.OPENAI_API_KEY = original_env
    else
      vim.env.OPENAI_API_KEY = nil
    end

    -- Check the result
    local success, err = framework.assert_equals(key, "test_openai_key", "Should retrieve correct API key")
    return success, err
  end)
end

return M
