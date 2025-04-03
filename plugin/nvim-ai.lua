-- plugin/nvim-ai.lua
-- Entry point for the plugin

-- Prevent loading twice
if vim.g.loaded_nvim_ai then
  return
end
vim.g.loaded_nvim_ai = true

-- Create user commands (simplified)
vim.api.nvim_create_user_command('NAIChat', function(opts)
  require('nai').chat(opts)
end, { range = true, nargs = '?', desc = 'AI chat' })

vim.api.nvim_create_user_command('NAIProvider', function(opts)
  require('nai').switch_provider(opts.args)
end, { nargs = 1, desc = 'Switch AI provider (openai or openrouter)' })

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

-- Register the file type
vim.api.nvim_create_autocmd({ "BufNewFile", "BufRead" }, {
  pattern = "*.naichat",
  callback = function()
    vim.bo.filetype = "naichat"
  end,
})
