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

  -- Parse file paths (similar to reference)
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
  local reference_module = require('nai.fileutils.reference')
  for _, path_pattern in ipairs(file_paths) do
    -- Wrap path expansion in pcall to catch any errors
    local success, expanded_paths = pcall(reference_module.expand_paths, path_pattern)

    if not success then
      -- Log the error and continue with other paths
      table.insert(result, "==> Error expanding path: " .. path_pattern .. " <==")
      table.insert(result, "Error: " .. tostring(expanded_paths))
      table.insert(result, "")
      goto continue
    end

    if #expanded_paths == 0 then
      -- No files found for this pattern
      table.insert(result, "==> No files found for: " .. path_pattern .. " <==")
      table.insert(result, "")
      goto continue
    end

    for _, path in ipairs(expanded_paths) do
      -- Wrap file reading in pcall to catch any errors
      local file_header = "==> " .. path .. " <=="
      local success, file_content = pcall(reference_module.read_file, path)

      if not success then
        -- Log the error and continue with other files
        table.insert(result, file_header)
        table.insert(result, "Error reading file: " .. tostring(file_content))
        table.insert(result, "")
        goto continue_file
      end

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

      -- Special handling for markdown files - don't wrap in code blocks
      if file_type == "markdown" then
        -- Split the file content into lines and add them directly
        local content_lines = vim.split(file_content, "\n")
        for _, content_line in ipairs(content_lines) do
          table.insert(result, content_line)
        end
      else
        -- For non-markdown files, wrap in code blocks with syntax highlighting
        table.insert(result, "```" .. file_type)

        -- Split the file content into lines and add them individually
        local content_lines = vim.split(file_content, "\n")
        for _, content_line in ipairs(content_lines) do
          table.insert(result, content_line)
        end

        -- Close the code block
        table.insert(result, "```")
      end

      table.insert(result, "") -- Empty line between files

      ::continue_file::
    end

    ::continue::
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
  local constants = require('nai.constants')

  for _, line in ipairs(lines) do
    if line:match("^" .. vim.pesc(constants.MARKERS.IGNORE or "```ignore") .. "$") then
      in_ignored_block = true
    elseif in_ignored_block and line:match("^" .. vim.pesc(constants.MARKERS.IGNORE_END or "```") .. "$") then
      in_ignored_block = false
    elseif vim.trim(line) == ">>> snapshot" then
      return true
    end
  end

  return false
end

return M
