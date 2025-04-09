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
  for bufnr, _ in pairs(require('nai.buffer').activated_buffers) do
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
    max_tokens = provider_config.max_tokens
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

-- Initialize the buffer detection system
require('nai.buffer').setup_autocmds()
require('nai.buffer').create_activation_command()
