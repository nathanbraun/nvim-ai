-- lua/nai/state/requests.lua
-- Manages active API request state with validation

local Store = require('nai.state.store')

local M = {}

-- Validators
local function validate_request_id(id)
  if type(id) ~= 'string' or id == '' then
    return false, "Request ID must be a non-empty string"
  end
  return true
end

local function validate_request_data(data)
  if type(data) ~= 'table' then
    return false, "Request data must be a table"
  end

  -- Optional: validate required fields
  -- if not data.provider then
  --   return false, "Request data must include provider"
  -- end

  return true
end

-- Initialize the request manager
function M.new()
  local manager = {
    _store = Store.new({
      active_requests = {},
      processing = false
    })
  }

  -- Register a new request
  function manager:register(request_id, data)
    -- Validate inputs
    local valid, err = validate_request_id(request_id)
    if not valid then
      return nil, err
    end

    valid, err = validate_request_data(data)
    if not valid then
      return nil, err
    end

    -- Add timestamp if not provided
    if not data.timestamp then
      data.timestamp = os.time()
    end

    -- Get current requests, add new one, and set entire table
    -- This ensures subscribers are notified
    local requests, get_err = self._store:get("active_requests")
    if get_err then
      requests = {}
    end

    requests[request_id] = data

    local success, store_err = self._store:set("active_requests", requests)
    if not success then
      return nil, store_err
    end

    -- Update processing flag
    self._store:set("processing", true)

    return request_id, nil
  end

  -- Update an existing request
  function manager:update(request_id, updates)
    local valid, err = validate_request_id(request_id)
    if not valid then
      return false, err
    end

    if type(updates) ~= 'table' then
      return false, "Updates must be a table"
    end

    -- Get all requests
    local requests, get_err = self._store:get("active_requests")
    if get_err then
      return false, get_err
    end

    -- Check if request exists
    if not requests[request_id] then
      return false, string.format("Request '%s' not found", request_id)
    end

    -- Merge updates
    for k, v in pairs(updates) do
      requests[request_id][k] = v
    end

    -- Set entire table to trigger notifications
    local success, set_err = self._store:set("active_requests", requests)
    if not success then
      return false, set_err
    end

    return true, nil
  end

  -- Clear a request
  function manager:clear(request_id)
    local valid, err = validate_request_id(request_id)
    if not valid then
      return false, err
    end

    -- Get all requests
    local requests, get_err = self._store:get("active_requests")
    if get_err then
      return false, get_err
    end

    -- Remove this request
    requests[request_id] = nil

    -- Update store (this triggers notifications)
    local success, set_err = self._store:set("active_requests", requests)
    if not success then
      return false, set_err
    end

    -- Update processing flag based on remaining requests
    local has_active = vim.tbl_count(requests) > 0
    self._store:set("processing", has_active)

    return true, nil
  end

  -- Get a specific request
  function manager:get(request_id)
    local valid, err = validate_request_id(request_id)
    if not valid then
      return nil, err
    end

    local requests, get_err = self._store:get("active_requests")
    if get_err then
      return nil, get_err
    end

    local request = requests[request_id]
    if not request then
      return nil, string.format("Request '%s' not found", request_id)
    end

    return request, nil
  end

  -- Get all active requests
  function manager:get_all()
    local requests, err = self._store:get("active_requests")
    if err then
      return {}, err
    end
    return requests or {}, nil
  end

  -- Check if there are any active requests
  function manager:has_active()
    local requests = self:get_all()
    return vim.tbl_count(requests) > 0
  end

  -- Check if processing
  function manager:is_processing()
    local processing, err = self._store:get("processing")
    if err then
      return false
    end
    return processing or false
  end

  -- Clear all requests
  function manager:clear_all()
    local success, err = self._store:set("active_requests", {})
    if not success then
      return false, err
    end

    self._store:set("processing", false)
    return true, nil
  end

  -- Subscribe to request changes
  function manager:subscribe(callback)
    return self._store:subscribe("active_requests", callback)
  end

  -- Subscribe to processing state changes
  function manager:subscribe_processing(callback)
    return self._store:subscribe("processing", callback)
  end

  -- Create a snapshot (for error recovery)
  function manager:snapshot()
    return self._store:snapshot()
  end

  -- Restore from snapshot
  function manager:restore(snapshot)
    return self._store:restore(snapshot)
  end

  -- Debug info
  function manager:debug()
    local requests = self:get_all()
    return {
      active_count = vim.tbl_count(requests),
      is_processing = self:is_processing(),
      request_ids = vim.tbl_keys(requests)
    }
  end

  return manager
end

return M
