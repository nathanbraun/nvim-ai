local M = {}
local utils = require('nai.utils')

function M.expand_paths(path_pattern)
  local expanded_path = vim.fn.expand(path_pattern)

  -- If it doesn't contain wildcards, just return the expanded path
  if not path_pattern:match("[*?%[%]]") then
    return { expanded_path }
  end

  -- Check if we need recursive globbing (contains **)
  local recursive = path_pattern:match("**") ~= nil

  -- For recursive patterns, use find command
  if recursive then
    -- Extract base directory (everything before **)
    local base_dir_pattern = "^(.-)%*%*"
    local base_dir = path_pattern:match(base_dir_pattern) or "."
    base_dir = vim.fn.fnamemodify(base_dir, ":p:h") -- Get absolute path

    -- Extract pattern after **
    local after_pattern = path_pattern:match(".*%*%*(.*)")
    local file_pattern = after_pattern or "*"
    if file_pattern == "" then file_pattern = "*" end

    -- Build and execute find command
    local cmd = string.format('find "%s" -type f -name "%s" 2>/dev/null',
      base_dir, file_pattern)

    local output = vim.fn.system(cmd)

    -- Process output into a table of files
    local files = {}
    for file in string.gmatch(output, "[^\n]+") do
      table.insert(files, file)
    end

    return files
  else
    -- For non-recursive, use standard glob
    return vim.fn.glob(expanded_path, false, true)
  end
end

-- Read file content and format it with header
function M.read_file_with_header(filepath)
  -- Add a maximum file size check (e.g., 500KB)
  local max_size = 500 * 1024 -- 500KB

  -- Check if file exists and is readable
  if vim.fn.filereadable(filepath) ~= 1 then
    return "==> " .. filepath .. " <==\nFile not found or not readable"
  end

  -- Check file size
  local size = vim.fn.getfsize(filepath)
  if size > max_size then
    return "==> " .. filepath .. " <==\nFile too large (" .. math.floor(size / 1024) .. "KB), content truncated\n\n" ..
        table.concat(vim.fn.readfile(filepath, "", max_size), "\n") .. "\n\n[File truncated...]"
  end

  -- Skip certain binary file types
  local ext = vim.fn.fnamemodify(filepath, ":e"):lower()
  local binary_exts = {
    "jpg", "jpeg", "png", "gif", "bmp", "pdf", "zip", "tar",
    "gz", "exe", "bin", "dll", "so", "dylib"
  }

  for _, bext in ipairs(binary_exts) do
    if ext == bext then
      return "==> " .. filepath .. " <==\nBinary file, content not displayed"
    end
  end

  -- Read file content
  local success, lines = pcall(vim.fn.readfile, filepath)
  if not success or #lines == 0 then
    return "==> " .. filepath .. " <==\nEmpty file or cannot read content"
  end

  -- Format with header
  return "==> " .. filepath .. " <==\n" .. table.concat(lines, "\n")
end

-- Process include statement with multiple file paths
function M.process_include_block(lines)
  local result = {}
  local file_paths = {}
  local additional_text = {}
  local processing_files = true

  for _, line in ipairs(lines) do
    if processing_files and line:match("^%s*$") then
      -- Empty line indicates end of file paths
      processing_files = false
    elseif processing_files then
      -- Process as file path
      local expanded_paths = M.expand_paths(line)
      for _, path in ipairs(expanded_paths) do
        table.insert(file_paths, path)
      end
    else
      -- Process as additional text
      table.insert(additional_text, line)
    end
  end

  -- Add file contents
  for _, path in ipairs(file_paths) do
    table.insert(result, M.read_file_with_header(path))
  end

  -- Add additional text if any
  if #additional_text > 0 then
    table.insert(result, table.concat(additional_text, "\n"))
  end

  return table.concat(result, "\n\n")
end

return M
