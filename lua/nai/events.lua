-- lua/nai/events.lua
local M = {
  listeners = {},
}

-- Register an event listener
function M.on(event_name, callback)
  if not M.listeners[event_name] then
    M.listeners[event_name] = {}
  end
  table.insert(M.listeners[event_name], callback)

  -- Return a function to remove this listener
  return function()
    for i, cb in ipairs(M.listeners[event_name]) do
      if cb == callback then
        table.remove(M.listeners[event_name], i)
        break
      end
    end
  end
end

-- Emit an event
function M.emit(event_name, ...)
  if M.listeners[event_name] then
    for _, callback in ipairs(M.listeners[event_name]) do
      -- Use pcall to prevent one error from stopping other callbacks
      pcall(callback, ...)
    end
  end
end

return M
