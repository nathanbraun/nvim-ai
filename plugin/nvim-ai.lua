-- plugin/nvim-ai.lua
-- Entry point for the plugin

-- Prevent loading twice
if vim.g.loaded_nvim_ai then
  return
end
vim.g.loaded_nvim_ai = true

-- Add profiling commands
vim.api.nvim_create_user_command('NAIProfileToggle', function()
  require('nai.utils.profiler').toggle()
end, { desc = 'Toggle NAI performance profiling' })

vim.api.nvim_create_user_command('NAIProfileSummary', function()
  require('nai.utils.profiler').print_summary()
end, { desc = 'Show NAI performance profiling summary' })

-- Create user commands

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

vim.api.nvim_create_user_command('NAIInclude', function(opts)
  local parser = require('nai.parser')
  local include_block = parser.format_include_block(opts.args or "")
  local lines = vim.split(include_block, "\n")

  -- Insert at cursor position
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1

  vim.api.nvim_buf_set_lines(0, row, row, false, lines)

  -- Position cursor at end of inserted block
  vim.api.nvim_win_set_cursor(0, { row + #lines, 0 })
end, {
  nargs = "?",
  desc = "Insert an include block at cursor position"
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

-- Initialize the buffer detection system
require('nai.buffer').setup_autocmds()
require('nai.buffer').create_activation_command()
