-- lua/nai/tests/init.lua
local M = {}
local config = require('nai.config')
local error_utils = require('nai.utils.error')

-- Test API Error Handling
function M.test_api_error()
  -- Test with invalid API key
  local original_get_api_key = config.get_api_key
  config.get_api_key = function() return "invalid_key_for_testing" end

  -- Make a request that will fail
  local test_messages = {
    { role = "user", content = "This is a test message that should fail" }
  }

  require('nai.api').chat_request(
    test_messages,
    function(response)
      vim.notify("Test failed: Request succeeded when it should have failed", vim.log.levels.ERROR)
      -- Restore the original function
      config.get_api_key = original_get_api_key
    end,
    function(error_msg)
      vim.notify("Test passed: API error correctly handled: " .. error_msg, vim.log.levels.INFO)
      -- Restore the original function
      config.get_api_key = original_get_api_key
    end
  )

  return "API error test initiated"
end

-- Test File Operation Errors
function M.test_file_errors()
  local reference = require('nai.fileutils.reference')

  -- Test with non-existent file
  local result1 = reference.read_file("/path/to/nonexistent/file.txt")
  vim.notify("Non-existent file test result: " .. result1, vim.log.levels.INFO)

  -- Test with binary file (if you have one)
  local result2 = reference.read_file("/path/to/some/image.jpg")
  vim.notify("Binary file test result: " .. result2, vim.log.levels.INFO)

  return "File error tests completed"
end

-- Test Buffer Validation
function M.test_buffer_validation()
  local buffer = require('nai.buffer')

  -- Test with invalid buffer number
  local result = error_utils.validate_buffer(99999, "test operation")
  vim.notify("Invalid buffer validation result: " .. tostring(result), vim.log.levels.INFO)

  -- Test activating invalid buffer
  buffer.activate_buffer(99999)
  vim.notify("Attempted to activate invalid buffer", vim.log.levels.INFO)

  return "Buffer validation tests completed"
end

-- Test Dependency Checking
function M.test_dependency_check()
  -- Test with existing executable
  local result1 = error_utils.check_executable("nvim", "This should always pass")
  vim.notify("Existing executable check: " .. tostring(result1), vim.log.levels.INFO)

  -- Test with non-existent executable
  local result2 = error_utils.check_executable("this_command_should_not_exist", "This should fail")
  vim.notify("Non-existent executable check: " .. tostring(result2), vim.log.levels.INFO)

  return "Dependency check tests completed"
end

-- Main Test Runner
function M.run_all()
  vim.notify("Starting nvim-ai error handling tests", vim.log.levels.INFO)

  -- Run the tests
  M.test_dependency_check()
  M.test_buffer_validation()
  M.test_file_errors()

  -- API test should be run separately since it's asynchronous
  vim.notify("Run M.test_api_error() separately for API testing", vim.log.levels.INFO)

  return "Basic tests completed"
end

return M
