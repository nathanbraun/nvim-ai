-- lua/nai/utils/indicators.lua
-- Advanced UI indicators for async operations
-- IMPORTANT: This file must NOT require 'nai' to avoid circular dependencies

local M = {}

-- Import config directly instead of through nai
local config = require('nai.config')

-- Create a namespace for our extmarks
M.namespace_id = vim.api.nvim_create_namespace('nvim_ai_indicators')

-- Namespace for spinner highlights
M.highlight_ns = vim.api.nvim_create_namespace('nai_spinner_highlight')

-- Helper to apply spinner highlighting to a line
local function highlight_spinner_line(buffer_id, row)
  -- Ensure highlight groups exist
  local syntax = require('nai.syntax')
  syntax.define_highlight_groups()

  -- Apply highlight to the entire line
  local line = vim.api.nvim_buf_get_lines(buffer_id, row, row + 1, false)[1]
  if line then
    vim.api.nvim_buf_add_highlight(buffer_id, M.highlight_ns, "naichatSpinner", row, 0, #line)
  end
end

-- Create an assistant placeholder that shows a proper format with animation
function M.create_assistant_placeholder(buffer_id, row)
  -- Insert a properly formatted assistant placeholder
  local placeholder_lines = {
    "",
    "<<< assistant",
    "",
    "⏳ Generating response...",
    "",
  }

  vim.api.nvim_buf_set_lines(buffer_id, row, row, false, placeholder_lines)

  -- Calculate the position where the spinner will be placed
  local spinner_row = row + 3 -- The line with the "Generating response..." text

  -- Create the indicator data structure
  local indicator = {
    buffer_id = buffer_id,
    start_row = row,
    spinner_row = spinner_row,
    end_row = row + #placeholder_lines,
    timer = nil,
    stats = {
      tokens = 0,
      elapsed_time = 0,
      start_time = vim.loop.now(),
      model = config.get_active_model()
    }
  }

  -- Apply initial highlighting
  highlight_spinner_line(buffer_id, spinner_row)

  -- Start the animation
  local animation_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
  local current_frame = 1

  indicator.timer = vim.loop.new_timer()
  indicator.timer:start(0, 120, vim.schedule_wrap(function()
    -- Check if buffer still exists
    if not vim.api.nvim_buf_is_valid(buffer_id) then
      M.remove(indicator)
      return
    end

    -- Update elapsed time
    indicator.stats.elapsed_time = math.floor((vim.loop.now() - indicator.stats.start_time) / 1000)

    -- Update the status line with current info
    local status_text = animation_frames[current_frame] .. " Generating response"

    -- Add elapsed time
    if indicator.stats.elapsed_time > 0 then
      status_text = status_text .. " | " .. indicator.stats.elapsed_time .. "s elapsed"
    end

    -- Add token info if available
    if indicator.stats.tokens > 0 then
      status_text = status_text .. " | " .. indicator.stats.tokens .. " tokens"
    end

    -- Temporarily disable TextChanged events to prevent triggering syntax re-highlighting
    local eventignore = vim.o.eventignore
    vim.o.eventignore = "TextChanged,TextChangedI"

    -- Update the text in the buffer
    vim.api.nvim_buf_set_lines(
      buffer_id,
      spinner_row,
      spinner_row + 1,
      false,
      { status_text }
    )

    -- Apply highlighting to the spinner line
    highlight_spinner_line(buffer_id, spinner_row)

    -- Model info line if we have model information
    local model_info = ""
    if indicator.stats.model then
      -- Extract just the model name without provider prefix
      local model_name = indicator.stats.model:match("[^/]+$") or indicator.stats.model
      model_info = "Using model: " .. model_name
    end

    -- If we have model info, put it on the next line
    if model_info ~= "" then
      -- Calculate the model info row
      local model_row = spinner_row + 1

      -- Check if we need to add a new line for model info
      if model_row >= indicator.end_row then
        vim.api.nvim_buf_set_lines(
          buffer_id,
          model_row,
          model_row,
          false,
          { model_info }
        )
        indicator.end_row = indicator.end_row + 1
      else
        -- Update existing line
        vim.api.nvim_buf_set_lines(
          buffer_id,
          model_row,
          model_row + 1,
          false,
          { model_info }
        )
      end

      -- Apply highlighting to the model info line
      highlight_spinner_line(buffer_id, model_row)
    end

    -- Restore eventignore
    vim.o.eventignore = eventignore

    -- Move to the next animation frame
    current_frame = (current_frame % #animation_frames) + 1
  end))

  return indicator
end

-- Function to update the indicator with new information
function M.update_stats(indicator, stats)
  if not indicator then return end

  -- Update the stats in the indicator
  for key, value in pairs(stats) do
    indicator.stats[key] = value
  end
  -- The timer will use these updated stats on the next tick
end

-- Function to remove the placeholder and return the final row
function M.remove(indicator)
  if not indicator then return 0 end

  -- Stop the timer if it exists
  if indicator.timer then
    indicator.timer:stop()
    indicator.timer:close()
    indicator.timer = nil
  end

  -- Save these values before potentially invalid references
  local buffer_id = indicator.buffer_id
  local start_row = indicator.start_row
  local end_row = indicator.end_row

  -- Clear our highlights
  if vim.api.nvim_buf_is_valid(buffer_id) then
    vim.api.nvim_buf_clear_namespace(buffer_id, M.highlight_ns, 0, -1)
  end

  -- Return start row for replacement operations
  return start_row
end

-- Create a simple, legacy-style indicator at cursor position (fallback)
function M.create_at_cursor(buffer_id, row, col)
  local mark_id = vim.api.nvim_buf_set_extmark(
    buffer_id,
    M.namespace_id,
    row, col,
    {
      virt_text = { { "AI working...", "Comment" } },
      virt_text_pos = "eol",
    }
  )

  local indicator = {
    buffer_id = buffer_id,
    mark_id = mark_id,
    legacy = true
  }

  return indicator
end

-- Remove a legacy indicator
function M.remove_legacy(indicator)
  if indicator and indicator.legacy then
    if vim.api.nvim_buf_is_valid(indicator.buffer_id) then
      vim.api.nvim_buf_del_extmark(
        indicator.buffer_id,
        M.namespace_id,
        indicator.mark_id
      )
    end
  end
end

return M
