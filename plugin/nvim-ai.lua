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

-- For backwards compatibility (will show notices directing to NAIChat)
vim.api.nvim_create_user_command('NAI', function(opts)
  require('nai').complete(opts)
end, { range = true, nargs = '?', desc = 'AI complete text (deprecated)' })

vim.api.nvim_create_user_command('NAIEdit', function(opts)
  require('nai').edit(opts)
end, { range = true, nargs = '?', desc = 'AI edit text (deprecated)' })

-- Register the file type
vim.api.nvim_create_autocmd({ "BufNewFile", "BufRead" }, {
  pattern = "*.naichat",
  callback = function()
    vim.bo.filetype = "naichat"
  end,
})
