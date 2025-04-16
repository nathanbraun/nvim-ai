-- plugin/nvim-ai.lua
-- Entry point for the plugin

-- Prevent loading twice
if vim.g.loaded_nvim_ai then
  return
end
vim.g.loaded_nvim_ai = true

vim.api.nvim_create_user_command('NAIProvider', function()
  require('nai.tools.picker').select_provider()
end, { nargs = 0, desc = 'Select AI provider' })

vim.api.nvim_create_user_command('NAIExpand', function()
  require('nai').expand_blocks_command()
end, { desc = 'Expand all special blocks without continuing chat' })


vim.api.nvim_create_user_command('NAIChat', function(opts)
  require('nai').chat(opts)
end, { range = true, nargs = '?', desc = 'AI chat' })

vim.api.nvim_create_user_command('NAICancel', function()
  require('nai').cancel()
end, { desc = 'Cancel ongoing AI request' })

vim.api.nvim_create_user_command('NAINew', function()
  require('nai').new_chat()
end, { desc = 'Create new empty AI chat file' })

vim.api.nvim_create_user_command('NAIScrape', function(opts)
  local parser = require('nai.parser')
  local url = opts.args

  -- Insert a properly formatted scrape block at cursor position
  local scrape_block = parser.format_scrape_block(url)
  local lines = vim.split(scrape_block, "\n")

  -- Insert at cursor position
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1

  vim.api.nvim_buf_set_lines(0, row, row, false, lines)

  -- Position cursor at end of inserted block
  vim.api.nvim_win_set_cursor(0, { row + #lines, 0 })
end, {
  nargs = "?",
  desc = "Insert a scrape block at cursor position",
  complete = function(ArgLead, CmdLine, CursorPos)
    -- Simple clipboard-based URL completion
    local clipboard = vim.fn.getreg("+"):match("https?://[%w%p]+")
    if clipboard and clipboard:find(ArgLead, 1, true) == 1 then
      return { clipboard }
    end
    return {}
  end
})

vim.api.nvim_create_user_command('NAICrawl', function(opts)
  local parser = require('nai.parser')
  local url = opts.args

  -- Insert a properly formatted crawl block at cursor position
  local crawl_block = parser.format_crawl_block(url)
  local lines = vim.split(crawl_block, "\n")

  -- Insert at cursor position
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1

  vim.api.nvim_buf_set_lines(0, row, row, false, lines)

  -- Position cursor at end of inserted block
  vim.api.nvim_win_set_cursor(0, { row + #lines, 0 })
end, {
  nargs = "?",
  desc = "Insert a website crawl block at cursor position",
  complete = function(ArgLead, CmdLine, CursorPos)
    -- Simple clipboard-based URL completion
    local clipboard = vim.fn.getreg("+"):match("https?://[%w%p]+")
    if clipboard and clipboard:find(ArgLead, 1, true) == 1 then
      return { clipboard }
    end
    return {}
  end
})

vim.api.nvim_create_user_command('NAIExpandScrape', function()
  local scrape = require('nai.fileutils.scrape')
  local buffer_id = vim.api.nvim_get_current_buf()

  scrape.expand_scrape_blocks_in_buffer(buffer_id)
end, { desc = 'Expand all scrape blocks in current buffer' })

vim.api.nvim_create_user_command('NAIYoutube', function(opts)
  local parser = require('nai.parser')
  local url = opts.args

  -- Insert a properly formatted YouTube block at cursor position
  local youtube_block = parser.format_youtube_block(url)
  local lines = vim.split(youtube_block, "\n")

  -- Insert at cursor position
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1

  vim.api.nvim_buf_set_lines(0, row, row, false, lines)

  -- Position cursor at end of inserted block
  vim.api.nvim_win_set_cursor(0, { row + #lines, 0 })
end, {
  nargs = "?",
  desc = "Insert a YouTube transcript block at cursor position",
  complete = function(ArgLead, CmdLine, CursorPos)
    -- Simple clipboard-based URL completion
    local clipboard = vim.fn.getreg("+"):match("https?://[%w%p]+")
    if clipboard and clipboard:find("youtube", 1, true) and clipboard:find(ArgLead, 1, true) == 1 then
      return { clipboard }
    end
    return {}
  end
})

vim.api.nvim_create_user_command('NAIUser', function()
  local parser = require('nai.parser')
  local buffer_id = vim.api.nvim_get_current_buf()

  -- Create the user message template
  local user_template = parser.format_user_message("")
  local user_lines = vim.split(user_template, "\n")

  -- Add at the end of the buffer
  vim.api.nvim_buf_set_lines(buffer_id, -1, -1, false, user_lines)

  -- Position cursor on the last line
  local line_count = vim.api.nvim_buf_line_count(buffer_id)
  vim.api.nvim_win_set_cursor(0, { line_count, 0 })
end, { desc = 'Add a new user message' })

vim.api.nvim_create_user_command('NAIReference', function(opts)
  local parser = require('nai.parser')
  local reference_block = parser.format_reference_block(opts.args or "")
  local lines = vim.split(reference_block, "\n")

  -- Insert at cursor position
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1

  vim.api.nvim_buf_set_lines(0, row, row, false, lines)

  -- Position cursor at end of inserted block
  vim.api.nvim_win_set_cursor(0, { row + #lines, 0 })
end, {
  nargs = "?",
  desc = "Insert an reference block at cursor position"
})

vim.api.nvim_create_user_command('NAISnapshot', function()
  local parser = require('nai.parser')
  local snapshot_block = parser.format_snapshot()
  local lines = vim.split(snapshot_block, "\n")

  -- Insert at cursor position
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1

  vim.api.nvim_buf_set_lines(0, row, row, false, lines)

  -- Position cursor at end of inserted block
  vim.api.nvim_win_set_cursor(0, { row + #lines, 0 })
end, {
  desc = "Insert a snapshot block at cursor position"
})

vim.api.nvim_create_user_command('NAIWeb', function(opts)
  local parser = require('nai.parser')
  local url = opts.args

  -- Insert a properly formatted web block at cursor position
  local web_block = parser.format_web_block(url or "")
  local lines = vim.split(web_block, "\n")

  -- Insert at cursor position
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1

  vim.api.nvim_buf_set_lines(0, row, row, false, lines)

  -- Position cursor at end of inserted block
  vim.api.nvim_win_set_cursor(0, { row + #lines, 0 })
end, {
  nargs = "?",
  desc = "Insert a web block at cursor position",
  complete = function(ArgLead, CmdLine, CursorPos)
    -- Simple clipboard-based URL completion
    local clipboard = vim.fn.getreg("+"):match("https?://[%w%p]+")
    if clipboard and clipboard:find(ArgLead, 1, true) == 1 then
      return { clipboard }
    end
    return {}
  end
})

-- Add this to plugin/nvim-ai.lua, inside the plugin initialization section
vim.api.nvim_create_user_command('NAIModel', function()
  require('nai.tools.picker').select_model()
end, { nargs = 0, desc = 'Select LLM model' })

vim.api.nvim_create_user_command('NAIRefreshHighlights', function()
  require('nai.syntax').define_highlight_groups()

  -- Reapply syntax to all activated buffers
  local state = require('nai.state')
  for bufnr, _ in pairs(state.activated_buffers) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      require('nai.buffer').apply_syntax_overlay(bufnr)
    end
  end

  vim.notify("NAI syntax highlighting refreshed", vim.log.levels.INFO)
end, { desc = 'Refresh NAI syntax highlighting' })

vim.api.nvim_create_user_command('NAIConfig', function()
  local parser = require('nai.parser')
  local config = require('nai.config')

  -- Get current provider config
  local provider = config.options.active_provider
  local provider_config = config.get_provider_config()

  -- Create a config block with current settings
  local config_options = {
    provider = provider,
    model = provider_config.model,
    temperature = provider_config.temperature,
    max_tokens = provider_config.max_tokens,
    expand_placeholders = config.options.expand_placeholders -- Include the expand_placeholders option
  }

  local config_block = parser.format_config_block(config_options)
  local lines = vim.split(config_block, "\n")

  -- Get current buffer lines
  local buffer_id = vim.api.nvim_get_current_buf()
  local buffer_lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)

  -- Determine insertion position
  local insert_position = 0 -- Default to cursor position
  local cursor_pos = vim.api.nvim_win_get_cursor(0)

  -- Option 1: Insert at cursor position
  insert_position = cursor_pos[1] - 1 -- Convert to 0-indexed

  -- Option 2: Try to find position after YAML header but before first message
  local yaml_end = -1
  local first_message = -1

  for i, line in ipairs(buffer_lines) do
    -- Find end of YAML header
    if line == "---" and i > 1 then
      yaml_end = i
    end

    -- Find first message marker
    if line:match("^>>>") or line:match("^<<<") then
      first_message = i - 1 -- Insert before this line
      break
    end
  end

  -- If we found a suitable position after YAML but before first message
  if yaml_end > 0 and first_message > yaml_end then
    insert_position = yaml_end -- Insert right after the YAML header
  end

  -- Insert the config block
  vim.api.nvim_buf_set_lines(buffer_id, insert_position, insert_position, false, lines)

  -- Position cursor at end of inserted block
  vim.api.nvim_win_set_cursor(0, { insert_position + #lines, 0 })

  -- Notify the user
  vim.notify("Config block inserted with current settings", vim.log.levels.INFO)
end, { desc = "Insert a config block at an appropriate position" })

vim.api.nvim_create_user_command('NAISetKey', function(opts)
  local args = opts.args
  local provider, key

  -- Parse arguments: provider and key
  if args and args:match("%S+%s+%S+") then
    provider, key = args:match("(%S+)%s+(.+)")
  elseif args and args:match("%S+") then
    provider = args:match("(%S+)")
    -- If only provider is given, prompt for key
    key = vim.fn.inputsecret("Enter API key for " .. provider .. ": ")
  else
    -- Interactive mode - ask for both provider and key
    local providers = { "openai", "openrouter", "dumpling", "ollama" }

    -- Use simple input instead of input with completion
    provider = vim.fn.input("Provider (openai, openrouter, dumpling, ollama): ")

    if provider == "" then
      vim.notify("Operation cancelled", vim.log.levels.INFO)
      return
    end

    key = vim.fn.inputsecret("Enter API key for " .. provider .. ": ")
  end

  if key == "" then
    vim.notify("No API key provided, operation cancelled", vim.log.levels.INFO)
    return
  end

  -- Validate provider
  local valid_providers = { "openai", "openrouter", "dumpling", "ollama" }
  local is_valid = false
  for _, valid_provider in ipairs(valid_providers) do
    if provider == valid_provider then
      is_valid = true
      break
    end
  end

  if not is_valid then
    vim.notify("Invalid provider: " .. provider .. ". Valid options: " .. table.concat(valid_providers, ", "),
      vim.log.levels.ERROR)
    return
  end

  -- Check if the credentials file exists and contains this provider already
  local config = require('nai.config')
  local path = require('nai.utils.path')
  local credentials_file = path.expand(config.options.credentials.file_path)

  local existing_credentials = {}
  if vim.fn.filereadable(credentials_file) == 1 then
    local content = vim.fn.readfile(credentials_file)
    local success, creds = pcall(vim.json.decode, table.concat(content, '\n'))

    if success and type(creds) == "table" then
      existing_credentials = creds

      -- Check if provider key already exists
      if existing_credentials[provider] then
        local overwrite = vim.fn.confirm(
          "API key for " .. provider .. " already exists. Overwrite?",
          "&Yes\n&No",
          2
        )

        if overwrite ~= 1 then
          vim.notify("Operation cancelled", vim.log.levels.INFO)
          return
        end
      end
    end
  end

  -- Ensure the directory exists first
  local config_dir = vim.fn.fnamemodify(credentials_file, ":h")
  if vim.fn.isdirectory(config_dir) ~= 1 then
    local mkdir_result = vim.fn.mkdir(config_dir, "p")
    if mkdir_result ~= 1 then
      vim.notify("Failed to create config directory: " .. config_dir, vim.log.levels.ERROR)
      return
    end
  end

  -- Update the credentials with the new key
  existing_credentials[provider] = key

  -- Format the JSON with indentation
  local formatted_json = "{\n"
  local keys = {}
  for k in pairs(existing_credentials) do
    table.insert(keys, k)
  end
  table.sort(keys) -- Sort keys for consistent output

  for i, k in ipairs(keys) do
    local v = existing_credentials[k]
    formatted_json = formatted_json .. string.format('  "%s": "%s"', k, v)
    if i < #keys then
      formatted_json = formatted_json .. ",\n"
    else
      formatted_json = formatted_json .. "\n"
    end
  end
  formatted_json = formatted_json .. "}\n"

  -- Write back to file
  local file = io.open(credentials_file, "w")

  if file then
    file:write(formatted_json)
    file:close()

    -- Set permissions to be readable only by the owner on Unix
    if vim.fn.has('unix') == 1 then
      vim.fn.system("chmod 600 " .. vim.fn.shellescape(credentials_file))
    end

    vim.notify("API key for " .. provider .. " saved successfully", vim.log.levels.INFO)
  else
    vim.notify("Failed to save API key: could not write to " .. credentials_file, vim.log.levels.ERROR)
  end
end, {
  nargs = "*",
  desc = "Set API key for a provider (usage: NAISetKey [provider] [key])",
  complete = function(ArgLead, CmdLine, CursorPos)
    -- Provide completion for providers
    local providers = { "openai", "openrouter", "dumpling", "ollama" }
    if CmdLine:match("^%s*NAISetKey%s+%S+%s+") then
      -- If provider is already specified, don't provide completions for the key
      return {}
    end

    -- Filter providers based on ArgLead
    local filtered = {}
    for _, provider in ipairs(providers) do
      if provider:find(ArgLead, 1, true) == 1 then
        table.insert(filtered, provider)
      end
    end
    return filtered
  end
})

-- Command to check which API keys are configured
vim.api.nvim_create_user_command('NAICheckKeys', function()
  local config = require('nai.config')
  local providers = { "openai", "openrouter", "dumpling" }
  local results = {}

  for _, provider in ipairs(providers) do
    local key = config.get_api_key(provider)
    if provider ~= "dumpling" then
      -- For regular providers
      if key then
        table.insert(results, provider .. ": ✓ Configured")
      else
        table.insert(results, provider .. ": ✗ Not configured")
      end
    else
      -- For dumpling
      key = config.get_dumpling_api_key()
      if key then
        table.insert(results, "dumpling: ✓ Configured")
      else
        table.insert(results, "dumpling: ✗ Not configured")
      end
    end
  end

  -- Create a temporary buffer to display results
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "nvim-ai API Key Status:",
    "=====================",
    ""
  })
  vim.api.nvim_buf_set_lines(buf, 3, 3, false, results)

  -- Add instructions
  vim.api.nvim_buf_set_lines(buf, 3 + #results, 3 + #results, false, {
    "",
    "To set an API key, use: :NAISetKey [provider]",
    "Active provider: " .. config.options.active_provider,
    "",
    "Press q to close this window"
  })

  -- Open the buffer in a floating window
  local width = 60
  local height = 10 + #results
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = "API Key Status",
    title_pos = "center"
  })

  -- Set buffer options
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")

  -- Add keymapping to close the window
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':close<CR>', { noremap = true, silent = true })

  -- Highlight the active provider
  local ns_id = vim.api.nvim_create_namespace('nai_key_status')
  for i, line in ipairs(results) do
    if line:match("^" .. config.options.active_provider) then
      vim.api.nvim_buf_add_highlight(buf, ns_id, "Title", 2 + i, 0, -1)
    end
  end

  -- Highlight configured vs not configured
  for i, line in ipairs(results) do
    if line:match("✓") then
      vim.api.nvim_buf_add_highlight(buf, ns_id, "DiagnosticOk", 2 + i, line:find("✓"), line:find("✓") + 3)
    elseif line:match("✗") then
      vim.api.nvim_buf_add_highlight(buf, ns_id, "DiagnosticError", 2 + i, line:find("✗"), line:find("✗") + 3)
    end
  end
end, { desc = "Check which API keys are configured" })

-- Add a command to quickly switch between providers
vim.api.nvim_create_user_command('NAISwitchProvider', function(opts)
  local provider = opts.args

  if not provider or provider == "" then
    -- If no provider specified, show current and prompt for new one
    local config = require('nai.config')
    local current = config.options.active_provider

    provider = vim.fn.input({
      prompt = "Current provider: " .. current .. "\nSwitch to (openai, openrouter, ollama): ",
      completion = function(_, _, _)
        return { "openai", "openrouter", "ollama" }
      end
    })

    if provider == "" then
      vim.notify("Operation cancelled", vim.log.levels.INFO)
      return
    end
  end

  -- Validate provider
  if provider ~= "openai" and provider ~= "openrouter" and provider ~= "ollama" then
    vim.notify("Invalid provider: " .. provider .. ". Valid options: openai, openrouter, ollama", vim.log.levels.ERROR)
    return
  end

  -- Switch provider
  local config = require('nai.config')
  config.options.active_provider = provider

  -- Update state
  require('nai.state').set_current_provider(provider)

  -- If switching to Ollama, ensure the model is valid
  if provider == "ollama" then
    config.ensure_valid_ollama_model(config.options.providers.ollama)
  end

  -- Check if API key exists for this provider (except for Ollama which might not need one)
  if provider ~= "ollama" then
    local key = config.get_api_key(provider)
    if not key then
      vim.notify("Warning: No API key found for " .. provider .. ". Use :NAISetKey " .. provider .. " to set one.",
        vim.log.levels.WARN)
    else
      vim.notify("Switched to " .. provider .. " provider", vim.log.levels.INFO)
    end
  else
    vim.notify("Switched to " .. provider .. " provider", vim.log.levels.INFO)
  end
end, {
  nargs = "?",
  desc = "Switch between AI providers",
  complete = function(ArgLead, CmdLine, CursorPos)
    local providers = { "openai", "openrouter", "ollama" }
    local filtered = {}
    for _, provider in ipairs(providers) do
      if provider:find(ArgLead, 1, true) == 1 then
        table.insert(filtered, provider)
      end
    end
    return filtered
  end
})

-- Test command
vim.api.nvim_create_user_command('NAITest', function(opts)
  local group = opts.args
  local tests = require('nai.tests')

  if group and group ~= "" then
    tests.run_group(group)
  else
    tests.run_all()
  end
end, {
  nargs = "?",
  desc = "Run nvim-ai tests (optional: parser, config, integration, fileutils)", -- Update description
  complete = function(ArgLead, CmdLine, CursorPos)
    local groups = { "parser", "config", "integration", "fileutils" }            -- Add fileutils
    local filtered = {}
    for _, group in ipairs(groups) do
      if group:find(ArgLead, 1, true) == 1 then
        table.insert(filtered, group)
      end
    end
    return filtered
  end
})

vim.api.nvim_create_user_command('NAIDebug', function()
  local state = require('nai.state')
  local debug_info = state.debug()

  -- Create a buffer to display debug info
  local buf = vim.api.nvim_create_buf(false, true)

  -- Format debug info
  local lines = {
    "nvim-ai Debug Information",
    "=======================",
    "",
    "Active Requests: " .. debug_info.active_requests,
    "Active Indicators: " .. debug_info.active_indicators,
    "Activated Buffers: " .. debug_info.activated_buffers,
    "Current Provider: " .. (debug_info.current_provider or "none"),
    "Current Model: " .. (debug_info.current_model or "none"),
    "Processing: " .. (debug_info.is_processing and "Yes" or "No"),
    "",
    "Active Request Details:"
  }

  -- Add details for each active request
  for id, request in pairs(state.active_requests) do
    table.insert(lines, "")
    table.insert(lines, "Request ID: " .. id)
    table.insert(lines, "  Status: " .. (request.status or "unknown"))
    table.insert(lines, "  Provider: " .. (request.provider or "unknown"))
    table.insert(lines, "  Model: " .. (request.model or "unknown"))
    table.insert(lines, "  Started: " .. os.date("%Y-%m-%d %H:%M:%S", request.start_time))
    if request.end_time then
      table.insert(lines, "  Ended: " .. os.date("%Y-%m-%d %H:%M:%S", request.end_time))
    end
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Open in a float
  local width = 80
  local height = #lines
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = "nvim-ai Debug",
    title_pos = "center"
  })

  -- Set buffer options
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")

  -- Add keymapping to close the window
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':close<CR>', { noremap = true, silent = true })
end, { desc = "Show nvim-ai debug information" })

vim.api.nvim_create_user_command('NAIOllamaPull', function(opts)
  local model = opts.args

  if not model or model == "" then
    vim.notify("Please specify a model to pull (e.g., :NAIOllamaPull llama3)", vim.log.levels.ERROR)
    return
  end

  -- Create a floating window to show the pull progress
  local buf = vim.api.nvim_create_buf(false, true)
  local width = 80
  local height = 20
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = "Pulling Ollama Model: " .. model,
    title_pos = "center"
  })

  -- Initial content
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "Pulling " .. model .. "...",
    "",
    "This may take a while depending on the model size.",
    "Please wait..."
  })

  -- Run the pull command
  local cmd = { "ollama", "pull", model }
  local job = vim.fn.jobstart(cmd, {
    on_stdout = function(_, data)
      if data then
        vim.schedule(function()
          -- Append the output lines to the buffer
          local line_count = vim.api.nvim_buf_line_count(buf)
          vim.api.nvim_buf_set_lines(buf, line_count, line_count, false, data)

          -- Scroll to the bottom
          if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_set_cursor(win, { line_count + #data, 0 })
          end
        end)
      end
    end,
    on_stderr = function(_, data)
      if data then
        vim.schedule(function()
          -- Append the error lines to the buffer
          local line_count = vim.api.nvim_buf_line_count(buf)
          vim.api.nvim_buf_set_lines(buf, line_count, line_count, false, data)

          -- Scroll to the bottom
          if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_set_cursor(win, { line_count + #data, 0 })
          end
        end)
      end
    end,
    on_exit = function(_, exit_code)
      vim.schedule(function()
        if exit_code == 0 then
          -- Add success message
          local line_count = vim.api.nvim_buf_line_count(buf)
          vim.api.nvim_buf_set_lines(buf, line_count, line_count, false, {
            "",
            "✅ Successfully pulled " .. model,
            "",
            "Press 'q' to close this window"
          })

          vim.notify("Successfully pulled Ollama model: " .. model, vim.log.levels.INFO)
        else
          -- Add error message
          local line_count = vim.api.nvim_buf_line_count(buf)
          vim.api.nvim_buf_set_lines(buf, line_count, line_count, false, {
            "",
            "❌ Failed to pull " .. model,
            "",
            "Press 'q' to close this window"
          })

          vim.notify("Failed to pull Ollama model: " .. model, vim.log.levels.ERROR)
        end

        -- Add keybinding to close the window
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':close<CR>', { noremap = true, silent = true })
        end
      end)
    end,
    stdout_buffered = false,
    stderr_buffered = false
  })

  -- If job failed to start
  if job <= 0 then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "Failed to start Ollama pull job.",
      "Please make sure Ollama is installed and in your PATH.",
      "",
      "Press 'q' to close this window"
    })

    vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':close<CR>', { noremap = true, silent = true })

    vim.notify("Failed to start Ollama pull job", vim.log.levels.ERROR)
  end
end, {
  nargs = "?",
  desc = "Pull a model from Ollama",
  complete = function(ArgLead, CmdLine, CursorPos)
    -- Suggest common models
    local common_models = {
      "llama3", "llama3:8b", "llama3:70b",
      "mistral", "mistral:7b", "mistral:instruct",
      "codellama", "codellama:7b", "codellama:13b", "codellama:34b",
      "phi3", "phi3:mini", "phi3:small", "phi3:medium",
      "gemma", "gemma:2b", "gemma:7b",
      "neural-chat", "wizard-math"
    }

    local filtered = {}
    for _, model in ipairs(common_models) do
      if model:find(ArgLead, 1, true) == 1 then
        table.insert(filtered, model)
      end
    end
    return filtered
  end
})


-- Initialize the buffer detection system
require('nai.buffer').setup_autocmds()
require('nai.buffer').create_activation_command()
