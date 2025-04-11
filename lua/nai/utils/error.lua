-- lua/nai/utils/error.lua
local M = {}

-- Error levels
M.LEVELS = {
  INFO = 1,
  WARNING = 2,
  ERROR = 3,
  CRITICAL = 4
}

-- Log an error with optional context
function M.log(message, level, context)
  level = level or M.LEVELS.ERROR

  -- Add debug information if available
  local debug_info = ""
  if context then
    if type(context) == "string" then
      debug_info = " (" .. context .. ")"
    elseif type(context) == "table" then
      debug_info = " (" .. vim.inspect(context) .. ")"
    end
  end

  -- Log to Neovim's log
  if level >= M.LEVELS.ERROR then
    vim.api.nvim_err_writeln("[nvim-ai] " .. message .. debug_info)
  end

  -- Notify the user based on severity
  local notify_level
  if level == M.LEVELS.INFO then
    notify_level = vim.log.levels.INFO
  elseif level == M.LEVELS.WARNING then
    notify_level = vim.log.levels.WARN
  elseif level == M.LEVELS.ERROR then
    notify_level = vim.log.levels.ERROR
  elseif level == M.LEVELS.CRITICAL then
    notify_level = vim.log.levels.ERROR
  end

  vim.notify("[nvim-ai] " .. message, notify_level)

  return message -- Return for chaining
end

-- Handle API errors specifically
function M.handle_api_error(response, provider)
  if not response then
    return M.log("Empty response from API", M.LEVELS.ERROR, { provider = provider })
  end

  -- Try to parse the response as JSON
  local success, parsed = pcall(vim.json.decode, response)
  if not success then
    return M.log("Failed to parse API response", M.LEVELS.ERROR, {
      provider = provider,
      response_preview = string.sub(response, 1, 100) -- Show first 100 chars
    })
  end

  -- Extract error message based on provider format
  local error_msg = "Unknown API error"

  if parsed.error then
    if parsed.error.message then
      error_msg = parsed.error.message
    elseif type(parsed.error) == "string" then
      error_msg = parsed.error
    end
  end

  return M.log("API Error: " .. error_msg, M.LEVELS.ERROR, {
    provider = provider,
    error_detail = parsed.error
  })
end

-- Check for required executables
function M.check_executable(name, suggestion)
  local path = require('nai.utils.path')

  -- Check if executable exists, handling platform differences
  local executable_exists

  if path.is_windows then
    -- On Windows, check for both name and name.exe
    executable_exists = vim.fn.executable(name) == 1 or vim.fn.executable(name .. '.exe') == 1
  else
    executable_exists = vim.fn.executable(name) == 1
  end

  if not executable_exists then
    local msg = "Required executable '" .. name .. "' not found"
    if suggestion then
      msg = msg .. ". " .. suggestion
    end
    M.log(msg, M.LEVELS.WARNING)
    return false
  end
  return true
end

-- Validate buffer operations
function M.validate_buffer(bufnr, operation)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    M.log("Invalid buffer for operation: " .. (operation or "unknown"), M.LEVELS.ERROR)
    return false
  end
  return true
end

return M
