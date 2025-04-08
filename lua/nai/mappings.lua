-- lua/nai/mappings.lua
local M = {}

-- Default mappings
M.defaults = {
  -- Chat commands
  chat = {
    continue = "<Leader>c", -- Continue chat
    new = "<Leader>an",     -- New chat
    cancel = "<Leader>ax",  -- Cancel request
  },

  -- Insert commands
  insert = {
    user_message = "<Leader>aiu", -- Add user message
    scrape = "<Leader>aid",       -- Add scrape block
    web = "<Leader>aiw",          -- Add web block
    youtube = "<Leader>aiy",      -- Add YouTube block
    include = "<Leader>aii",      -- Add include block
    snapshot = "<Leader>ais",     -- Add snapshot block
  },

  -- Settings
  settings = {
    select_model = "<Leader>asm",    -- Select model
    toggle_provider = "<Leader>asp", -- Toggle provider
  }
}

-- Store active mappings (will be populated from config)
M.active = vim.deepcopy(M.defaults)

-- Apply mappings to a buffer
function M.apply_to_buffer(bufnr)
  -- Chat commands
  vim.api.nvim_buf_set_keymap(bufnr, 'n', M.active.chat.continue, ':NAIChat<CR>',
    { noremap = true, silent = true, desc = 'Continue chat' })
  vim.api.nvim_buf_set_keymap(bufnr, 'n', M.active.chat.new, ':NAINew<CR>',
    { noremap = true, silent = true, desc = 'New chat' })
  vim.api.nvim_buf_set_keymap(bufnr, 'n', M.active.chat.cancel, ':NAICancel<CR>',
    { noremap = true, silent = true, desc = 'Cancel request' })

  -- Insert commands
  vim.api.nvim_buf_set_keymap(bufnr, 'n', M.active.insert.user_message, ':NAIUser<CR>',
    { noremap = true, silent = true, desc = 'Add new user message' })
  vim.api.nvim_buf_set_keymap(bufnr, 'n', M.active.insert.scrape, ':NAIScrape<CR>',
    { noremap = true, silent = true, desc = 'Add scrape block' })
  vim.api.nvim_buf_set_keymap(bufnr, 'n', M.active.insert.web, ':NAIWeb<CR>',
    { noremap = true, silent = true, desc = 'Add web block' })
  vim.api.nvim_buf_set_keymap(bufnr, 'n', M.active.insert.youtube, ':NAIYoutube<CR>',
    { noremap = true, silent = true, desc = 'Add YouTube block' })
  vim.api.nvim_buf_set_keymap(bufnr, 'n', M.active.insert.include, ':NAIInclude<CR>',
    { noremap = true, silent = true, desc = 'Add include block' })
  vim.api.nvim_buf_set_keymap(bufnr, 'n', M.active.insert.snapshot, ':NAISnapshot<CR>',
    { noremap = true, silent = true, desc = 'Add snapshot block' })

  -- Settings
  vim.api.nvim_buf_set_keymap(bufnr, 'n', M.active.settings.select_model, ':NAIModel<CR>',
    { noremap = true, silent = true, desc = 'Select model' })

  -- Try to set up which-key if available
  M.setup_which_key()
end

-- Setup which-key integration if available
function M.setup_which_key()
  local ok, wk = pcall(require, "which-key")
  if not ok then
    return
  end

  wk.register({
    ["<Leader>a"] = { name = "+AI" },
    ["<Leader>ac"] = { name = "+Chat" },
    ["<Leader>ai"] = { name = "+Insert" },
    ["<Leader>as"] = { name = "+Settings" },
  })
end

-- Setup function to merge user config
function M.setup(opts)
  if opts and opts.mappings then
    -- Merge user mappings with defaults
    for category, mappings in pairs(opts.mappings) do
      if M.active[category] then
        for action, mapping in pairs(mappings) do
          if M.active[category][action] then
            M.active[category][action] = mapping
          end
        end
      end
    end
  end
end

return M
