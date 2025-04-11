-- lua/nai/tests/framework.lua
local M = {}

-- Test results tracking
M.results = {
  passed = 0,
  failed = 0,
  tests = {}
}

-- Test assertion functions
function M.assert_equals(actual, expected, message)
  if actual == expected then
    return true
  else
    return false, string.format("%s: expected %s, got %s",
      message or "Values not equal",
      vim.inspect(expected),
      vim.inspect(actual))
  end
end

function M.assert_contains(haystack, needle, message)
  if type(haystack) == "string" and haystack:find(needle, 1, true) then
    return true
  elseif type(haystack) == "table" then
    for _, v in pairs(haystack) do
      if v == needle then
        return true
      end
    end
  end
  return false, string.format("%s: %s not found in %s",
    message or "Value not found",
    vim.inspect(needle),
    vim.inspect(haystack))
end

function M.assert_type(value, expected_type, message)
  if type(value) == expected_type then
    return true
  else
    return false, string.format("%s: expected type %s, got %s",
      message or "Type mismatch",
      expected_type,
      type(value))
  end
end

-- Test runner
function M.run_test(name, test_fn)
  local status, err = pcall(function()
    local result, err_msg = test_fn()
    if result == false then
      error(err_msg or "Test failed with no error message")
    end
  end)

  local test_result = {
    name = name,
    passed = status,
    error = not status and err or nil
  }

  table.insert(M.results.tests, test_result)

  if status then
    M.results.passed = M.results.passed + 1
  else
    M.results.failed = M.results.failed + 1
  end

  return status, err
end

-- Display test results in a nice buffer
function M.display_results()
  local buf = vim.api.nvim_create_buf(false, true)

  local lines = {
    "nvim-ai Test Results",
    "==================",
    "",
    string.format("Tests: %d | Passed: %d | Failed: %d",
      #M.results.tests,
      M.results.passed,
      M.results.failed),
    ""
  }

  for i, test in ipairs(M.results.tests) do
    local status = test.passed and "✓ PASS" or "✗ FAIL"
    local color = test.passed and "DiagnosticOk" or "DiagnosticError"

    table.insert(lines, string.format("%s: %s", status, test.name))

    if not test.passed then
      table.insert(lines, "  " .. test.error)
    end
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Create highlighting
  local ns_id = vim.api.nvim_create_namespace('nai_test_results')
  for i, line in ipairs(lines) do
    if line:match("^✓") then
      vim.api.nvim_buf_add_highlight(buf, ns_id, "DiagnosticOk", i - 1, 0, 6)
    elseif line:match("^✗") then
      vim.api.nvim_buf_add_highlight(buf, ns_id, "DiagnosticError", i - 1, 0, 6)
    elseif line:match("^nvim%-ai Test Results") then
      vim.api.nvim_buf_add_highlight(buf, ns_id, "Title", i - 1, 0, -1)
    end
  end

  -- Open in a nice floating window
  local width = 80
  local height = #lines
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = "Test Results",
    title_pos = "center"
  })

  -- Set buffer options
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")

  -- Add keymapping to close the window
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':close<CR>', { noremap = true, silent = true })

  return buf, win
end

-- Reset test results
function M.reset_results()
  M.results = {
    passed = 0,
    failed = 0,
    tests = {}
  }
end

return M
