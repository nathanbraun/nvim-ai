local M = {}
local config = require('nai.config')

-- Store activated buffers
M.activated_buffers = {}

-- Check if a buffer should be activated based on filename
function M.should_activate_by_pattern(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local filename = vim.api.nvim_buf_get_name(bufnr)

  -- Check against configured patterns
  for _, pattern in ipairs(config.options.active_filetypes.patterns) do
    if vim.fn.glob(pattern) ~= "" and vim.fn.match(filename, vim.fn.glob2regpat(pattern)) >= 0 then
      return true
    end
  end

  return false
end

-- Check if buffer contains chat markers
function M.detect_chat_markers(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Bail out if buffer is not valid
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  -- Get buffer lines
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local markers = config.options.active_filetypes.block_markers

  -- Check for presence of any markers
  for _, line in ipairs(lines) do
    for _, marker in pairs(markers) do
      if line:match("^" .. vim.pesc(marker) .. "$") then
        return true
      end
    end
  end

  return false
end

-- Check if a buffer should be activated
function M.should_activate_by_pattern(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local filename = vim.api.nvim_buf_get_name(bufnr)

  -- Check against configured patterns
  for _, pattern in ipairs(config.options.active_filetypes.patterns) do
    -- Use simpler pattern matching that doesn't depend on glob
    if vim.fn.match(filename, pattern:gsub("%*", ".*")) >= 0 then
      return true
    end
  end

  return false
end

-- Activate the plugin for a buffer
function M.activate_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Debug info
  local filename = vim.api.nvim_buf_get_name(bufnr)

  -- Skip if already activated
  if M.activated_buffers[bufnr] then
    return
  end

  -- Mark buffer as activated
  M.activated_buffers[bufnr] = true

  -- Register buffer-local commands
  vim.api.nvim_buf_create_user_command(bufnr, 'NAIChat', function(opts)
    require('nai').chat(opts)
  end, { range = true, nargs = '?', desc = 'AI chat in current buffer' })

  vim.api.nvim_buf_create_user_command(bufnr, 'NAINewMessage', function()
    local parser = require('nai.parser')
    local user_template = parser.format_user_message("")
    local user_lines = vim.split(user_template, "\n")

    -- Add at the end of the buffer
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, user_lines)

    -- Position cursor on the 3rd line of new user message
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    vim.api.nvim_win_set_cursor(0, { line_count, 0 })
  end, { desc = 'Add a new user message' })

  -- Add key mappings (buffer-local)
  vim.api.nvim_buf_set_keymap(bufnr, 'n', '<Leader>c', ':NAIChat<CR>',
    { noremap = true, silent = true, desc = 'Continue chat' })

  vim.api.nvim_buf_set_keymap(bufnr, 'n', '<Leader>apu', ':NAINewMessage<CR>',
    { noremap = true, silent = true, desc = 'Add new user message' })

  vim.api.nvim_buf_set_keymap(bufnr, 'n', '<Leader>aps', ':NAIScrape<CR>',
    { noremap = true, silent = true, desc = 'Add new scrape message' })

  vim.api.nvim_buf_set_keymap(bufnr, 'n', '<Leader>apw', ':NAIWeb<CR>',
    { noremap = true, silent = true, desc = 'Add new web message' })

  vim.api.nvim_buf_set_keymap(bufnr, 'n', '<Leader>apy', ':NAIYoutube<CR>',
    { noremap = true, silent = true, desc = 'Add new youtube message' })

  vim.api.nvim_buf_set_keymap(bufnr, 'n', '<Leader>am', ':NAIModel<CR>',
    { noremap = true, silent = true, desc = 'Add new user message' })

  -- Explicitly apply syntax highlighting
  if config.options.active_filetypes.enable_overlay then
    M.apply_syntax_overlay(bufnr)
  end

  -- Add cleanup on buffer unload
  local augroup = vim.api.nvim_create_augroup('NaiBufferCleanup' .. bufnr, { clear = true })
  vim.api.nvim_create_autocmd("BufUnload", {
    group = augroup,
    buffer = bufnr,
    callback = function()
      M.deactivate_buffer(bufnr)
    end
  })

  -- Schedule another application of syntax highlighting
  -- This helps with race conditions where filetype is set after activation
  vim.defer_fn(function()
    if vim.api.nvim_buf_is_valid(bufnr) and M.activated_buffers[bufnr] then
      M.apply_syntax_overlay(bufnr)
    end
  end, 100)
end

-- Create syntax overlay namespace if it doesn't exist
M.overlay_ns = vim.api.nvim_create_namespace('nai_overlay')

-- Apply syntax highlighting overlay to a buffer
function M.apply_syntax_overlay(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Clear any existing overlay
  vim.api.nvim_buf_clear_namespace(bufnr, M.overlay_ns, 0, -1)

  -- Apply new syntax highlighting using our syntax module
  local syntax = require('nai.syntax')
  local ns_id = syntax.apply_to_buffer(bufnr)

  -- Store the namespace ID for future reference
  M.overlay_ns = ns_id
end

-- Deactivate a buffer
function M.deactivate_buffer(bufnr)
  -- Remove from activated buffers
  M.activated_buffers[bufnr] = nil

  -- Clear highlights
  vim.api.nvim_buf_clear_namespace(bufnr, M.overlay_ns, 0, -1)
end

-- Set up autocmd to check files when they're loaded
function M.setup_autocmds()
  local augroup = vim.api.nvim_create_augroup('NaiBufferDetection', { clear = true })

  -- Check files when they're loaded
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
    group = augroup,
    pattern = "*",
    callback = function(args)
      if M.should_activate(args.buf) then
        M.activate_buffer(args.buf)
      end
    end
  })

  -- Also apply highlighting when opening files that match patterns
  vim.api.nvim_create_autocmd("FileType", {
    group = augroup,
    pattern = { "markdown", "text", "wiki" },
    callback = function(args)
      if M.should_activate(args.buf) then
        M.activate_buffer(args.buf)
      end
    end
  })
end

-- Command to manually activate current buffer
function M.create_activation_command()
  vim.api.nvim_create_user_command('NAIActivate', function()
    local bufnr = vim.api.nvim_get_current_buf()
    local filename = vim.api.nvim_buf_get_name(bufnr)

    -- Make sure the buffer isn't already activated
    if M.activated_buffers[bufnr] then
      return
    end

    -- Force activation regardless of checks
    M.activated_buffers[bufnr] = true
    M.apply_syntax_overlay(bufnr)

    -- Set up buffer-local commands
    vim.api.nvim_buf_create_user_command(bufnr, 'NAIChat', function(opts)
      require('nai').chat(opts)
    end, { range = true, nargs = '?', desc = 'AI chat in current buffer' })

    -- vim.api.nvim_buf_set_keymap(bufnr, 'n', '<Leader>r', ':NAIChat<CR>',
    --   { noremap = true, silent = true, desc = 'Continue chat' })
  end, { desc = 'Activate NAI Chat for current buffer' })
end

-- Add this function
function M.should_activate(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Check if the buffer should be activated based on file pattern
  if M.should_activate_by_pattern(bufnr) then
    return true
  end

  -- Check if the buffer contains chat markers
  if config.options.active_filetypes.autodetect and M.detect_chat_markers(bufnr) then
    return true
  end

  return false
end

return M
