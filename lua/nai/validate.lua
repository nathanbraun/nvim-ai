-- lua/nai/validate.lua
local M = {}

-- Helper function to check if a value is of the expected type
function M.check_type(value, expected_type, path)
  local value_type = type(value)
  if value_type ~= expected_type then
    return false, string.format("Config error at %s: expected %s, got %s",
      path, expected_type, value_type)
  end
  return true, nil
end

-- Helper to check if a value is one of the allowed values
function M.check_enum(value, allowed_values, path)
  for _, allowed in ipairs(allowed_values) do
    if value == allowed then
      return true, nil
    end
  end

  return false, string.format("Config error at %s: value '%s' not in allowed values: %s",
    path, tostring(value), table.concat(allowed_values, ", "))
end

-- Validate the entire configuration
function M.validate_config(config)
  local errors = {}

  -- Check active_provider
  if config.active_provider then
    local valid, err = M.check_enum(config.active_provider, { "openai", "openrouter" }, "active_provider")
    if not valid then
      table.insert(errors, err)
    end

    -- Check if the specified provider exists in the providers table
    if not config.providers or not config.providers[config.active_provider] then
      table.insert(errors, "Config error: active_provider '" .. config.active_provider ..
        "' not found in providers configuration")
    end
  end

  -- Validate providers configuration
  if config.providers then
    local valid, err = M.check_type(config.providers, "table", "providers")
    if not valid then
      table.insert(errors, err)
    else
      -- Validate each provider
      for provider_name, provider_config in pairs(config.providers) do
        local provider_path = "providers." .. provider_name

        -- Check provider is a table
        local valid, err = M.check_type(provider_config, "table", provider_path)
        if not valid then
          table.insert(errors, err)
        else
          -- Check required fields
          if not provider_config.model then
            table.insert(errors, "Config error: " .. provider_path .. ".model is required")
          end

          if not provider_config.endpoint then
            table.insert(errors, "Config error: " .. provider_path .. ".endpoint is required")
          end

          -- Check types of common fields
          if provider_config.temperature ~= nil then
            local valid, err = M.check_type(provider_config.temperature, "number", provider_path .. ".temperature")
            if not valid then
              table.insert(errors, err)
            elseif provider_config.temperature < 0 or provider_config.temperature > 2 then
              table.insert(errors, "Config error: " .. provider_path ..
                ".temperature should be between 0 and 2")
            end
          end

          if provider_config.max_tokens ~= nil then
            local valid, err = M.check_type(provider_config.max_tokens, "number", provider_path .. ".max_tokens")
            if not valid then
              table.insert(errors, err)
            elseif provider_config.max_tokens <= 0 then
              table.insert(errors, "Config error: " .. provider_path ..
                ".max_tokens should be greater than 0")
            end
          end
        end
      end
    end
  end

  -- Validate mappings
  if config.mappings then
    local valid, err = M.check_type(config.mappings, "table", "mappings")
    if not valid then
      table.insert(errors, err)
    else
      if config.mappings.enabled ~= nil then
        local valid, err = M.check_type(config.mappings.enabled, "boolean", "mappings.enabled")
        if not valid then
          table.insert(errors, err)
        end
      end

      -- Validate mapping categories
      for _, category in ipairs({ "chat", "insert", "settings" }) do
        if config.mappings[category] then
          local valid, err = M.check_type(config.mappings[category], "table", "mappings." .. category)
          if not valid then
            table.insert(errors, err)
          end
        end
      end
    end
  end

  -- Validate highlights
  if config.highlights then
    local valid, err = M.check_type(config.highlights, "table", "highlights")
    if not valid then
      table.insert(errors, err)
    else
      -- Check each highlight group
      for group_name, highlight in pairs(config.highlights) do
        local highlight_path = "highlights." .. group_name
        local valid, err = M.check_type(highlight, "table", highlight_path)
        if not valid then
          table.insert(errors, err)
        end
      end
    end
  end

  -- Return all validation errors
  return errors
end

-- Apply the validation and handle errors
function M.apply_validation(config)
  local errors = M.validate_config(config)

  if #errors > 0 then
    -- Log all errors
    vim.notify("nvim-ai configuration has errors:", vim.log.levels.WARN)
    for _, err in ipairs(errors) do
      vim.notify(err, vim.log.levels.WARN)
    end

    -- Return false to indicate validation failure
    return false
  end

  -- Return true to indicate validation success
  return true
end

return M
