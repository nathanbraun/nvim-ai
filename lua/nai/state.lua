-- lua/nai/state.lua
-- Unified state management facade

local RequestManager = require('nai.state.requests')
local BufferManager = require('nai.state.buffers')
local IndicatorManager = require('nai.state.indicators')
local UIManager = require('nai.state.ui')

local M = {
  -- Manager instances (created on init)
  requests = nil,
  buffers = nil,
  indicators = nil,
  ui = nil,

  -- Chat history (kept simple for now, could be a manager later)
  chat_history = {},
}

-- Initialize state with config values
function M.init(config_options)
  -- Create manager instances
  M.requests = RequestManager.new()
  M.buffers = BufferManager.new()
  M.indicators = IndicatorManager.new()
  M.ui = UIManager.new(
    config_options.active_provider,
    config_options.providers[config_options.active_provider].model
  )
end

-- ============================================================================
-- Request Management (delegates to requests manager)
-- ============================================================================

function M.register_request(request_id, data)
  return M.requests:register(request_id, data)
end

function M.update_request(request_id, updates)
  return M.requests:update(request_id, updates)
end

function M.clear_request(request_id)
  return M.requests:clear(request_id)
end

function M.get_active_requests()
  return M.requests:get_all()
end

function M.has_active_requests()
  return M.requests:has_active()
end

-- ============================================================================
-- Buffer Management (delegates to buffers manager)
-- ============================================================================

function M.activate_buffer(bufnr)
  return M.buffers:activate(bufnr)
end

function M.deactivate_buffer(bufnr)
  return M.buffers:deactivate(bufnr)
end

function M.is_buffer_activated(bufnr)
  return M.buffers:is_activated(bufnr)
end

function M.get_activated_buffers()
  return M.buffers:get_all()
end

-- ============================================================================
-- Indicator Management (delegates to indicators manager)
-- ============================================================================

function M.register_indicator(indicator_id, data)
  return M.indicators:register(indicator_id, data)
end

function M.clear_indicator(indicator_id)
  return M.indicators:clear(indicator_id)
end

-- ============================================================================
-- UI State Management (delegates to ui manager)
-- ============================================================================

function M.set_current_provider(provider)
  return M.ui:set_provider(provider)
end

function M.set_current_model(model)
  return M.ui:set_model(model)
end

function M.get_current_provider()
  return M.ui:get_provider()
end

function M.get_current_model()
  return M.ui:get_model()
end

-- ============================================================================
-- Unified Operations (work across managers)
-- ============================================================================

-- Reset all processing state (requests + indicators + UI processing flag)
function M.reset_processing_state()
  M.requests:clear_all()
  M.indicators:clear_all()
  M.ui:set_processing(false)

  -- Note: We don't clear activated_buffers as those should persist

  return true
end

-- Create a complete snapshot of all state
function M.snapshot()
  return {
    requests = M.requests:snapshot(),
    buffers = M.buffers:snapshot(),
    indicators = M.indicators:snapshot(),
    ui = M.ui:snapshot(),
    chat_history = vim.deepcopy(M.chat_history)
  }
end

-- Restore from a complete snapshot
function M.restore(snapshot)
  if type(snapshot) ~= 'table' then
    return false, "Snapshot must be a table"
  end

  local success, err

  if snapshot.requests then
    success, err = M.requests:restore(snapshot.requests)
    if not success then return false, "Failed to restore requests: " .. (err or "unknown") end
  end

  if snapshot.buffers then
    success, err = M.buffers:restore(snapshot.buffers)
    if not success then return false, "Failed to restore buffers: " .. (err or "unknown") end
  end

  if snapshot.indicators then
    success, err = M.indicators:restore(snapshot.indicators)
    if not success then return false, "Failed to restore indicators: " .. (err or "unknown") end
  end

  if snapshot.ui then
    success, err = M.ui:restore(snapshot.ui)
    if not success then return false, "Failed to restore UI: " .. (err or "unknown") end
  end

  if snapshot.chat_history then
    M.chat_history = vim.deepcopy(snapshot.chat_history)
  end

  return true, nil
end

-- Debug state - aggregate info from all managers
function M.debug()
  return {
    requests = M.requests:debug(),
    buffers = M.buffers:debug(),
    indicators = M.indicators:debug(),
    ui = M.ui:debug(),
    chat_history_entries = #M.chat_history
  }
end

-- ============================================================================
-- Subscriptions (convenience methods for cross-manager events)
-- ============================================================================

-- Subscribe to any request changes
function M.subscribe_requests(callback)
  return M.requests:subscribe(callback)
end

-- Subscribe to buffer activation changes
function M.subscribe_buffers(callback)
  return M.buffers:subscribe(callback)
end

-- Subscribe to provider changes
function M.subscribe_provider(callback)
  return M.ui:subscribe_provider(callback)
end

-- Subscribe to model changes
function M.subscribe_model(callback)
  return M.ui:subscribe_model(callback)
end

return M
