-- lua/nai/state/store.lua
-- Core state management with validation, snapshots, and change notifications

local M = {}

-- Deep copy utility
local function deep_copy(obj)
  if type(obj) ~= 'table' then
    return obj
  end
  
  local copy = {}
  for k, v in pairs(obj) do
    copy[k] = deep_copy(v)
  end
  return copy
end

-- Get nested value from table using dot notation path
-- e.g., get_nested(state, "ui.current_provider")
local function get_nested(tbl, path)
  if type(path) ~= 'string' then
    return nil, "Path must be a string"
  end
  
  local keys = vim.split(path, '.', { plain = true })
  local current = tbl
  
  for _, key in ipairs(keys) do
    if type(current) ~= 'table' then
      return nil, string.format("Cannot traverse non-table at key '%s'", key)
    end
    current = current[key]
    if current == nil then
      return nil, string.format("Key '%s' not found in path '%s'", key, path)
    end
  end
  
  return current, nil
end

-- Set nested value in table using dot notation path
local function set_nested(tbl, path, value)
  if type(path) ~= 'string' then
    return false, "Path must be a string"
  end
  
  local keys = vim.split(path, '.', { plain = true })
  local current = tbl
  
  -- Navigate to parent of target
  for i = 1, #keys - 1 do
    local key = keys[i]
    if type(current[key]) ~= 'table' then
      current[key] = {}
    end
    current = current[key]
  end
  
  -- Set the final value
  current[keys[#keys]] = value
  return true, nil
end

-- Create a new store instance
function M.new(initial_state)
  local store = {
    _state = initial_state or {},
    _subscribers = {},
    _snapshots = {}
  }
  
  -- Get a value from the store
  function store:get(path)
    if not path then
      -- Return entire state (deep copy for safety)
      return deep_copy(self._state)
    end
    
    local value, err = get_nested(self._state, path)
    if err then
      return nil, err
    end
    
    -- Return deep copy to prevent external mutation
    return deep_copy(value), nil
  end
  
  -- Set a value in the store with optional validation
  function store:set(path, value, validator)
    if not path then
      return false, "Path is required"
    end
    
    -- Run validator if provided
    if validator and type(validator) == 'function' then
      local valid, err = validator(value)
      if not valid then
        return false, err or "Validation failed"
      end
    end
    
    -- Store old value for change notification
    local old_value = get_nested(self._state, path)
    
    -- Set the new value
    local success, err = set_nested(self._state, path, value)
    if not success then
      return false, err
    end
    
    -- Notify subscribers
    self:_notify(path, value, old_value)
    
    return true, nil
  end
  
  -- Update multiple paths atomically
  function store:update(updates, validator)
    if type(updates) ~= 'table' then
      return false, "Updates must be a table"
    end
    
    -- Create a snapshot before making changes
    local snapshot = self:snapshot()
    
    -- Apply all updates
    for path, value in pairs(updates) do
      local success, err = self:set(path, value, validator)
      if not success then
        -- Rollback on any failure
        self:restore(snapshot)
        return false, string.format("Failed to update '%s': %s", path, err)
      end
    end
    
    return true, nil
  end
  
  -- Create a snapshot of current state
  function store:snapshot()
    return deep_copy(self._state)
  end
  
  -- Restore state from a snapshot
  function store:restore(snapshot)
    if type(snapshot) ~= 'table' then
      return false, "Snapshot must be a table"
    end
    
    self._state = deep_copy(snapshot)
    
    -- Notify all subscribers of the restoration
    self:_notify('*', self._state, nil)
    
    return true, nil
  end
  
  -- Subscribe to changes on a path
  function store:subscribe(path, callback)
    if type(callback) ~= 'function' then
      return nil, "Callback must be a function"
    end
    
    if not self._subscribers[path] then
      self._subscribers[path] = {}
    end
    
    -- Generate unique subscription ID
    local sub_id = string.format("%s_%d", path, #self._subscribers[path] + 1)
    
    table.insert(self._subscribers[path], {
      id = sub_id,
      callback = callback
    })
    
    -- Return unsubscribe function
    return function()
      self:unsubscribe(sub_id)
    end, nil
  end
  
  -- Unsubscribe from changes
  function store:unsubscribe(sub_id)
    for path, subscribers in pairs(self._subscribers) do
      for i, sub in ipairs(subscribers) do
        if sub.id == sub_id then
          table.remove(subscribers, i)
          return true
        end
      end
    end
    return false
  end
  
  -- Internal: Notify subscribers of changes
  function store:_notify(path, new_value, old_value)
    -- Notify exact path subscribers
    if self._subscribers[path] then
      for _, sub in ipairs(self._subscribers[path]) do
        -- Wrap in pcall to prevent subscriber errors from breaking the store
        pcall(sub.callback, new_value, old_value, path)
      end
    end
    
    -- Notify wildcard subscribers
    if self._subscribers['*'] then
      for _, sub in ipairs(self._subscribers['*']) do
        pcall(sub.callback, new_value, old_value, path)
      end
    end
  end
  
  -- Reset store to initial state
  function store:reset()
    self._state = initial_state and deep_copy(initial_state) or {}
    self._subscribers = {}
    self._snapshots = {}
    return true
  end
  
  -- Debug: Get store info
  function store:debug()
    local subscriber_count = 0
    for _, subs in pairs(self._subscribers) do
      subscriber_count = subscriber_count + #subs
    end
    
    return {
      state_keys = vim.tbl_keys(self._state),
      subscriber_count = subscriber_count,
      snapshot_count = #self._snapshots
    }
  end
  
  return store
end

return M

