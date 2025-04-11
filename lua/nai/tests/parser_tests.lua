-- lua/nai/tests/parser_tests.lua
local M = {}
local framework = require('nai.tests.framework')
local parser = require('nai.parser')

-- Test parsing of chat buffer
function M.test_parse_chat_buffer()
  return framework.run_test("Parser: Parse chat buffer", function()
    local buffer_content = [[
>>> system
You are a helpful assistant.

>>> user
Hello world!

<<< assistant
Hi there! How can I help you today?
]]

    local messages, chat_config = parser.parse_chat_buffer(buffer_content, 0)

    local success, err = framework.assert_type(messages, "table", "Messages should be a table")
    if not success then return false, err end

    success, err = framework.assert_equals(#messages, 3, "Should have 3 messages")
    if not success then return false, err end

    success, err = framework.assert_equals(messages[1].role, "system", "First message should be system")
    if not success then return false, err end

    success, err = framework.assert_equals(messages[2].role, "user", "Second message should be user")
    if not success then return false, err end

    success, err = framework.assert_equals(messages[3].role, "assistant", "Third message should be assistant")
    if not success then return false, err end

    return true
  end)
end

-- Test message formatting
function M.test_message_formatting()
  return framework.run_test("Parser: Message formatting", function()
    local user_msg = parser.format_user_message("Test message")
    local assistant_msg = parser.format_assistant_message("Test response")

    local success, err = framework.assert_contains(user_msg, ">>> user", "User message should contain marker")
    if not success then return false, err end

    success, err = framework.assert_contains(assistant_msg, "<<< assistant", "Assistant message should contain marker")
    if not success then return false, err end

    success, err = framework.assert_contains(user_msg, "Test message", "User message should contain content")
    if not success then return false, err end

    return true
  end)
end

-- Test placeholder replacement
function M.test_placeholder_replacement()
  return framework.run_test("Parser: Placeholder replacement", function()
    -- Create a temporary buffer with content
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "This is test content",
      "Line 2 of test content",
      ">>> user",
      "Message with placeholder: $FILE_CONTENTS"
    })

    local content = "Message with placeholder: $FILE_CONTENTS"
    local result = parser.replace_placeholders(content, bufnr)

    local expected_content = "Message with placeholder: This is test content\nLine 2 of test content"
    local success, err = framework.assert_equals(result, expected_content,
      "Placeholder should be replaced with buffer content")

    -- Clean up
    vim.api.nvim_buf_delete(bufnr, { force = true })

    return success, err
  end)
end

return M
