-- lua/nai/utils/init.lua
local M = {}

-- The existing utilities
M.get_visual_selection = function()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  local start_line, start_col = start_pos[2], start_pos[3]
  local end_line, end_col = end_pos[2], end_pos[3]

  -- Get the lines in the selection
  local lines = vim.fn.getline(start_line, end_line)

  -- Adjust the first and last line to only include the selected text
  if #lines == 0 then
    return ""
  elseif #lines == 1 then
    lines[1] = string.sub(lines[1], start_col, end_col)
  else
    lines[1] = string.sub(lines[1], start_col)
    lines[#lines] = string.sub(lines[#lines], 1, end_col)
  end

  -- Join the lines with newline characters
  return table.concat(lines, "\n")
end

-- Import and expose the indicators module
M.indicators = require('nai.utils.indicators')

return M
