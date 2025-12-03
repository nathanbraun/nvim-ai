-- lua/nai/state/buffers.lua
-- Manages activated buffer state

local Store = require('nai.state.store')

local M = {}

-- Validator
local function validate_bufnr(bufnr)
  if type(bufnr) ~= 'number' or bufnr < 0 then
    return false, "Buffer number must be a positive number"
  end
  return true
end

-- Initialize the buffer manager
function M.new()
  local manager = {
    _store = Store.new({
      activated_buffers = {}
    })
  }

  -- Activate a buffer
  function manager:activate(bufnr)
    local valid, err = validate_bufnr(bufnr)
    if not valid then
      return false, err
    end

    -- Get current buffers
    local buffers, get_err = self._store:get("activated_buffers")
    if get_err then
      buffers = {}
    end

    -- Add this buffer
    buffers[bufnr] = true

    -- Update store
    local success, set_err = self._store:set("activated_buffers", buffers)
    if not success then
      return false, set_err
    end

    return true, nil
  end

  -- Deactivate a buffer
  function manager:deactivate(bufnr)
    local valid, err = validate_bufnr(bufnr)
    if not valid then
      return false, err
    end

    -- Get current buffers
    local buffers, get_err = self._store:get("activated_buffers")
    if get_err then
      return false, get_err
    end

    -- Remove this buffer
    buffers[bufnr] = nil

    -- Update store
    local success, set_err = self._store:set("activated_buffers", buffers)
    if not success then
      return false, set_err
    end

    return true, nil
  end

  -- Check if a buffer is activated
  function manager:is_activated(bufnr)
    local valid, err = validate_bufnr(bufnr)
    if not valid then
      return false
    end

    local buffers = self._store:get("activated_buffers")
    return buffers[bufnr] == true
  end

  -- Get all activated buffers
  function manager:get_all()
    local buffers, err = self._store:get("activated_buffers")
    if err then
      return {}, err
    end
    return buffers or {}, nil
  end

  -- Clear all activated buffers
  function manager:clear_all()
    return self._store:set("activated_buffers", {})
  end

  -- Subscribe to buffer changes
  function manager:subscribe(callback)
    return self._store:subscribe("activated_buffers", callback)
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
    local buffers = self:get_all()
    return {
      activated_count = vim.tbl_count(buffers),
      buffer_numbers = vim.tbl_keys(buffers)
    }
  end

  return manager
end

return M
