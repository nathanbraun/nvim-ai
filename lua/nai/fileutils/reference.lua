local M = {}
local utils = require('nai.utils')
local error_utils = require('nai.utils.error')
local path = require('nai.utils.path')
local config = require('nai.config')

function M.expand_paths(path_pattern)
  -- Set a reasonable maximum file limit to prevent accidental massive expansions
  local MAX_FILES = _G.TEST_MAX_FILES or 100

  -- Debug info
  if config.options.debug and config.options.debug.enabled then
    vim.notify("DEBUG: Original path_pattern: " .. path_pattern, vim.log.levels.INFO)
  end

  -- Check for wildcards, but be smarter about brackets
  local has_wildcards = false
  
  -- Check for * and ? wildcards
  if path_pattern:match("[*?]") then
    has_wildcards = true
  end
  
  -- Check for bracket wildcards (character classes), but not literal brackets
  if path_pattern:match("%[") then
    for bracket_content in path_pattern:gmatch("%[([^%]]+)%]") do
      local is_char_class = false
      
      -- Check for ranges (a-z, 0-9, etc.)
      if bracket_content:match("[%w]%-[%w]") then
        is_char_class = true
      end
      
      -- Check for negation patterns
      if bracket_content:match("^[!^]") then
        is_char_class = true
      end
      
      -- Check for single character
      if #bracket_content == 1 then
        is_char_class = true
      end
      
      -- For multi-character content without ranges or negation
      if #bracket_content > 1 and not bracket_content:match("%-") and not bracket_content:match("^[!^]") then
        -- Improved heuristic: 
        -- Character classes tend to be short (2-4 chars) and either:
        -- - All letters: [abc], [xyz] 
        -- - All numbers: [123], [456]
        -- - Mixed but short: [a1b]
        -- 
        -- Directory names tend to be longer and word-like:
        -- - [id], [component], [slug], [userId], etc.
        
        if #bracket_content <= 4 then
          -- Short patterns are likely character classes
          -- But make an exception for common directory name patterns
          local common_dir_patterns = {
            "id", "slug", "key", "name", "type", "page", "tab"
          }
          
          local is_common_dir = false
          for _, pattern in ipairs(common_dir_patterns) do
            if bracket_content == pattern then
              is_common_dir = true
              break
            end
          end
          
          if not is_common_dir then
            is_char_class = true
          end
        else
          -- Longer patterns (5+ chars) are almost certainly directory names
          is_char_class = false
        end
      end
      
      if is_char_class then
        has_wildcards = true
        break
      end
    end
  end

  -- If it doesn't contain wildcards, just return the expanded path
  if not has_wildcards then
    local expanded_path = path.expand(path_pattern)
    return { expanded_path }
  end

  -- Rest of the function remains the same...
  -- Simple case: non-recursive wildcards (no **)
  if not path_pattern:match("**") then
    -- Just use vim's glob directly - it's reliable for simple patterns
    local files = vim.fn.glob(path_pattern, false, true)

    if #files > MAX_FILES then
      vim.notify(string.format("Warning: Pattern '%s' matched %d files, limiting to %d. Use a more specific pattern.",
        path_pattern, #files, MAX_FILES), vim.log.levels.WARN)
      return vim.list_slice(files, 1, MAX_FILES)
    end

    return files
  end

  -- For recursive patterns, we need to be more careful
  -- Extract the base directory (everything before **)
  local base_pattern = path_pattern:match("^(.-)%*%*")
  if not base_pattern then
    -- If there's no match (shouldn't happen since we checked for ** above)
    return vim.fn.glob(path_pattern, false, true)
  end

  -- Properly expand the base directory
  local base_dir = vim.fn.fnamemodify(path.expand(base_pattern), ":p:h")

  -- Safety check: prevent searching from root or very broad directories
  if base_dir == "/" or base_dir == "\\" or base_dir == "C:\\" or #base_dir <= 3 then
    vim.notify(
      string.format(
        "Safety warning: Pattern '%s' would search from root or very broad directory. Please use a more specific pattern.",
        path_pattern), vim.log.levels.ERROR)
    return {}
  end

  -- Extract the pattern after **
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

  -- Use vim's globpath for recursive search
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
