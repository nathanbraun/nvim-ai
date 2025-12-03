-- lua/nai/state/indicators.lua
-- Manages UI indicator state

local Store = require('nai.state.store')

local M = {}

-- Validators
local function validate_indicator_id(id)
  if type(id) ~= 'string' or id == '' then
    return false, "Indicator ID must be a non-empty string"
  end
  return true
end

local function validate_indicator_data(data)
  if type(data) ~= 'table' then
    return false, "Indicator data must be a table"
  end
  return true
end

-- Initialize the indicator manager
function M.new()
  local manager = {
    _store = Store.new({
      active_indicators = {}
    })
  }

  -- Register an indicator
  function manager:register(indicator_id, data)
    local valid, err = validate_indicator_id(indicator_id)
    if not valid then
      return nil, err
    end

    valid, err = validate_indicator_data(data)
    if not valid then
      return nil, err
    end

    -- Get current indicators
    local indicators, get_err = self._store:get("active_indicators")
    if get_err then
      indicators = {}
    end

    -- Add new indicator
    indicators[indicator_id] = data

    -- Update store
    local success, set_err = self._store:set("active_indicators", indicators)
    if not success then
      return nil, set_err
    end

    return indicator_id, nil
  end

  -- Update an indicator
  function manager:update(indicator_id, updates)
    local valid, err = validate_indicator_id(indicator_id)
    if not valid then
      return false, err
    end

    if type(updates) ~= 'table' then
      return false, "Updates must be a table"
    end

    -- Get current indicators
    local indicators, get_err = self._store:get("active_indicators")
    if get_err then
      return false, get_err
    end

    if not indicators[indicator_id] then
      return false, string.format("Indicator '%s' not found", indicator_id)
    end

    -- Merge updates
    for k, v in pairs(updates) do
      indicators[indicator_id][k] = v
    end

    -- Update store
    local success, set_err = self._store:set("active_indicators", indicators)
    if not success then
      return false, set_err
    end

    return true, nil
  end

  -- Clear an indicator
  function manager:clear(indicator_id)
    local valid, err = validate_indicator_id(indicator_id)
    if not valid then
      return false, err
    end

    -- Get current indicators
    local indicators, get_err = self._store:get("active_indicators")
    if get_err then
      return false, get_err
    end

    -- Remove indicator
    indicators[indicator_id] = nil

    -- Update store
    local success, set_err = self._store:set("active_indicators", indicators)
    if not success then
      return false, set_err
    end

    return true, nil
  end

  -- Get a specific indicator
  function manager:get(indicator_id)
    local valid, err = validate_indicator_id(indicator_id)
    if not valid then
      return nil, err
    end

    local indicators, get_err = self._store:get("active_indicators")
    if get_err then
      return nil, get_err
    end

    local indicator = indicators[indicator_id]
    if not indicator then
      return nil, string.format("Indicator '%s' not found", indicator_id)
    end

    return indicator, nil
  end

  -- Get all indicators
  function manager:get_all()
    local indicators, err = self._store:get("active_indicators")
    if err then
      return {}, err
    end
    return indicators or {}, nil
  end

  -- Clear all indicators
  function manager:clear_all()
    return self._store:set("active_indicators", {})
  end

  -- Subscribe to indicator changes
  function manager:subscribe(callback)
    return self._store:subscribe("active_indicators", callback)
  end

  -- Snapshot and restore
  function manager:snapshot()
    return self._store:snapshot()
  end

  function manager:restore(snapshot)
    return self._store:restore(snapshot)
  end

  -- Debug info
  function manager:debug()
    local indicators = self:get_all()
    return {
      active_count = vim.tbl_count(indicators),
      indicator_ids = vim.tbl_keys(indicators)
    }
  end

  return manager
end

return M
