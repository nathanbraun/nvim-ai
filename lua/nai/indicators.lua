function M.indicators.create_assistant_placeholder(buffer_id, row)
  -- Insert a properly formatted assistant placeholder at the specified row
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
    marks = {},
    timer = nil,
    stats = {
      tokens = 0,
      estimated_time = nil,
      model = config.get_provider_config().model,
    }
  }
  
  -- Start the animation
  local animation_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
  local current_frame = 1
  
  indicator.timer = vim.loop.new_timer()
  indicator.timer:start(0, 120, vim.schedule_wrap(function()
    -- Check if buffer still exists
    if not vim.api.nvim_buf_is_valid(buffer_id) then
      M.indicators.remove(indicator)
      return
    end
    
    -- Update the status line with current info
    local status_text = animation_frames[current_frame] .. " Generating response"
    
    -- Add additional info if available
    if indicator.stats.estimated_time then
      status_text = status_text .. " (est. " .. indicator.stats.estimated_time .. "s)"
    end
    
    if indicator.stats.tokens > 0 then
      status_text = status_text .. " | " .. indicator.stats.tokens .. " tokens"
    end
    
    -- Update the model info if available
    local model_info = ""
    if indicator.stats.model then
      -- Extract just the model name without provider prefix
      local model_name = indicator.stats.model:match("[^/]+$") or indicator.stats.model
      model_info = "Using " .. model_name
    end
    
    -- Update the text in the buffer
    vim.api.nvim_buf_set_lines(
      buffer_id, 
      spinner_row, 
      spinner_row + 1, 
      false, 
      {status_text}
    )
    
    -- If we have model info, put it on the next line
    if model_info ~= "" then
      -- Check if the model info line exists, create it if not
      if spinner_row + 2 > indicator.end_row then
        vim.api.nvim_buf_set_lines(
          buffer_id,
          spinner_row + 1,
          spinner_row + 1,
          false,
          {model_info}
        )
        indicator.end_row = indicator.end_row + 1
      else
        vim.api.nvim_buf_set_lines(
          buffer_id,
          spinner_row + 1,
          spinner_row + 2,
          false,
          {model_info}
        )
      end
    end
    
    -- Move to the next animation frame
    current_frame = (current_frame % #animation_frames) + 1
  end))
  
  return indicator
end

-- Function to update the indicator with new information
function M.indicators.update_stats(indicator, stats)
  -- Update the stats in the indicator
  for key, value in pairs(stats) do
    indicator.stats[key] = value
  end
  -- The timer will use these updated stats on the next tick
end

-- Function to remove the placeholder and return the final row
function M.indicators.remove_placeholder(indicator)
  -- Stop the timer
  if indicator.timer then
    indicator.timer:stop()
    indicator.timer:close()
    indicator.timer = nil
  end
  
  -- Return the start position to place the actual content
  return indicator.start_row
end

