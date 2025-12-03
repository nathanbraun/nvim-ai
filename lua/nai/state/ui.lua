-- lua/nai/state/ui.lua
-- Manages UI state (provider, model, etc.)

local Store = require('nai.state.store')

local M = {}

-- Validators
local function validate_provider(provider)
  if type(provider) ~= 'string' or provider == '' then
    return false, "Provider must be a non-empty string"
  end

  local valid_providers = { "openai", "openrouter", "ollama", "google" }
  for _, valid in ipairs(valid_providers) do
    if provider == valid then
      return true
    end
  end

  return false, string.format("Provider '%s' not recognized. Valid: %s",
    provider, table.concat(valid_providers, ", "))
end

local function validate_model(model)
  if type(model) ~= 'string' or model == '' then
    return false, "Model must be a non-empty string"
  end
  return true
end

-- Initialize the UI manager
function M.new(initial_provider, initial_model)
  local manager = {
    _store = Store.new({
      current_provider = initial_provider,
      current_model = initial_model,
      is_processing = false
    })
  }

  -- Set current provider
  function manager:set_provider(provider)
    local valid, err = validate_provider(provider)
    if not valid then
      return false, err
    end

    return self._store:set("current_provider", provider)
  end

  -- Get current provider
  function manager:get_provider()
    local provider, err = self._store:get("current_provider")
    if err then
      return nil, err
    end
    return provider, nil
  end

  -- Set current model
  function manager:set_model(model)
    local valid, err = validate_model(model)
    if not valid then
      return false, err
    end

    return self._store:set("current_model", model)
  end

  -- Get current model
  function manager:get_model()
    local model, err = self._store:get("current_model")
    if err then
      return nil, err
    end
    return model, nil
  end

  -- Set processing state
  function manager:set_processing(is_processing)
    if type(is_processing) ~= 'boolean' then
      return false, "Processing state must be a boolean"
    end

    return self._store:set("is_processing", is_processing)
  end

  -- Get processing state
  function manager:is_processing()
    local processing, err = self._store:get("is_processing")
    if err then
      return false
    end
    return processing or false
  end

  -- Subscribe to provider changes
  function manager:subscribe_provider(callback)
    return self._store:subscribe("current_provider", callback)
  end

  -- Subscribe to model changes
  function manager:subscribe_model(callback)
    return self._store:subscribe("current_model", callback)
  end

  -- Subscribe to processing state changes
  function manager:subscribe_processing(callback)
    return self._store:subscribe("is_processing", callback)
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
    return {
      current_provider = self:get_provider(),
      current_model = self:get_model(),
      is_processing = self:is_processing()
    }
  end

  return manager
end

return M
