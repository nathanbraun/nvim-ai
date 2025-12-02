-- lua/nai/utils/error_handler.lua
-- Standardized error handling for async operations with proper cleanup

local M = {}
local error_utils = require('nai.utils.error')

-- Handle request errors with consistent cleanup
-- This ensures state, indicators, and events are properly managed
function M.handle_request_error(opts)
  local request_id = opts.request_id
  local indicator_id = opts.indicator_id
  local indicator = opts.indicator
  local error_msg = opts.error_msg
  local callback = opts.callback
  local context = opts.context or {}

  -- Get required modules
  local state = require('nai.state')
  local events = require('nai.events')

  -- 1. Update request state if request_id exists
  if request_id then
    state.update_request(request_id, {
      status = 'error',
      end_time = os.time(),
      error = error_msg
    })

    -- 2. Emit error event
    events.emit('request:error', request_id, error_msg)
  end

  -- 3. Clean up indicator if it exists
  if indicator then
    local utils = require('nai.utils')
    local insertion_row = utils.indicators.remove(indicator)
    
    -- Store insertion_row for callback
    context.insertion_row = insertion_row
    context.placeholder_height = indicator.end_row - indicator.start_row
  end

  -- 4. Clear indicator from state
  if indicator_id then
    state.clear_indicator(indicator_id)
  end

  -- 5. Schedule the error callback
  vim.schedule(function()
    -- Log the error
    error_utils.log(error_msg, error_utils.LEVELS.ERROR, context)
    
    -- Call the user's error callback
    if callback then
      callback(error_msg, context)
    end

    -- 6. Clear request from state after callback completes
    if request_id then
      state.clear_request(request_id)
    end
  end)
end

-- Handle cancellation with proper cleanup
function M.handle_request_cancellation(opts)
  local request_id = opts.request_id
  local indicator_id = opts.indicator_id
  local indicator = opts.indicator

  local state = require('nai.state')
  local events = require('nai.events')

  -- 1. Update request state
  if request_id then
    state.update_request(request_id, {
      status = 'cancelled',
      end_time = os.time()
    })

    -- 2. Emit cancellation event
    events.emit('request:cancel', request_id)
  end

  -- 3. Clean up indicator
  if indicator then
    local utils = require('nai.utils')
    utils.indicators.remove(indicator)
  end

  -- 4. Clear indicator from state
  if indicator_id then
    state.clear_indicator(indicator_id)
  end

  -- 5. Clear request from state after a short delay
  if request_id then
    vim.defer_fn(function()
      state.clear_request(request_id)
    end, 100)
  end
end

-- Wrapper for API error handling with consistent context
function M.handle_api_error(opts)
  local response = opts.response
  local provider = opts.provider
  local request_id = opts.request_id
  local indicator_id = opts.indicator_id
  local indicator = opts.indicator
  local callback = opts.callback

  -- Parse and format the error message
  local error_msg = error_utils.handle_api_error(response, provider)

  -- Use the standard request error handler
  M.handle_request_error({
    request_id = request_id,
    indicator_id = indicator_id,
    indicator = indicator,
    error_msg = error_msg,
    callback = callback,
    context = {
      provider = provider,
      endpoint = opts.endpoint
    }
  })
end

-- Validate and handle buffer errors
function M.validate_buffer_or_error(bufnr, operation, callback)
  if not error_utils.validate_buffer(bufnr, operation) then
    if callback then
      vim.schedule(function()
        callback("Invalid buffer for operation: " .. operation)
      end)
    end
    return false
  end
  return true
end

return M

