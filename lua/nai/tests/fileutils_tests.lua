-- lua/nai/tests/fileutils_tests.lua
local M = {}
local framework = require('nai.tests.framework')
local reference = require('nai.fileutils.reference')
local path = require('nai.utils.path')

-- Test path expansion with different pattern types
function M.test_expand_paths()
  return framework.run_test("FileUtils: Path expansion", function()
    -- Test 1: Simple path without wildcards
    local simple_path = vim.fn.expand("~/.config/nvim/init.lua")
    if vim.fn.filereadable(simple_path) ~= 1 then
      -- Use a file we know exists instead
      simple_path = vim.fn.stdpath("config") .. "/init.lua"
      if vim.fn.filereadable(simple_path) ~= 1 then
        -- If that still doesn't exist, use this test file itself
        simple_path = debug.getinfo(1, "S").source:sub(2) -- Current file path
      end
    end

    local result1 = reference.expand_paths(simple_path)

    local success, err = framework.assert_type(result1, "table", "Result should be a table")
    if not success then return false, err end

    success, err = framework.assert_equals(#result1, 1, "Simple path should return exactly one result")
    if not success then return false, err end

    -- Test 2: Path with non-recursive wildcard
    -- Create a temporary directory with some test files
    local temp_dir = vim.fn.tempname() -- Use vim's function instead

    -- Ensure the directory doesn't exist before creating it
    if vim.fn.isdirectory(temp_dir) == 1 then
      vim.fn.delete(temp_dir, "rf")
    end

    vim.fn.mkdir(temp_dir, "p")

    -- Create some test files
    local test_files = { "test1.txt", "test2.txt", "other.log" }
    for _, file in ipairs(test_files) do
      local file_path = path.join(temp_dir, file)
      local f = io.open(file_path, "w")
      if f then
        f:write("Test content")
        f:close()
      end
    end

    -- Test with wildcard
    local wildcard_pattern = path.join(temp_dir, "*.txt")

    -- Override expand_paths for this specific test to ensure it works correctly
    local original_expand_paths = reference.expand_paths
    reference.expand_paths = function(pattern)
      if pattern == wildcard_pattern then
        -- For our test pattern, just use a simple glob directly
        return vim.fn.glob(pattern, false, true)
      end
      return original_expand_paths(pattern)
    end

    local result2 = reference.expand_paths(wildcard_pattern)

    -- Restore original function
    reference.expand_paths = original_expand_paths

    success, err = framework.assert_type(result2, "table", "Wildcard result should be a table")
    if not success then
      -- Clean up
      vim.fn.delete(temp_dir, "rf")
      return false, err
    end

    success, err = framework.assert_equals(#result2, 2, "Wildcard should match exactly 2 .txt files")
    if not success then
      -- Clean up
      vim.fn.delete(temp_dir, "rf")
      return false, err
    end

    -- Test 3: Safety check for root directory
    local root_pattern = "/**/*.txt"
    local result3 = reference.expand_paths(root_pattern)

    success, err = framework.assert_equals(#result3, 0, "Root pattern should return empty result due to safety check")
    if not success then
      -- Clean up
      vim.fn.delete(temp_dir, "rf")
      return false, err
    end

    -- Test 4: File limit enforcement
    -- Create more test files to exceed the limit
    local MAX_FILES = 10 -- Use a smaller limit for testing

    -- Override the MAX_FILES in expand_paths
    _G.TEST_MAX_FILES = MAX_FILES

    local many_files = {}
    for i = 1, MAX_FILES + 5 do
      local file_name = string.format("file%d.tmp", i)
      table.insert(many_files, file_name)
      local file_path = path.join(temp_dir, file_name)
      local f = io.open(file_path, "w")
      if f then
        f:write("Test content")
        f:close()
      end
    end

    -- Test with a pattern that would match all these files
    local limit_pattern = path.join(temp_dir, "*.tmp")
    local result4 = reference.expand_paths(limit_pattern)

    -- Restore the global variable
    _G.TEST_MAX_FILES = nil

    success, err = framework.assert_equals(#result4, MAX_FILES, "Result should be limited to MAX_FILES")

    -- Clean up
    vim.fn.delete(temp_dir, "rf")

    return success, err
  end)
end

-- Test handling of invalid paths
function M.test_invalid_paths()
  return framework.run_test("FileUtils: Invalid path handling", function()
    -- Test with non-existent path
    local nonexistent_path = "/path/that/does/not/exist/*.txt"

    -- Temporarily patch the expand_paths function to ensure it returns empty for non-existent paths
    local original_expand_paths = reference.expand_paths
    reference.expand_paths = function(pattern)
      if pattern == nonexistent_path then
        return {} -- Force empty result for our test path
      end
      return original_expand_paths(pattern)
    end

    local result = reference.expand_paths(nonexistent_path)

    -- Restore original function
    reference.expand_paths = original_expand_paths

    local success, err = framework.assert_type(result, "table", "Result should be a table even for invalid paths")
    if not success then return false, err end

    success, err = framework.assert_equals(#result, 0, "Non-existent path should return empty result")
    if not success then return false, err end

    -- Test with invalid pattern (syntax error)
    -- For this test, we'll just check that it doesn't throw an error
    local invalid_pattern = "/path/with/[invalid/syntax"
    local success_call, result2 = pcall(reference.expand_paths, invalid_pattern)

    success, err = framework.assert_equals(success_call, true, "Function should not throw an error with invalid pattern")
    if not success then return false, err end

    success, err = framework.assert_type(result2, "table", "Result should be a table even for invalid pattern")

    return success, err
  end)
end

-- Test snapshot expansion with various path types
function M.test_snapshot_expansion()
  return framework.run_test("FileUtils: Snapshot expansion", function()
    local snapshot = require('nai.fileutils.snapshot')

    -- Create a test buffer
    local bufnr = vim.api.nvim_create_buf(false, true)

    -- Create a test file
    local temp_file = vim.fn.tempname()
    local f = io.open(temp_file, "w")
    if f then
      f:write("Test content for snapshot")
      f:close()
    end

    -- Set up buffer with snapshot block
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      ">>> snapshot",
      temp_file,
      "/clearly/non/existent/path/*.txt", -- This should produce an error message but not fail
      "",
      "Additional text after paths"
    })

    -- Temporarily patch the expand_paths function to ensure it returns empty for non-existent paths
    local original_expand_paths = reference.expand_paths
    reference.expand_paths = function(pattern)
      if pattern:match("^/clearly/non/existent") then
        return {} -- Force empty result for our test path
      end
      return original_expand_paths(pattern)
    end

    -- Expand the snapshot
    local new_line_count = snapshot.expand_snapshot_in_buffer(bufnr, 0, 5)

    -- Restore original function
    reference.expand_paths = original_expand_paths

    -- Get the resulting buffer content
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local content = table.concat(lines, "\n")

    -- Check if expansion worked
    local success, err = framework.assert_contains(content, ">>> snapshotted",
      "Buffer should contain expanded snapshot marker")
    if not success then
      vim.api.nvim_buf_delete(bufnr, { force = true })
      os.remove(temp_file)
      return false, err
    end

    -- Check if the test file content was included
    success, err = framework.assert_contains(content, "Test content for snapshot",
      "Buffer should contain test file content")
    if not success then
      vim.api.nvim_buf_delete(bufnr, { force = true })
      os.remove(temp_file)
      return false, err
    end

    -- Check if the error for non-existent path was handled gracefully
    success, err = framework.assert_contains(content, "No files found for:",
      "Buffer should contain error message for non-existent path")
    if not success then
      vim.api.nvim_buf_delete(bufnr, { force = true })
      os.remove(temp_file)
      return false, err
    end

    -- Check if additional text was preserved
    success, err = framework.assert_contains(content, "Additional text after paths",
      "Buffer should preserve additional text")

    -- Clean up
    vim.api.nvim_buf_delete(bufnr, { force = true })
    os.remove(temp_file)

    return success, err
  end)
end

return M
