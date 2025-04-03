local M = {}
local include = require('nai.fileutils.include')

-- Process snapshot block for API requests
function M.process_snapshot_block(lines)
  -- For API requests, just use the text that's already in the buffer
  -- since we've already expanded the snapshot
  return table.concat(lines, "\n")
end

-- Create and expand a snapshot in the buffer
function M.expand_snapshot_in_buffer(buffer_id, start_line, end_line)
  -- Get the snapshot block lines
  local lines = vim.api.nvim_buf_get_lines(buffer_id, start_line, end_line, false)

  -- Parse file paths (similar to include)
  local file_paths = {}
  local additional_text = {}
  local processing_files = true
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")

  -- Skip the first line which contains the snapshot marker
  for i = 2, #lines do
    local line = lines[i]
    if processing_files and line:match("^%s*$") then
      -- Empty line indicates end of file paths
      processing_files = false
    elseif processing_files and line ~= "" then
      -- Process as file path
      table.insert(file_paths, line)
    elseif not processing_files then
      -- Process as additional text
      table.insert(additional_text, line)
    end
  end

  -- Build the expanded snapshot content
  local result = { ">>> snapshot [" .. timestamp .. "]", "" }

  -- Expand file paths and add file contents
  for _, path_pattern in ipairs(file_paths) do
    local expanded_paths = include.expand_paths(path_pattern)
    for _, path in ipairs(expanded_paths) do
      local file_content = include.read_file_with_header(path)

      -- Split the file content into lines and add them individually
      local content_lines = vim.split(file_content, "\n")
      for _, content_line in ipairs(content_lines) do
        table.insert(result, content_line)
      end
      table.insert(result, "") -- Empty line between files
    end
  end

  -- Add any additional text that was after the file paths
  if #additional_text > 0 then
    for _, line in ipairs(additional_text) do
      table.insert(result, line)
    end
  end

  -- Replace the snapshot block with the expanded content
  vim.api.nvim_buf_set_lines(buffer_id, start_line, end_line, false, result)

  -- Return the number of lines in the new content
  return #result
end

return M
