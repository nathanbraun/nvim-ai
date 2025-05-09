local M = {}
local config = require('nai.config')
local constants = require('nai.constants')
local error_utils = require('nai.utils.error')

-- Check if buffer contains chat markers
function M.detect_chat_markers(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Bail out if buffer is not valid
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  -- Get buffer lines
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local markers = constants.MARKERS

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

  -- Validate buffer
  if not error_utils.validate_buffer(bufnr, "activate") then
    return
  end

  -- Debug info
  local filename = vim.api.nvim_buf_get_name(bufnr)

  local state = require('nai.state')
  local events = require('nai.events')

  -- Skip if already activated
  if state.is_buffer_activated(bufnr) then
    return
  end

  -- Mark buffer as activated
  state.activate_buffer(bufnr)

  -- Emit event
  events.emit('buffer:activate', bufnr, filename)

  if config.options.mappings.enabled then
    require('nai.mappings').apply_to_buffer(bufnr)
  end

  -- Explicitly apply syntax highlighting
  if config.options.active_filetypes.enable_overlay then
    M.apply_syntax_overlay(bufnr)
  end

  -- Always apply folding unless explicitly disabled
  if config.options.active_filetypes.enable_folding ~= false then
    require('nai.folding').apply_to_buffer(bufnr)

    -- Force folding method to take effect immediately for all windows showing this buffer
    for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
      vim.wo[winid].foldmethod = "expr"
      vim.wo[winid].foldexpr = "v:lua.require('nai.folding').get_fold_level(v:lnum)"
      vim.wo[winid].foldenable = true
      vim.wo[winid].foldlevel = 99 -- Start with all folds open

      -- Refresh folding
      vim.cmd("normal! zx")
    end
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
  local state = require('nai.state') -- Add this line
  vim.defer_fn(function()
    if vim.api.nvim_buf_is_valid(bufnr) and state.is_buffer_activated(bufnr) then
      M.apply_syntax_overlay(bufnr)

      -- Refresh folding for all windows showing this buffer
      if config.options.active_filetypes.enable_folding ~= false then
        for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
          vim.wo[winid].foldmethod = "expr"
          vim.wo[winid].foldexpr = "v:lua.require('nai.folding').get_fold_level(v:lnum)"

          -- Force folding to update
          pcall(vim.cmd, "normal! zx")
        end
      end
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
  -- Skip if buffer is not valid
  if not vim.api.nvim_buf_is_valid(bufnr) then
    local state = require('nai.state')
    state.deactivate_buffer(bufnr)
    return
  end

  local state = require('nai.state')
  local events = require('nai.events')

  -- Remove from activated buffers
  state.deactivate_buffer(bufnr)

  -- Emit event
  events.emit('buffer:deactivate', bufnr)

  -- Clear highlights
  pcall(vim.api.nvim_buf_clear_namespace, bufnr, M.overlay_ns, 0, -1)

  -- Restore original folding
  pcall(function() require('nai.folding').restore_original(bufnr) end)

  -- Restore original mappings
  pcall(function() require('nai.mappings').restore_original_mappings(bufnr) end)
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
    local state = require('nai.state')

    -- Make sure the buffer isn't already activated
    if state.is_buffer_activated(bufnr) then
      return
    end

    -- Force activation regardless of checks
    state.activate_buffer(bufnr)
    M.apply_syntax_overlay(bufnr)

    -- Set up buffer-local commands
    vim.api.nvim_buf_create_user_command(bufnr, 'NAIChat', function(opts)
      require('nai').chat(opts)
    end, { range = true, nargs = '?', desc = 'AI chat in current buffer' })

    -- vim.api.nvim_buf_set_keymap(bufnr, 'n', '<Leader>r', ':NAIChat<CR>',
    --   { noremap = true, silent = true, desc = 'Continue chat' })
  end, { desc = 'Activate NAI Chat for current buffer' })
end

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
