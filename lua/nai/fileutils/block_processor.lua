-- lua/nai/fileutils/block_processor.lua
local M = {}

-- Active requests tracking (shared across all block types)
M.active_requests = {}

-- Spinner animation frames
local SPINNER_FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local SPINNER_INTERVAL = 120 -- milliseconds

-- ============================================================================
-- Indicator Management
-- ============================================================================

-- Create an indicator structure
function M.create_indicator(buffer_id, start_row, end_row)
  return {
    buffer_id = buffer_id,
    start_row = start_row,
    end_row = end_row,
    spinner_row = start_row + 2, -- Spinner goes after marker and content
    timer = nil,
    current_frame = 1,
  }
end

-- Start spinner animation
function M.start_spinner(indicator, message_fn)
  if indicator.timer then
    return -- Already running
  end

  indicator.timer = vim.loop.new_timer()
  indicator.timer:start(0, SPINNER_INTERVAL, vim.schedule_wrap(function()
    -- Check if buffer still exists
    if not vim.api.nvim_buf_is_valid(indicator.buffer_id) then
      M.stop_spinner(indicator)
      return
    end

    -- Generate status message
    local status_text = SPINNER_FRAMES[indicator.current_frame] .. " " .. message_fn()

    -- Update the buffer
    vim.api.nvim_buf_set_lines(
      indicator.buffer_id,
      indicator.spinner_row,
      indicator.spinner_row + 1,
      false,
      { status_text }
    )

    -- Move to next frame
    indicator.current_frame = (indicator.current_frame % #SPINNER_FRAMES) + 1
  end))
end

-- Stop spinner animation
function M.stop_spinner(indicator)
  if indicator.timer then
    indicator.timer:stop()
    indicator.timer:close()
    indicator.timer = nil
  end
end

-- ============================================================================
-- Request Tracking
-- ============================================================================

-- Register a new request
function M.register_request(request_id, request_data)
  M.active_requests[request_id] = request_data
end

-- Complete and remove a request
function M.complete_request(request_id)
  local request = M.active_requests[request_id]
  if request and request.indicator then
    M.stop_spinner(request.indicator)
  end
  M.active_requests[request_id] = nil
end

-- Check if there are active requests
function M.has_active_requests()
  return next(M.active_requests) ~= nil
end

-- Get active request by ID
function M.get_request(request_id)
  return M.active_requests[request_id]
end

-- ============================================================================
-- Block Parsing Utilities
-- ============================================================================

-- Parse options from block lines (lines starting with --)
function M.parse_options(lines, defaults)
  local options = vim.tbl_deep_extend("force", {}, defaults or {})

  for _, line in ipairs(lines) do
    if line:match("^%s*%-%-") then
      local option_name, option_value = line:match("^%s*%-%-+%s*(%w+)%s*:%s*(.+)$")
      if option_name and option_value then
        -- Trim whitespace
        option_value = option_value:gsub("^%s*(.-)%s*$", "%1")

        -- Try to convert to number if it looks like one
        local as_number = tonumber(option_value)
        if as_number then
          options[option_name] = as_number
          -- Try to convert to boolean
        elseif option_value:lower() == "true" then
          options[option_name] = true
        elseif option_value:lower() == "false" then
          options[option_name] = false
        else
          options[option_name] = option_value
        end
      end
    end
  end

  return options
end

-- Extract URL or path from block lines (first non-empty, non-option line)
function M.extract_target(lines)
  for i = 2, #lines do -- Skip first line (marker)
    local line = lines[i]
    -- Skip empty lines and option lines
    if line:match("%S") and not line:match("^%s*%-%-") then
      return line:gsub("^%s*(.-)%s*$", "%1") -- Trim whitespace
    end
  end
  return nil
end

-- ============================================================================
-- Block Formatting Utilities
-- ============================================================================

-- Format a completed block header
function M.format_completed_header(marker, target, options, timestamp)
  local lines = {
    marker .. " [" .. (timestamp or os.date("%Y-%m-%d %H:%M:%S")) .. "]",
    target
  }

  -- Add options as comments if provided
  if options then
    for key, value in pairs(options) do
      table.insert(lines, "-- " .. key .. ": " .. tostring(value))
    end
  end

  table.insert(lines, "") -- Blank line after header
  return lines
end

-- Format an error block
function M.format_error_block(error_marker, target, error_msg)
  return {
    error_marker,
    target or "",
    "",
    "❌ Error: " .. error_msg,
    ""
  }
end

-- ============================================================================
-- Core Async Block Expansion
-- ============================================================================

-- Expand an async block (for scrape, youtube, crawl, etc.)
function M.expand_async_block(config)
  --[[
  config = {
    buffer_id = number,
    start_line = number,
    end_line = number,
    block_type = string,           -- e.g., "scrape"
    progress_marker = string,      -- e.g., ">>> scraping"
    completed_marker = string,     -- e.g., ">>> scraped"
    error_marker = string,         -- e.g., ">>> scrape-error"
    spinner_message = function(target, options),
    default_options = table,
    parse_options = function(lines) [optional],
    validate_target = function(target) [optional],
    execute = function(target, options, callback, on_error),
    format_result = function(result, target, options),
  }
  --]]

  local buffer_id = config.buffer_id
  local start_line = config.start_line
  local end_line = config.end_line

  -- Get block lines
  local lines = vim.api.nvim_buf_get_lines(buffer_id, start_line, end_line, false)

  -- Extract target (URL, path, etc.)
  local target = M.extract_target(lines)

  -- Validate target
  if not target or target == "" then
    vim.api.nvim_buf_set_lines(
      buffer_id,
      start_line,
      end_line,
      false,
      M.format_error_block(config.error_marker, nil, "No target provided")
    )
    return 3
  end

  -- Custom validation if provided
  if config.validate_target and not config.validate_target(target) then
    vim.api.nvim_buf_set_lines(
      buffer_id,
      start_line,
      end_line,
      false,
      M.format_error_block(config.error_marker, target, "Invalid target: " .. target)
    )
    return 3
  end

  -- Parse options
  local options
  if config.parse_options then
    options = config.parse_options(lines)
  else
    options = M.parse_options(lines, config.default_options)
  end

  -- Change marker to progress state
  vim.api.nvim_buf_set_lines(
    buffer_id,
    start_line,
    start_line + 1,
    false,
    { config.progress_marker }
  )

  -- Create indicator
  local indicator = M.create_indicator(buffer_id, start_line, end_line)

  -- Insert spinner line
  vim.api.nvim_buf_set_lines(
    buffer_id,
    indicator.spinner_row,
    indicator.spinner_row,
    false,
    { "⏳ Processing..." }
  )

  -- Start spinner
  M.start_spinner(indicator, function()
    return config.spinner_message(target, options)
  end)

  -- Generate request ID
  local request_id = string.format("%s_%d_%d_%d",
    config.block_type,
    buffer_id,
    start_line,
    os.time()
  )

  -- Track request
  M.register_request(request_id, {
    buffer_id = buffer_id,
    indicator = indicator,
    start_line = start_line,
    end_line = end_line,
    target = target,
    block_type = config.block_type,
  })

  -- Execute the async operation
  config.execute(
    target,
    options,
    -- Success callback
    function(result)
      -- Complete request
      M.complete_request(request_id)

      -- Check if buffer still valid
      if not vim.api.nvim_buf_is_valid(buffer_id) then
        return
      end

      -- Format result
      local result_lines = config.format_result(result, target, options)

      -- Replace placeholder with result
      vim.api.nvim_buf_set_lines(
        buffer_id,
        indicator.start_row,
        math.max(indicator.end_row, indicator.start_row + 3),
        false,
        result_lines
      )
    end,
    -- Error callback
    function(error_msg)
      -- Complete request
      M.complete_request(request_id)

      -- Check if buffer still valid
      if not vim.api.nvim_buf_is_valid(buffer_id) then
        return
      end

      -- Format error
      local error_lines = M.format_error_block(config.error_marker, target, error_msg)

      -- Replace placeholder with error
      vim.api.nvim_buf_set_lines(
        buffer_id,
        indicator.start_row,
        math.max(indicator.end_row, indicator.start_row + 3),
        false,
        error_lines
      )

      -- Show notification
      vim.schedule(function()
        vim.notify("Error in " .. config.block_type .. ": " .. error_msg, vim.log.levels.ERROR)
      end)
    end
  )

  -- Return placeholder line count
  return 3
end

-- ============================================================================
-- Core Sync Block Expansion
-- ============================================================================

-- Expand a sync block (for snapshot, tree, etc.)
function M.expand_sync_block(config)
  --[[
  config = {
    buffer_id = number,
    start_line = number,
    end_line = number,
    block_type = string,
    progress_marker = string [optional],
    completed_marker = string,
    error_marker = string,
    use_spinner = boolean [optional],
    spinner_message = function(target, options) [optional],
    default_options = table [optional],
    parse_options = function(lines) [optional],
    validate_target = function(target) [optional],
    execute = function(lines, options) -> result_lines or nil, error_msg,
  }
  --]]

  local buffer_id = config.buffer_id
  local start_line = config.start_line
  local end_line = config.end_line

  -- Get block lines
  local lines = vim.api.nvim_buf_get_lines(buffer_id, start_line, end_line, false)

  -- Parse options if needed
  local options
  if config.parse_options then
    options = config.parse_options(lines)
  elseif config.default_options then
    options = M.parse_options(lines, config.default_options)
  end

  -- Optionally show progress marker
  if config.progress_marker then
    vim.api.nvim_buf_set_lines(
      buffer_id,
      start_line,
      start_line + 1,
      false,
      { config.progress_marker }
    )
  end

  -- Optionally use spinner for long operations
  local indicator
  if config.use_spinner and config.spinner_message then
    indicator = M.create_indicator(buffer_id, start_line, end_line)
    vim.api.nvim_buf_set_lines(
      buffer_id,
      indicator.spinner_row,
      indicator.spinner_row,
      false,
      { "⏳ Processing..." }
    )

    -- Extract target for spinner message
    local target = M.extract_target(lines)
    M.start_spinner(indicator, function()
      return config.spinner_message(target, options)
    end)
  end

  -- Execute synchronously (but schedule to allow spinner to show)
  vim.schedule(function()
    local result_lines, error_msg = config.execute(lines, options)

    -- Stop spinner if used
    if indicator then
      M.stop_spinner(indicator)
    end

    -- Check if buffer still valid
    if not vim.api.nvim_buf_is_valid(buffer_id) then
      return
    end

    if error_msg then
      -- Handle error
      local target = M.extract_target(lines)
      local error_lines = M.format_error_block(config.error_marker, target, error_msg)
      vim.api.nvim_buf_set_lines(buffer_id, start_line, end_line, false, error_lines)
    else
      -- Success - replace with result
      vim.api.nvim_buf_set_lines(buffer_id, start_line, end_line, false, result_lines)
    end
  end)

  -- Return estimated line count
  return config.use_spinner and 3 or (end_line - start_line)
end

return M
