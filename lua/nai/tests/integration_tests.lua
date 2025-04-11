-- lua/nai/tests/integration_tests.lua
local M = {}
local framework = require('nai.tests.framework')
local mock_api = require('nai.tests.mock_api')

-- Test full chat flow
function M.test_chat_flow()
  return framework.run_test("Integration: Chat flow", function()
    -- Install API mocks that succeed
    mock_api.install_mocks(true)

    -- Create a test buffer
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      ">>> system",
      "You are a test assistant.",
      "",
      ">>> user",
      "Test message",
      ""
    })

    -- Activate the buffer
    require('nai.buffer').activate_buffer(bufnr)

    -- Set current buffer
    vim.api.nvim_set_current_buf(bufnr)

    -- Run chat
    local nai = require('nai')
    nai.chat({ range = 0 })

    -- Wait for async completion
    vim.wait(500, function() return nai.active_request == nil end)

    -- Get buffer content
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local content = table.concat(lines, "\n")

    -- Restore original functions
    mock_api.restore_originals()

    -- Clean up
    vim.api.nvim_buf_delete(bufnr, { force = true })

    -- Check for assistant response
    local success, err = framework.assert_contains(content, "<<< assistant", "Buffer should contain assistant message")
    if not success then return false, err end

    return true
  end)
end

-- Test error handling
function M.test_error_handling()
  return framework.run_test("Integration: Error handling", function()
    -- Install API mocks that fail
    mock_api.install_mocks(false)

    -- Create a test buffer
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      ">>> user",
      "Test message that should fail",
      ""
    })

    -- Activate the buffer
    require('nai.buffer').activate_buffer(bufnr)

    -- Set current buffer
    vim.api.nvim_set_current_buf(bufnr)

    -- Run chat
    local nai = require('nai')
    nai.chat({ range = 0 })

    -- Wait for async completion
    vim.wait(500, function() return nai.active_request == nil end)

    -- Get buffer content
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local content = table.concat(lines, "\n")

    -- Restore original functions
    mock_api.restore_originals()

    -- Clean up
    vim.api.nvim_buf_delete(bufnr, { force = true })

    -- Check for error message
    local success, err = framework.assert_contains(content, "Error", "Buffer should contain error message")
    if not success then return false, err end

    return true
  end)
end

return M
