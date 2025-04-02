-- plugin/nvim-ai.lua
-- Entry point for the plugin

-- Prevent loading twice
if vim.g.loaded_nvim_ai then
  return
end
vim.g.loaded_nvim_ai = true

-- Create user commands
vim.api.nvim_create_user_command('NAI', function(opts)
  require('nai').complete(opts)
end, { range = true, nargs = '?', desc = 'AI complete text' })

vim.api.nvim_create_user_command('NAIChat', function(opts)
  require('nai').chat(opts)
end, { range = true, nargs = '?', desc = 'AI chat' })

vim.api.nvim_create_user_command('NAIEdit', function(opts)
  require('nai').edit(opts)
end, { range = true, nargs = '?', desc = 'AI edit text' })

vim.api.nvim_create_user_command('NAIProvider', function(opts)
  require('nai').switch_provider(opts.args)
end, { nargs = 1, desc = 'Switch AI provider (openai or openrouter)' })

-- Register the file type (different from aichat)
-- This autocmd associates .naichat files with our custom filetype
vim.api.nvim_create_autocmd({ "BufNewFile", "BufRead" }, {
  pattern = "*.naichat",
  callback = function()
    vim.bo.filetype = "naichat"
  end,
})
