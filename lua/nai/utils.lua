-- lua/nai/utils.lua
-- Utility functions

local M = {}

-- Get visual selection
function M.get_visual_selection()
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

-- Insert text at cursor position
function M.insert_text_at_cursor(text)
  local lines = vim.split(text, "\n")
  vim.api.nvim_put(lines, "c", true, true)
end

function M.replace_last_insertion(old_text, new_text)
  -- Save current position
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local line_num, col = cursor_pos[1], cursor_pos[2]

  -- Calculate lines in old and new text
  local old_lines = vim.split(old_text, "\n")
  local new_lines = vim.split(new_text, "\n")

  -- Calculate the region to replace
  local start_line = line_num - #old_lines + 1
  if start_line < 1 then start_line = 1 end

  -- Replace the text
  vim.api.nvim_buf_set_text(0,
    start_line - 1, -- 0-indexed start line
    0,              -- Start column
    line_num - 1,   -- 0-indexed end line
    col,            -- End column
    new_lines
  )

  -- Update cursor position
  local new_line_num = start_line + #new_lines - 1
  local new_col = #new_lines[#new_lines]
  vim.api.nvim_win_set_cursor(0, { new_line_num, new_col })
end

return M
