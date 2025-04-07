-- lua/nai/syntax.lua
local M = {}

-- Define highlight groups if they don't already exist
function M.define_highlight_groups()
  -- User message highlighting
  vim.cmd([[
    highlight default naichatUser guifg=#88AAFF ctermfg=111 gui=bold cterm=bold
    highlight default naichatAssistant guifg=#AAFFAA ctermfg=157 gui=bold cterm=bold
    highlight default naichatSystem guifg=#FFAA88 ctermfg=216 gui=bold cterm=bold
    highlight default naichatSpecialBlock guifg=#AAAAFF ctermfg=147 gui=bold cterm=bold
    highlight default naichatErrorBlock guifg=#FF8888 ctermfg=210 gui=bold cterm=bold
    highlight default naichatContentStart guifg=#AAAAAA ctermfg=145 gui=italic cterm=italic
  ]])
end

-- Apply our syntax highlighting to a buffer while preserving existing syntax
function M.apply_to_buffer(bufnr)
  local config = require('nai.config')

  -- Get the markers from config
  local markers = config.options.active_filetypes.block_markers

  -- Ensure highlight groups exist
  M.define_highlight_groups()

  -- Create a unique namespace for our overlay
  local ns_id = vim.api.nvim_create_namespace('nai_syntax_overlay')

  -- Function to apply highlighting to a single line
  local function highlight_line(line_nr, line)
    -- User marker
    if line:match("^" .. vim.pesc(markers.user) .. "$") then
      -- Get the full line length
      local line_length = #line
      vim.api.nvim_buf_add_highlight(bufnr, ns_id, "naichatUser", line_nr, 0, line_length)

      -- Assistant marker
    elseif line:match("^" .. vim.pesc(markers.assistant) .. "$") then
      local line_length = #line
      vim.api.nvim_buf_add_highlight(bufnr, ns_id, "naichatAssistant", line_nr, 0, line_length)

      -- System marker
    elseif line:match("^" .. vim.pesc(markers.system) .. "$") then
      local line_length = #line
      vim.api.nvim_buf_add_highlight(bufnr, ns_id, "naichatSystem", line_nr, 0, line_length)

      -- Special blocks
    elseif line:match("^>>> [a-z%-]+") then
      local line_length = #line
      if line:match("error") then
        vim.api.nvim_buf_add_highlight(bufnr, ns_id, "naichatErrorBlock", line_nr, 0, line_length)
      else
        vim.api.nvim_buf_add_highlight(bufnr, ns_id, "naichatSpecialBlock", line_nr, 0, line_length)
      end

      -- Content start
    elseif line:match("^<<< content") then
      local line_length = #line
      vim.api.nvim_buf_add_highlight(bufnr, ns_id, "naichatContentStart", line_nr, 0, line_length)
    end
  end

  -- Apply highlighting to the entire buffer
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i, line in ipairs(lines) do
    highlight_line(i - 1, line) -- 0-based indexing for api functions
  end

  -- Debounce function for efficiency
  local debounce_timer = nil
  local function debounced_highlight(delay)
    if debounce_timer then
      debounce_timer:stop()
      debounce_timer:close()
    end

    debounce_timer = vim.loop.new_timer()
    debounce_timer:start(delay or 100, 0, vim.schedule_wrap(function()
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end

      -- Clear existing highlights
      vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

      -- Reapply highlights
      local updated_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      for i, line in ipairs(updated_lines) do
        highlight_line(i - 1, line)
      end
    end))
  end

  -- Setup autocmd to keep highlighting up-to-date, with debouncing
  local augroup = vim.api.nvim_create_augroup('NaiSyntaxOverlay' .. bufnr, { clear = true })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = augroup,
    buffer = bufnr,
    callback = function()
      debounced_highlight(100) -- 100ms debounce
    end
  })

  return ns_id
end

return M
