-- lua/nai/tests/init.lua
local M = {}
local framework = require('nai.tests.framework')

-- Import test modules
local parser_tests = require('nai.tests.parser_tests')
local config_tests = require('nai.tests.config_tests')
local integration_tests = require('nai.tests.integration_tests')
local fileutils_tests = require('nai.tests.fileutils_tests') -- Add this line

function M.run_all()
  -- Reset results
  framework.reset_results()

  vim.notify("Running nvim-ai tests...", vim.log.levels.INFO)

  -- Run parser tests
  parser_tests.test_parse_chat_buffer()
  parser_tests.test_message_formatting()
  parser_tests.test_placeholder_replacement()

  -- Run config tests
  config_tests.test_config_loading()
  config_tests.test_api_key_management()

  -- Run integration tests
  integration_tests.test_chat_flow()
  integration_tests.test_error_handling()

  -- Run fileutils tests
  fileutils_tests.test_expand_paths()       -- Add this line
  fileutils_tests.test_invalid_paths()      -- Add this line
  fileutils_tests.test_snapshot_expansion() -- Add this line

  -- Display results
  framework.display_results()

  return string.format("Tests completed: %d passed, %d failed",
    framework.results.passed,
    framework.results.failed)
end

-- Add a command to run specific test groups
function M.run_group(group)
  framework.reset_results()

  if group == "parser" then
    parser_tests.test_parse_chat_buffer()
    parser_tests.test_message_formatting()
    parser_tests.test_placeholder_replacement()
  elseif group == "config" then
    config_tests.test_config_loading()
    config_tests.test_api_key_management()
  elseif group == "integration" then
    integration_tests.test_chat_flow()
    integration_tests.test_error_handling()
  elseif group == "fileutils" then -- Add this block
    fileutils_tests.test_expand_paths()
    fileutils_tests.test_invalid_paths()
    fileutils_tests.test_snapshot_expansion()
  else
    vim.notify("Unknown test group: " .. group, vim.log.levels.ERROR)
    return
  end

  framework.display_results()
end

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

return M
