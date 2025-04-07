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
      width = 0.5,            -- Use 50% of screen width
      height = 0.4,           -- Use 40% of screen height
    },
  }):find()
end

return M
