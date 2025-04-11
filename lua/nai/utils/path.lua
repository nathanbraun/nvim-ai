-- lua/nai/utils/path.lua
local M = {}

-- Detect platform
M.is_windows = vim.fn.has('win32') == 1 or vim.fn.has('win64') == 1
M.separator = M.is_windows and '\\' or '/'

-- Normalize path separators
function M.normalize(path)
  if M.is_windows then
    -- Convert forward slashes to backslashes for Windows
    return path:gsub('/', '\\')
  else
    -- Convert backslashes to forward slashes for Unix
    return path:gsub('\\', '/')
  end
end

-- Join path components in a platform-independent way
function M.join(...)
  local path_sep = M.is_windows and '\\' or '/'
  local result = table.concat({ ... }, path_sep)
  return M.normalize(result)
end

-- Get the home directory in a platform-independent way
function M.home()
  return vim.fn.expand('~')
end

-- Expand a path with environment variables and ~
function M.expand(path)
  return vim.fn.expand(path)
end

-- Check if a path exists
function M.exists(path)
  return vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1
end

-- Create a directory and its parents if they don't exist
function M.mkdir(path)
  if not M.exists(path) then
    vim.fn.mkdir(path, 'p')
    return true
  end
  return false
end

function M.tmpname()
  if M.is_windows then
    -- On Windows, os.tmpname() returns a name in the root directory, which isn't writable
    -- Instead, use the TEMP environment variable
    local temp_dir = os.getenv("TEMP") or os.getenv("TMP") or "C:\\Windows\\Temp"
    return temp_dir .. "\\" .. os.time() .. "_" .. math.random(1000) .. ".tmp"
  else
    -- On Unix, os.tmpname() works fine
    return os.tmpname()
  end
end

return M
