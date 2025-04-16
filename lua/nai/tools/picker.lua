-- lua/nai/tools/picker.lua
local M = {}

function M.select_model()
  -- Check if telescope is available
  local has_telescope, telescope = pcall(require, 'telescope')
  if not has_telescope then
    vim.notify("Telescope is required but not found", vim.log.levels.ERROR)
    return
  end

  -- Get configuration
  local config = require('nai.config')
  local provider = config.options.active_provider
  local provider_config = config.options.providers[provider]

  if not provider_config then
    vim.notify("Provider configuration not found for: " .. provider, vim.log.levels.ERROR)
    return
  end

  -- Get list of available models for the current provider
  local models = {}

  -- For Ollama, dynamically fetch available models
  if provider == "ollama" then
    -- Check if ollama is installed
    if vim.fn.executable('ollama') ~= 1 then
      vim.notify("Ollama executable not found in PATH", vim.log.levels.ERROR)
      return
    end

    -- Use vim.system to run the command asynchronously
    vim.system({ "ollama", "list" }, { text = true }, function(obj)
      if obj.code ~= 0 then
        vim.schedule(function()
          vim.notify("Failed to get Ollama models: " .. (obj.stderr or "unknown error"), vim.log.levels.ERROR)
        end)
        return
      end

      local output = obj.stdout
      if not output or output == "" then
        vim.schedule(function()
          vim.notify("No models found in Ollama", vim.log.levels.WARN)
        end)
        return
      end

      -- Parse the output to extract model names
      -- The format is typically:
      -- NAME            ID              SIZE    MODIFIED
      -- llama3          ...             ...     ...
      local ollama_models = {}

      -- Skip the header line
      local lines = vim.split(output, "\n")
      for i = 2, #lines do
        local line = lines[i]
        if line ~= "" then
          -- Extract the first column (model name)
          local model_name = line:match("^(%S+)")
          if model_name then
            table.insert(ollama_models, model_name)
          end
        end
      end

      -- If no models were found, show a message
      if #ollama_models == 0 then
        vim.schedule(function()
          vim.notify("No models found in Ollama output", vim.log.levels.WARN)
        end)
        return
      end

      -- Continue with the telescope picker using the fetched models
      vim.schedule(function()
        M.show_model_picker(provider, provider_config, ollama_models)
      end)
    end)

    -- Return early since we're handling this asynchronously
    return
  else
    -- For other providers, use the existing logic
    models = provider_config.models or {}
    if #models == 0 then
      -- Fallback models if none defined in config
      if provider == "openai" then
        models = {
          "gpt-4o",
          "gpt-4-turbo",
          "gpt-4",
          "gpt-3.5-turbo",
        }
      elseif provider == "openrouter" then
        models = {
          "google/gemini-2.0-flash-001",
          "google/gemini-2.0-pro-001",
          "anthropic/claude-3-opus",
          "anthropic/claude-3-sonnet",
          "mistralai/mistral-large",
        }
      end
    end

    -- Show the picker with the models
    M.show_model_picker(provider, provider_config, models)
  end
end

-- Extract the telescope picker logic into a separate function
function M.show_model_picker(provider, provider_config, models)
  local current_model = provider_config.model or ""

  -- Format for telescope finder
  local finder_items = {}
  for _, model_name in ipairs(models) do
    table.insert(finder_items, {
      display = model_name .. (model_name == current_model and " (current)" or ""),
      value = model_name,
      ordinal = model_name -- For sorting
    })
  end

  -- Create the picker using telescope
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values

  pickers.new({}, {
    prompt_title = "Select " .. provider .. " Model",
    finder = finders.new_table {
      results = finder_items,
      entry_maker = function(entry)
        return {
          value = entry.value,
          display = entry.display,
          ordinal = entry.ordinal
        }
      end
    },
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)

        -- Set the selected model for the current provider
        if selection then
          local model_id = selection.value

          -- Update the model in the provider's configuration
          local config = require('nai.config')
          config.options.providers[provider].model = model_id

          -- Update state
          require('nai.state').set_current_model(model_id)
          require('nai.events').emit('model:change', model_id)

          -- Notify user
          vim.notify("Model changed to " .. model_id, vim.log.levels.INFO)
        end
      end)
      return true
    end,
    layout_strategy = "center", -- Center the window
    layout_config = {
      width = 0.5,              -- Use 50% of screen width
      height = 0.4,             -- Use 40% of screen height
    },
  }):find()
end

function M.select_provider()
  -- Check if telescope is available
  local has_telescope, telescope = pcall(require, 'telescope')
  if not has_telescope then
    vim.notify("Telescope is required but not found", vim.log.levels.ERROR)
    return
  end

  -- Get configuration
  local config = require('nai.config')
  local current_provider = config.options.active_provider

  -- Get providers from config
  local providers = {}
  for provider_id, provider_config in pairs(config.options.providers) do
    table.insert(providers, {
      id = provider_id,
      name = provider_config.name or provider_id,
      description = provider_config.description or "",
      config = provider_config
    })
  end

  -- Format for telescope finder
  local finder_items = {}
  for _, provider in ipairs(providers) do
    table.insert(finder_items, {
      display = provider.name .. (provider.id == current_provider and " (current)" or ""),
      value = provider.id,
      description = provider.description,
      config = provider.config,
      ordinal = provider.name -- For sorting
    })
  end

  -- Create the picker using telescope
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local previewers = require("telescope.previewers")

  -- Create a custom previewer
  local provider_previewer = previewers.new_buffer_previewer({
    title = "Provider Info",
    define_preview = function(self, entry, status)
      local preview_lines = {
        "Provider: " .. entry.display,
        "",
        entry.description or "",
        "",
        "Current Configuration:",
        "-------------------",
        "Model: " .. (entry.config.model or "Not set"),
        "Temperature: " .. (entry.config.temperature or "Not set"),
        "Max Tokens: " .. (entry.config.max_tokens or "Not set"),
      }

      -- Add available models if present
      if entry.config.models and #entry.config.models > 0 then
        table.insert(preview_lines, "")
        table.insert(preview_lines, "Available Models:")
        table.insert(preview_lines, "---------------")
        for _, model in ipairs(entry.config.models) do
          table.insert(preview_lines, "- " .. model)
        end
      end

      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, preview_lines)
    end
  })

  pickers.new({}, {
    prompt_title = "Select AI Provider",
    finder = finders.new_table {
      results = finder_items,
      entry_maker = function(entry)
        return {
          value = entry.value,
          display = entry.display,
          ordinal = entry.ordinal,
          description = entry.description,
          config = entry.config
        }
      end
    },
    sorter = conf.generic_sorter({}),
    previewer = provider_previewer,
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)

        -- Set the selected provider
        if selection then
          local provider_id = selection.value
          config.options.active_provider = provider_id

          -- Notify user
          local provider_name = config.options.providers[provider_id].name or provider_id
          vim.notify("Provider changed to " .. provider_name, vim.log.levels.INFO)
        end
      end)
      return true
    end,
    layout_strategy = "center", -- Center the window
    layout_config = {
      width = 0.6,              -- Use 60% of screen width
      height = 0.6,             -- Use 60% of screen height
    },
  }):find()
end

return M
