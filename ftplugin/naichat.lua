-- ftplugin/naichat.lua
-- Settings for naichat filetype

-- Set basic buffer options
vim.bo.swapfile = false

-- Enable concealing for the buffer
vim.wo.conceallevel = 2
vim.wo.concealcursor = 'nc'

-- Add additional mappings for convenience
vim.api.nvim_buf_set_keymap(0, 'n', '<Leader>r', ':NAIChat<CR>',
  { noremap = true, silent = true, desc = 'Continue chat' })

vim.api.nvim_buf_set_keymap(0, 'n', '<Leader>n', ':NAINew<CR>',
  { noremap = true, silent = true, desc = 'Create new empty chat' })

-- You can add more filetype-specific settings here
