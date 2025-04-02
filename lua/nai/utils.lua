-- lua/nai/utils.lua
-- Utility functions

local M = {}

M.indicators = {}
-- Create a namespace for our extmarks
M.indicators.namespace_id = vim.api.nvim_create_namespace('nvim_ai_indicators')

-- Function to create an indicator at cursor position
function M.indicators.create_at_cursor(buffer_id, row, col)
  -- Store info for later removal
  local indicator = {
    buffer_id = buffer_id,
    marks = {},
    timer = nil
  }

  -- Create virtual text saying "AI working..."
  local mark_id = vim.api.nvim_buf_set_extmark(
    buffer_id,
    M.indicators.namespace_id,
    row, col,
    {
      virt_text = { { "AI working...", "Comment" } },
      virt_text_pos = "eol", -- or "right" if you prefer
    }
  )
  table.insert(indicator.marks, mark_id)

  -- Create an animated cursor effect
  local animation_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
  local current_frame = 1

  -- Set up a timer for animation (every 100ms)
  indicator.timer = vim.loop.new_timer()
  indicator.timer:start(0, 100, vim.schedule_wrap(function()
    -- Check if buffer still exists
    if not vim.api.nvim_buf_is_valid(buffer_id) then
      M.indicators.remove(indicator)
      return
    end

    -- Update the animation frame
    local cursor_mark_id = vim.api.nvim_buf_set_extmark(
      buffer_id,
      M.indicators.namespace_id,
      row, col,
      {
        virt_text = { { animation_frames[current_frame], "Special" } },
        virt_text_pos = "overlay",
      }
    )

    -- Replace the previous cursor mark
    if indicator.cursor_mark then
      vim.api.nvim_buf_del_extmark(buffer_id, M.indicators.namespace_id, indicator.cursor_mark)
    end
    indicator.cursor_mark = cursor_mark_id

    -- Move to the next animation frame
    current_frame = (current_frame % #animation_frames) + 1
  end))

  return indicator
end

-- Function to remove an indicator
function M.indicators.remove(indicator)
  -- Stop the timer if it exists
  if indicator.timer then
    indicator.timer:stop()
    indicator.timer:close()
    indicator.timer = nil
  end

  -- Remove all extmarks
  if vim.api.nvim_buf_is_valid(indicator.buffer_id) then
    -- Delete the virtual text mark
    for _, mark_id in ipairs(indicator.marks) do
      vim.api.nvim_buf_del_extmark(indicator.buffer_id, M.indicators.namespace_id, mark_id)
    end

    -- Delete the cursor mark if it exists
    if indicator.cursor_mark then
      vim.api.nvim_buf_del_extmark(indicator.buffer_id, M.indicators.namespace_id, indicator.cursor_mark)
    end
  end
end

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

return M
