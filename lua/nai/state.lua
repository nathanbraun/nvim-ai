-- lua/nai/state.lua
local M = {
  -- Track active API requests
  active_requests = {},

  -- Track UI indicators
  active_indicators = {},

  -- Track activated buffers (migrated from buffer.lua)
  activated_buffers = {},

  -- General UI state
  ui_state = {
    is_processing = false,
    current_provider = nil,
    current_model = nil,
  },

  -- Chat context history (could be used for context management)
  chat_history = {},
}

-- Initialize state with config values
function M.init(config_options)
  M.ui_state.current_provider = config_options.active_provider
  M.ui_state.current_model = config_options.providers[config_options.active_provider].model
end

-- Register a new request
function M.register_request(request_id, data)
  M.active_requests[request_id] = data
  M.ui_state.is_processing = true
  return request_id
end

-- Update an existing request
function M.update_request(request_id, updates)
  if M.active_requests[request_id] then
    for k, v in pairs(updates) do
      M.active_requests[request_id][k] = v
    end
  end
end

-- Clear a request
function M.clear_request(request_id)
  M.active_requests[request_id] = nil
  M.ui_state.is_processing = vim.tbl_count(M.active_requests) > 0
end

-- Register a buffer as activated
function M.activate_buffer(bufnr)
  M.activated_buffers[bufnr] = true
end

-- Deactivate a buffer
function M.deactivate_buffer(bufnr)
  M.activated_buffers[bufnr] = nil
end

-- Check if a buffer is activated
function M.is_buffer_activated(bufnr)
  return M.activated_buffers[bufnr] == true
end

-- Register an indicator
function M.register_indicator(indicator_id, data)
  M.active_indicators[indicator_id] = data
end

-- Clear an indicator
function M.clear_indicator(indicator_id)
  M.active_indicators[indicator_id] = nil
end

-- Get all active requests
function M.get_active_requests()
  return M.active_requests
end

-- Check if there are any active requests
function M.has_active_requests()
  return vim.tbl_count(M.active_requests) > 0
end

-- Update current provider/model
function M.set_current_provider(provider)
  M.ui_state.current_provider = provider
end

function M.set_current_model(model)
  M.ui_state.current_model = model
end

-- Get current provider/model
function M.get_current_provider()
  return M.ui_state.current_provider
end

function M.get_current_model()
  return M.ui_state.current_model
end

-- Debug state
function M.debug()
  return {
    active_requests = vim.tbl_count(M.active_requests),
    active_indicators = vim.tbl_count(M.active_indicators),
    activated_buffers = vim.tbl_count(M.activated_buffers),
    current_provider = M.ui_state.current_provider,
    current_model = M.ui_state.current_model,
    is_processing = M.ui_state.is_processing
  }
end

return M
