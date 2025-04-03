local M = {}

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

  -- Change marker to show it's in progress
  vim.api.nvim_buf_set_lines(
    buffer_id,
    start_line,
    start_line + 1,
    false,
    { ">>> snapshotting" }
  )

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
  local result = { ">>> snapshotted [" .. timestamp .. "]" }

  -- Add original file paths first
  for _, path in ipairs(file_paths) do
    table.insert(result, path)
  end
  table.insert(result, "") -- Empty line after file paths

  -- Expand file paths and add file contents
  for _, path_pattern in ipairs(file_paths) do
    local expanded_paths = require('nai.fileutils.include').expand_paths(path_pattern)
    for _, path in ipairs(expanded_paths) do
      -- Read file content with header
      local file_header = "==> " .. path .. " <=="
      local file_content = require('nai.fileutils.include').read_file(path)

      -- Get file extension for syntax highlighting
      local ext = vim.fn.fnamemodify(path, ":e")
      local file_type = ""

      -- Map common extensions to syntax types
      if ext == "lua" then
        file_type = "lua"
      elseif ext == "py" then
        file_type = "python"
      elseif ext == "js" then
        file_type = "javascript"
      elseif ext == "ts" then
        file_type = "typescript"
      elseif ext == "html" then
        file_type = "html"
      elseif ext == "css" then
        file_type = "css"
      elseif ext == "json" then
        file_type = "json"
      elseif ext == "md" then
        file_type = "markdown"
      elseif ext == "rb" then
        file_type = "ruby"
      elseif ext == "go" then
        file_type = "go"
      elseif ext == "rs" then
        file_type = "rust"
      elseif ext == "c" or ext == "h" then
        file_type = "c"
      elseif ext == "cpp" or ext == "hpp" then
        file_type = "cpp"
      elseif ext == "sh" then
        file_type = "bash"
      end

      -- Add to results with proper formatting
      table.insert(result, file_header)
      table.insert(result, "```" .. file_type)

      -- Split the file content into lines and add them individually
      local content_lines = vim.split(file_content, "\n")
      for _, content_line in ipairs(content_lines) do
        table.insert(result, content_line)
      end

      -- Close the code block and add spacing
      table.insert(result, "```")
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

-- Check if there are unexpanded snapshot blocks in buffer
function M.has_unexpanded_snapshot_blocks(buffer_id)
  local lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)

  for _, line in ipairs(lines) do
    -- Only match exact ">>> snapshot" and not ones with timestamps
    if line == ">>> snapshot" then
      return true
    end
  end

  return false
end

return M
