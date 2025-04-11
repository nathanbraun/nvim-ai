local M = {}
local config = require('nai.config')
local constants = require('nai.constants')
local error_utils = require('nai.utils.error')

-- Store activated buffers
M.activated_buffers = {}

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

  -- Skip if already activated
  if M.activated_buffers[bufnr] then
    return
  end

  -- Mark buffer as activated
  M.activated_buffers[bufnr] = true

  if config.options.mappings.enabled then
    require('nai.mappings').apply_to_buffer(bufnr)
  end

  -- Explicitly apply syntax highlighting
  if config.options.active_filetypes.enable_overlay then
    M.apply_syntax_overlay(bufnr)
  end

  if config.options.active_filetypes.enable_folding ~= false then
    require('nai.folding').apply_to_buffer(bufnr)
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
  -- Validate buffer (but don't return since we want to clean up anyway)
  error_utils.validate_buffer(bufnr, "deactivate")

  -- Remove from activated buffers
  M.activated_buffers[bufnr] = nil

  -- Clear highlights only if buffer is valid
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, M.overlay_ns, 0, -1)
  end

  -- Restore original folding
  require('nai.folding').restore_original(bufnr)

  -- Restore original mappings
  require('nai.mappings').restore_original_mappings(bufnr)
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
