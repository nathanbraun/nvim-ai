-- lua/nai/tools/picker.lua
local M = {}

function M.select_model()
  -- Get configuration
  local config = require('nai.config')
  local current_provider = config.options.active_provider
  local current_model = config.options.providers[current_provider].model

  -- Create a unified list of all models across providers
  local all_models = {}

  -- Find the longest provider name for padding
  local max_provider_length = 0
  for provider_id, _ in pairs(config.options.providers) do
    max_provider_length = math.max(max_provider_length, #provider_id)
  end

  -- Go through each provider and collect their models
  for provider_id, provider_config in pairs(config.options.providers) do
    local provider_name = provider_config.name or provider_id
    local models = provider_config.models or {}

    -- Create fixed-width provider prefix
    local provider_prefix = string.format("%-" .. max_provider_length .. "s", provider_id)

    -- For Ollama, we'll handle it differently (see below)
    if provider_id ~= "ollama" then
      -- Add each model to our unified list
      for _, model_id in ipairs(models) do
        -- Create a display name that includes provider info
        local display_name

        -- For models with provider in the name (like google/gemini), extract just the model part
        if model_id:match("/") then
          local _, model_part = model_id:match("([^/]+)/(.+)")
          display_name = provider_prefix .. " │ " .. model_part
        else
          display_name = provider_prefix .. " │ " .. model_id
        end

        table.insert(all_models, {
          display = display_name ..
              (model_id == current_model and current_provider == provider_id and " (current)" or ""),
          value = model_id,
          provider = provider_id,
          ordinal = provider_id .. " " .. model_id -- For sorting
        })
      end

      -- Also add the current model if it's not in the list
      local current_in_list = false
      if provider_id == current_provider then
        for _, model in ipairs(models) do
          if model == current_model then
            current_in_list = true
            break
          end
        end

        if not current_in_list then
          local display_name
          if current_model:match("/") then
            local _, model_part = current_model:match("([^/]+)/(.+)")
            display_name = provider_prefix .. " │ " .. model_part
          else
            display_name = provider_prefix .. " │ " .. current_model
          end

          table.insert(all_models, {
            display = display_name .. " (current)",
            value = current_model,
            provider = provider_id,
            ordinal = provider_id .. " " .. current_model
          })
        end
      end
    end
  end

  -- Handle Ollama models separately - fetch them dynamically if possible
  if vim.fn.executable('ollama') == 1 then
    -- Create fixed-width provider prefix for Ollama
    local provider_prefix = string.format("%-" .. max_provider_length .. "s", "ollama")

    vim.system({ "ollama", "list" }, { text = true }, function(obj)
      if obj.code == 0 and obj.stdout and obj.stdout ~= "" then
        -- Parse the output to extract model names
        local ollama_models = {}

        -- Skip the header line
        local lines = vim.split(obj.stdout, "\n")
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

        -- Add Ollama models to our unified list
        for _, model_id in ipairs(ollama_models) do
          local display_name = provider_prefix .. " │ " .. model_id

          table.insert(all_models, {
            display = display_name .. (model_id == current_model and current_provider == "ollama" and " (current)" or ""),
            value = model_id,
            provider = "ollama",
            ordinal = "ollama " .. model_id -- For sorting
          })
        end

        -- Show the picker with all models
        vim.schedule(function()
          M.show_unified_model_picker_with_fallbacks(all_models, current_provider, current_model)
        end)
      else
        -- If we couldn't get Ollama models, just show what we have
        vim.schedule(function()
          M.show_unified_model_picker_with_fallbacks(all_models, current_provider, current_model)
        end)
      end
    end)
  else
    -- If Ollama is not available, just show the models we have
    M.show_unified_model_picker_with_fallbacks(all_models, current_provider, current_model)
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

function M.show_unified_model_picker(models, current_provider, current_model)
  -- Create the picker using telescope
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values

  pickers.new({}, {
    prompt_title = "Select AI Model",
    finder = finders.new_table {
      results = models,
      entry_maker = function(entry)
        return {
          value = entry.value,
          display = entry.display,
          ordinal = entry.ordinal,
          provider = entry.provider
        }
      end
    },
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)

        if selection then
          local model_id = selection.value
          local provider_id = selection.provider

          -- Switch provider if needed
          if provider_id ~= current_provider then
            local config = require('nai.config')
            config.options.active_provider = provider_id
            require('nai.state').set_current_provider(provider_id)

            -- Notify about provider change
            vim.notify("Switched to " .. provider_id .. " provider", vim.log.levels.INFO)
          end

          -- Update the model
          local config = require('nai.config')
          config.options.providers[provider_id].model = model_id

          -- Update state
          require('nai.state').set_current_model(model_id)
          require('nai.events').emit('model:change', model_id)

          -- Notify user
          vim.notify("Model changed to " .. model_id, vim.log.levels.INFO)
        end
      end)
      return true
    end,
    layout_strategy = "center",
    layout_config = {
      width = 0.6,
      height = 0.5,
    },
  }):find()
end

function M.show_unified_model_picker_with_fallbacks(models, current_provider, current_model)
  -- Try snacks first
  local has_snacks, snacks = pcall(require, 'snacks')
  if has_snacks then
    return M.show_unified_model_picker_snacks(models, current_provider, current_model)
  end

  -- Try telescope next
  local has_telescope, telescope = pcall(require, 'telescope')
  if has_telescope then
    return M.show_unified_model_picker_telescope(models, current_provider, current_model)
  end

  -- Try fzf-lua last
  local has_fzf_lua, fzf_lua = pcall(require, 'fzf-lua')
  if has_fzf_lua then
    return M.show_unified_model_picker_fzf_lua(models, current_provider, current_model)
  end

  -- Fallback to simple UI if none of the pickers are available
  vim.notify("No picker plugin found (snacks, telescope, or fzf-lua)", vim.log.levels.WARN)
  return M.show_unified_model_picker_simple(models, current_provider, current_model)
end

-- Implementation for snacks
function M.show_unified_model_picker_snacks(models, current_provider, current_model)
  -- Check if Snacks is available
  local has_snacks, Snacks = pcall(require, 'snacks')
  if not has_snacks then
    return false
  end

  -- Create a custom finder function
  local finder = function()
    local items = {}
    for i, model in ipairs(models) do
      table.insert(items, {
        idx = i,
        text = model.display,
        value = model.value,
        provider = model.provider,
        ordinal = model.ordinal,
        -- Add a preview property to avoid the error
        preview = {
          text = "Model: " .. model.value ..
              "\nProvider: " .. model.provider ..
              "\n\nStatus: " .. (model.value == current_model and model.provider == current_provider
                and "Current model" or "Available model"),
          ft = "markdown" -- Use markdown for nice highlighting
        }
      })
    end
    return items
  end

  -- Use Snacks picker with a custom source config
  Snacks.picker.pick({
    finder = finder,           -- Use our custom finder function
    format = function(item)
      return { { item.text } } -- Format the display text
    end,
    title = "Select AI Model",
    preview = "preview", -- Use the preview from the item
    confirm = function(picker, item)
      -- Close the picker first
      picker:close()

      -- Then handle the selection
      if item then
        local model_id = item.value
        local provider_id = item.provider

        -- Switch provider if needed
        if provider_id ~= current_provider then
          local config = require('nai.config')
          config.options.active_provider = provider_id
          require('nai.state').set_current_provider(provider_id)

          -- Notify about provider change
          vim.notify("Switched to " .. provider_id .. " provider", vim.log.levels.INFO)
        end

        -- Update the model
        local config = require('nai.config')
        config.options.providers[provider_id].model = model_id

        -- Update state
        require('nai.state').set_current_model(model_id)
        require('nai.events').emit('model:change', model_id)

        -- Notify user
        vim.notify("Model changed to " .. model_id, vim.log.levels.INFO)
      end
    end
  })

  return true
end

-- Implementation for telescope (existing function renamed)
function M.show_unified_model_picker_telescope(models, current_provider, current_model)
  -- Create the picker using telescope
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values

  pickers.new({}, {
    prompt_title = "Select AI Model",
    finder = finders.new_table {
      results = models,
      entry_maker = function(entry)
        return {
          value = entry.value,
          display = entry.display,
          ordinal = entry.ordinal,
          provider = entry.provider
        }
      end
    },
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)

        if selection then
          local model_id = selection.value
          local provider_id = selection.provider

          -- Switch provider if needed
          if provider_id ~= current_provider then
            local config = require('nai.config')
            config.options.active_provider = provider_id
            require('nai.state').set_current_provider(provider_id)

            -- Notify about provider change
            vim.notify("Switched to " .. provider_id .. " provider", vim.log.levels.INFO)
          end

          -- Update the model
          local config = require('nai.config')
          config.options.providers[provider_id].model = model_id

          -- Update state
          require('nai.state').set_current_model(model_id)
          require('nai.events').emit('model:change', model_id)

          -- Notify user
          vim.notify("Model changed to " .. model_id, vim.log.levels.INFO)
        end
      end)
      return true
    end,
    layout_strategy = "center",
    layout_config = {
      width = 0.6,
      height = 0.5,
    },
  }):find()
end

function M.show_unified_model_picker_fzf_lua(models, current_provider, current_model)
  local fzf_lua = require('fzf-lua')

  -- Format items for fzf-lua
  local items = {}
  local item_map = {}
  for i, model in ipairs(models) do
    table.insert(items, model.display)
    item_map[model.display] = model
  end

  fzf_lua.fzf_exec(items, {
    prompt = "Select AI Model> ",
    actions = {
      ["default"] = function(selected)
        if selected and #selected > 0 then
          local selected_display = selected[1]
          local model = item_map[selected_display]
          if model then
            local model_id = model.value
            local provider_id = model.provider

            -- Switch provider if needed
            if provider_id ~= current_provider then
              local config = require('nai.config')
              config.options.active_provider = provider_id
              require('nai.state').set_current_provider(provider_id)

              -- Notify about provider change
              vim.notify("Switched to " .. provider_id .. " provider", vim.log.levels.INFO)
            end

            -- Update the model
            local config = require('nai.config')
            config.options.providers[provider_id].model = model_id

            -- Update state
            require('nai.state').set_current_model(model_id)
            require('nai.events').emit('model:change', model_id)

            -- Notify user
            vim.notify("Model changed to " .. model_id, vim.log.levels.INFO)
          end
        end
      end
    }
  })

  return true
end

-- Simple fallback using vim.ui.select
function M.show_unified_model_picker_simple(models, current_provider, current_model)
  local items = {}
  for _, model in ipairs(models) do
    table.insert(items, {
      name = model.display,
      value = model.value,
      provider = model.provider
    })
  end

  vim.ui.select(items, {
    prompt = "Select AI Model",
    format_item = function(item)
      return item.name
    end
  }, function(choice)
    if choice then
      local model_id = choice.value
      local provider_id = choice.provider

      -- Switch provider if needed
      if provider_id ~= current_provider then
        local config = require('nai.config')
        config.options.active_provider = provider_id
        require('nai.state').set_current_provider(provider_id)

        -- Notify about provider change
        vim.notify("Switched to " .. provider_id .. " provider", vim.log.levels.INFO)
      end

      -- Update the model
      local config = require('nai.config')
      config.options.providers[provider_id].model = model_id

      -- Update state
      require('nai.state').set_current_model(model_id)
      require('nai.events').emit('model:change', model_id)

      -- Notify user
      vim.notify("Model changed to " .. model_id, vim.log.levels.INFO)
    end
  end)

  return true
end

return M
