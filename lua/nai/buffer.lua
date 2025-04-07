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
function M.should_activate(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Always activate for .naichat files (backward compatibility)
  local filename = vim.api.nvim_buf_get_name(bufnr)
  if filename:match("%.naichat$") then
    return true
  end

  -- Check pattern match
  if M.should_activate_by_pattern(bufnr) then
    return true
  end

  -- If autodetect is enabled, scan buffer content
  if config.options.active_filetypes.autodetect then
    return M.detect_chat_markers(bufnr)
  end

  return false
end

-- Activate the plugin for a buffer
function M.activate_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

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
  vim.api.nvim_buf_set_keymap(bufnr, 'n', '<Leader>r', ':NAIChat<CR>',
    { noremap = true, silent = true, desc = 'Continue chat' })

  vim.api.nvim_buf_set_keymap(bufnr, 'n', '<Leader>m', ':NAINewMessage<CR>',
    { noremap = true, silent = true, desc = 'Add new user message' })

  -- Add cleanup on buffer unload
  vim.api.nvim_create_autocmd("BufUnload", {
    group = augroup,
    buffer = bufnr,
    callback = function()
      M.deactivate_buffer(bufnr)
    end
  })

  vim.notify("NAI Chat activated for this buffer", vim.log.levels.INFO)
end

-- Create syntax overlay namespace if it doesn't exist
M.overlay_ns = vim.api.nvim_create_namespace('nai_overlay')

-- Apply syntax highlighting overlay to a buffer
function M.apply_syntax_overlay(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Clear existing highlights
  vim.api.nvim_buf_clear_namespace(bufnr, M.overlay_ns, 0, -1)

  -- Get buffer lines
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local markers = config.options.active_filetypes.block_markers

  -- Apply highlights to each line
  for i, line in ipairs(lines) do
    -- User marker
    if line:match("^" .. vim.pesc(markers.user) .. "$") then
      vim.api.nvim_buf_add_highlight(bufnr, M.overlay_ns, "naichatUser", i - 1, 0, -1)

      -- Assistant marker
    elseif line:match("^" .. vim.pesc(markers.assistant) .. "$") then
      vim.api.nvim_buf_add_highlight(bufnr, M.overlay_ns, "naichatAssistant", i - 1, 0, -1)

      -- System marker
    elseif line:match("^" .. vim.pesc(markers.system) .. "$") then
      vim.api.nvim_buf_add_highlight(bufnr, M.overlay_ns, "naichatSystem", i - 1, 0, -1)

      -- Special blocks
    elseif line:match("^>>> [a-z%-]+") then
      if line:match("error") then
        vim.api.nvim_buf_add_highlight(bufnr, M.overlay_ns, "naichatErrorBlock", i - 1, 0, -1)
      else
        vim.api.nvim_buf_add_highlight(bufnr, M.overlay_ns, "naichatSpecialBlock", i - 1, 0, -1)
      end

      -- Content start
    elseif line:match("^<<< content") then
      vim.api.nvim_buf_add_highlight(bufnr, M.overlay_ns, "naichatContentStart", i - 1, 0, -1)
    end
  end
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
end

-- Command to manually activate current buffer
function M.create_activation_command()
  vim.api.nvim_create_user_command('NAIActivate', function()
    M.activate_buffer()
  end, { desc = 'Activate NAI Chat for current buffer' })
end

return M
