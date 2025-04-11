local M = {}
local utils = require('nai.utils')
local error_utils = require('nai.utils.error')
local path = require('nai.utils.path')

function M.expand_paths(path_pattern)
  -- Set a reasonable maximum file limit to prevent accidental massive expansions
  local MAX_FILES = _G.TEST_MAX_FILES or 100

  -- If it doesn't contain wildcards, just return the expanded path
  if not path_pattern:match("[*?%[%]]") then
    local expanded_path = path.expand(path_pattern)
    return { expanded_path }
  end

  -- Use vim's built-in glob for non-recursive patterns (more cross-platform)
  if not path_pattern:match("**") then
    -- This is the key part - we need to ensure we're only getting matching files
    local files = vim.fn.glob(path_pattern, false, true)
    if #files > MAX_FILES then
      vim.notify(string.format("Warning: Pattern '%s' matched %d files, limiting to %d. Use a more specific pattern.",
        path_pattern, #files, MAX_FILES), vim.log.levels.WARN)
      return vim.list_slice(files, 1, MAX_FILES)
    end
    return files
  end

  -- For recursive patterns, use platform-specific approach
  local base_dir = path_pattern:match("^(.-)%*%*") or "."
  base_dir = vim.fn.fnamemodify(path.expand(base_dir), ":p:h") -- Get absolute path

  -- Safety check: prevent searching from root or very broad directories
  if base_dir == "/" or base_dir == "\\" or base_dir == "C:\\" or #base_dir <= 3 then
    vim.notify(
    string.format(
      "Safety warning: Pattern '%s' would search from root or very broad directory. Please use a more specific pattern.",
      path_pattern), vim.log.levels.ERROR)
    return {}
  end

  -- Extract pattern after **
  local after_pattern = path_pattern:match("%*%*(.*)")

  -- Handle the case where after_pattern is nil (pattern ends with **)
  if not after_pattern then
    after_pattern = ""
  end

  -- Remove leading separator if present
  if after_pattern ~= "" and (after_pattern:sub(1, 1) == "/" or after_pattern:sub(1, 1) == "\\") then
    after_pattern = after_pattern:sub(2)
  end

  -- Default pattern if none specified
  local file_pattern = after_pattern ~= "" and after_pattern or "*"

  -- Try to use vim's built-in globpath first (most cross-platform)
  local glob_result = vim.fn.globpath(base_dir, "**/" .. file_pattern, false, true)

  -- Check if we have too many results
  if #glob_result > MAX_FILES then
    vim.notify(string.format("Warning: Pattern '%s' matched %d files, limiting to %d. Use a more specific pattern.",
      path_pattern, #glob_result, MAX_FILES), vim.log.levels.WARN)
    return vim.list_slice(glob_result, 1, MAX_FILES)
  end

  if #glob_result > 0 then
    return glob_result
  end

  -- Fallback to platform-specific commands if vim's globpath didn't work
  local files = {}

  -- Add error handling around platform-specific commands
  local success, result = pcall(function()
    if path.is_windows then
      -- Improved PowerShell command to ensure we only get matching files
      local ps_cmd = string.format(
        'powershell -NoProfile -Command "Get-ChildItem -Path \"%s\" -Recurse -File | Where-Object { $_.FullName -like \"*%s\" } | Select-Object -First %d | ForEach-Object { $_.FullName }"',
        base_dir:gsub("/", "\\"),
        file_pattern:gsub("/", "\\"),
        MAX_FILES
      )

      local output = vim.fn.system(ps_cmd)

      -- Process output into a table of files
      for file in string.gmatch(output, "[^\r\n]+") do
        if file ~= "" then
          table.insert(files, file)
        end
      end
    else
      -- Unix find command with better pattern matching
      -- Use a more specific find command that properly matches the pattern
      local cmd
      if file_pattern == "*" then
        -- If the pattern is just "*", match all files
        cmd = string.format('find "%s" -type f -print | head -n %d 2>/dev/null',
          base_dir, MAX_FILES)
      else
        -- Otherwise, use -name for more precise matching
        cmd = string.format('find "%s" -type f -name "%s" -print | head -n %d 2>/dev/null',
          base_dir, file_pattern, MAX_FILES)
      end

      local output = vim.fn.system(cmd)

      -- Process output into a table of files
      for file in string.gmatch(output, "[^\n]+") do
        if file ~= "" then
          table.insert(files, file)
        end
      end
    end

    -- Check if we might have hit the limit
    if #files >= MAX_FILES then
      vim.notify(
      string.format(
        "Warning: Pattern '%s' may match more than %d files. Results have been limited. Use a more specific pattern.",
        path_pattern, MAX_FILES), vim.log.levels.WARN)
    end

    return files
  end)

  if not success then
    vim.notify("Error expanding path pattern: " .. path_pattern .. "\n" .. result, vim.log.levels.WARN)
    return {}
  end

  if #files == 0 then
    vim.notify("No files found with pattern: " .. path_pattern, vim.log.levels.WARN)
  end

  return files
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

-- Process reference statement with multiple file paths
function M.process_reference_block(lines)
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

function M.read_file(filepath)
  -- Check if file exists and is readable
  if vim.fn.filereadable(filepath) ~= 1 then
    return error_utils.log("File not found or not readable: " .. filepath, error_utils.LEVELS.WARNING)
  end

  -- Check file size
  local max_size = 500 * 1024 -- 500KB
  local size = vim.fn.getfsize(filepath)
  if size > max_size then
    error_utils.log("File exceeds size limit, truncating: " .. filepath, error_utils.LEVELS.WARNING, {
      size = size,
      max_size = max_size
    })
    return table.concat(vim.fn.readfile(filepath, "", max_size), "\n") ..
        "\n\n[File truncated...]"
  end

  -- Skip certain binary file types
  local ext = vim.fn.fnamemodify(filepath, ":e"):lower()
  local binary_exts = {
    "jpg", "jpeg", "png", "gif", "bmp", "pdf", "zip", "tar",
    "gz", "exe", "bin", "dll", "so", "dylib"
  }

  for _, bext in ipairs(binary_exts) do
    if ext == bext then
      return error_utils.log("Binary file, content not displayed: " .. filepath, error_utils.LEVELS.INFO)
    end
  end

  -- Read file content
  local success, lines = pcall(vim.fn.readfile, filepath)
  if not success or #lines == 0 then
    return error_utils.log("Empty file or cannot read content: " .. filepath, error_utils.LEVELS.WARNING)
  end

  -- Return content without header
  return table.concat(lines, "\n")
end

return M
