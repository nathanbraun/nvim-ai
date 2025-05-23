local config = require('nai.config') -- Add this line to properly import the config module

-- lua/nai/mappings.lua
local M = {}

-- Default mappings
M.defaults = {
  -- Chat commands
  chat = {
    continue = "<Leader>c",       -- Continue chat
    verified_chat = "<Leader>av", -- Continue chat
    new = "<Leader>ai",           -- New chat
    cancel = "<Leader>ax",        -- Cancel request
  },

  expand = {
    blocks = "<Leader>ae", -- Expand blocks
  },

  verify = {
    reverify = "<Leader>arv", -- Re-verify blocks
  },

  -- Insert commands
  insert = {
    user_message = "<Leader>anu", -- Add user message
    scrape = "<Leader>and",       -- Add scrape block
    web = "<Leader>anw",          -- Add web block
    youtube = "<Leader>any",      -- Add YouTube block
    reference = "<Leader>anr",    -- Add reference block
    snapshot = "<Leader>ans",     -- Add snapshot block
    tree = "<Leader>ant",         -- Add tree block
    crawl = "<Leader>anc",        -- Add snapshot block
  },

  -- Settings
  settings = {
    select_model = "<Leader>am",    -- Select model
    toggle_provider = "<Leader>ap", -- Toggle provider
  },

  -- Files (add this new section)
  files = {
    browse = "<Leader>ao", -- Browse AI chat files
  }
}

-- Store active mappings (will be populated from config)
M.active = vim.deepcopy(M.defaults)

-- Apply mappings to a buffer
function M.apply_to_buffer(bufnr)
  -- Chat commands
  vim.api.nvim_buf_set_keymap(bufnr, 'n', M.active.chat.continue, ':NAIChat<CR>',
    { noremap = true, silent = true, desc = 'Continue chat' })
  vim.api.nvim_buf_set_keymap(bufnr, 'n', M.active.chat.verified_chat, ':NAISignedChat<CR>',
    { noremap = true, silent = true, desc = 'Continue and verify chat' })
  vim.api.nvim_buf_set_keymap(bufnr, 'n', M.active.chat.new, ':NAINew<CR>',
    { noremap = true, silent = true, desc = 'New chat' })
  vim.api.nvim_buf_set_keymap(bufnr, 'n', M.active.chat.cancel, ':NAICancel<CR>',
    { noremap = true, silent = true, desc = 'Cancel request' })

  -- expand commands
  vim.api.nvim_buf_set_keymap(bufnr, 'n', M.active.expand.blocks, ':NAIExpand<CR>',
    { noremap = true, silent = true, desc = 'Expand special blocks' })

  -- re-verify commands
  vim.api.nvim_buf_set_keymap(bufnr, 'n', M.active.verify.reverify, ':NAIVerify<CR>',
    { noremap = true, silent = true, desc = 'Expand special blocks' })

  -- Insert commands
  vim.api.nvim_buf_set_keymap(bufnr, 'n', M.active.insert.user_message, ':NAIUser<CR>',
    { noremap = true, silent = true, desc = 'Add new user message' })
  vim.api.nvim_buf_set_keymap(bufnr, 'n', M.active.insert.scrape, ':NAIScrape<CR>',
    { noremap = true, silent = true, desc = 'Add scrape block' })
  vim.api.nvim_buf_set_keymap(bufnr, 'n', M.active.insert.tree, ':NAITree<CR>',
    { noremap = true, silent = true, desc = 'Add directory tree block' })
  vim.api.nvim_buf_set_keymap(bufnr, 'n', M.active.insert.web, ':NAIWeb<CR>',
    { noremap = true, silent = true, desc = 'Add web block' })
  vim.api.nvim_buf_set_keymap(bufnr, 'n', M.active.insert.youtube, ':NAIYoutube<CR>',
    { noremap = true, silent = true, desc = 'Add YouTube block' })
  vim.api.nvim_buf_set_keymap(bufnr, 'n', M.active.insert.reference, ':NAIReference<CR>',
    { noremap = true, silent = true, desc = 'Add reference block' })
  vim.api.nvim_buf_set_keymap(bufnr, 'n', M.active.insert.snapshot, ':NAISnapshot<CR>',
    { noremap = true, silent = true, desc = 'Add snapshot block' })

  vim.api.nvim_buf_set_keymap(bufnr, 'n', M.active.insert.crawl, ':NAICrawl<CR>',
    { noremap = true, silent = true, desc = 'Add crawl block' })

  -- Settings
  vim.api.nvim_buf_set_keymap(bufnr, 'n', M.active.settings.select_model, ':NAIModel<CR>',
    { noremap = true, silent = true, desc = 'Select model' })

  vim.api.nvim_buf_set_keymap(bufnr, 'n', M.active.settings.toggle_provider, ':NAIProvider<CR>',
    { noremap = true, silent = true, desc = 'Select provider' })

  -- Add the browse mapping
  vim.api.nvim_buf_set_keymap(bufnr, 'n', M.active.files.browse, ':NAIBrowse<CR>',
    { noremap = true, silent = true, desc = 'Browse AI chat files' })

  -- Add Ctrl+C mapping if enabled
  if config.options.mappings.intercept_ctrl_c then
    -- Save the original mapping for restoration
    local original_ctrl_c = vim.fn.maparg("<C-c>", "n", false, true)
    if original_ctrl_c and original_ctrl_c.rhs then
      -- Store the original mapping in a buffer variable
      vim.api.nvim_buf_set_var(bufnr, "nai_original_ctrl_c", original_ctrl_c)
    end

    -- Map Ctrl+C to cancel in normal mode
    vim.api.nvim_buf_set_keymap(bufnr, 'n', '<C-c>', ':NAICancel<CR>',
      { noremap = true, silent = true, desc = 'Cancel AI request' })

    -- For insert mode, we need to be more careful - only intercept if an AI request is active
    -- This function will check if there's an active request
    vim.api.nvim_buf_set_keymap(bufnr, 'i', '<C-c>', [[<Cmd>lua require('nai.mappings').handle_ctrl_c()<CR>]],
      { noremap = true, silent = true, desc = 'Cancel AI request or exit insert mode' })
  end
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

-- Add a new function to handle Ctrl+C in insert mode
function M.handle_ctrl_c()
  local nai = require('nai')

  -- If there's an active request, cancel it
  if nai.active_request then
    nai.cancel()
    return
  end

  -- Otherwise, behave like normal Ctrl+C (exit insert mode)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), 'n', true)
end

-- Add a function to restore original mappings
function M.restore_original_mappings(bufnr)
  -- Skip if buffer is not valid
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Check if we have stored an original Ctrl+C mapping
  local success, original_ctrl_c = pcall(vim.api.nvim_buf_get_var, bufnr, "nai_original_ctrl_c")

  if success and original_ctrl_c then
    -- Restore the original mapping
    pcall(vim.api.nvim_buf_set_keymap, bufnr,
      original_ctrl_c.mode,
      original_ctrl_c.lhs,
      original_ctrl_c.rhs,
      {
        noremap = original_ctrl_c.noremap == 1,
        silent = original_ctrl_c.silent == 1,
        expr = original_ctrl_c.expr == 1,
        nowait = original_ctrl_c.nowait == 1
      })
  else
    -- If no original mapping, just clear our mapping if it exists
    -- Use pcall to avoid errors if the mapping doesn't exist
    pcall(vim.api.nvim_buf_del_keymap, bufnr, 'n', '<C-c>')
    pcall(vim.api.nvim_buf_del_keymap, bufnr, 'i', '<C-c>')
  end
end

return M
