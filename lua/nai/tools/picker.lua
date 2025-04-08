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

  -- Get list of available models for the current provider
  local models = {}
  local current_model = nil

  -- Handle different providers
  if provider == "openai" then
    models = config.options.providers.openai.models or {
      "gpt-4o",
      "gpt-4-turbo",
      "gpt-4",
      "gpt-3.5-turbo",
    }
    current_model = config.options.providers.openai.model
  elseif provider == "openrouter" then
    models = config.options.providers.openrouter.models or {
      "google/gemini-2.0-flash-001",
      "google/gemini-2.0-pro-001",
      "anthropic/claude-3-opus",
      "anthropic/claude-3-sonnet",
      "mistralai/mistral-large",
    }
    current_model = config.options.providers.openrouter.model
  end

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

        -- Set the selected model
        if selection then
          local model_name = selection.value
          config.options.providers[provider].model = model_name

          -- Notify user
          vim.notify("Model changed to " .. model_name, vim.log.levels.INFO)
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
