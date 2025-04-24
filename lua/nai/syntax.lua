-- lua/nai/syntax.lua
local M = {}

-- Define highlight groups if they don't already exist
function M.define_highlight_groups()
  local config = require('nai.config')
  local hl_config = config.options.highlights

  -- Helper function to create highlight command
  local function create_highlight_cmd(name, opts)
    local cmd = "highlight default " .. name

    -- Add foreground color if specified
    if opts.fg then
      cmd = cmd .. " guifg=" .. opts.fg
    end

    -- Add background color if specified
    if opts.bg then
      cmd = cmd .. " guibg=" .. opts.bg
    end

    -- Add GUI options
    local gui_opts = {}
    if opts.bold then table.insert(gui_opts, "bold") end
    if opts.italic then table.insert(gui_opts, "italic") end
    if opts.underline then table.insert(gui_opts, "underline") end

    if #gui_opts > 0 then
      cmd = cmd .. " gui=" .. table.concat(gui_opts, ",")
    end

    -- Add terminal colors if specified
    if opts.ctermfg then
      cmd = cmd .. " ctermfg=" .. opts.ctermfg
    end

    if opts.ctermbg then
      cmd = cmd .. " ctermbg=" .. opts.ctermbg
    end

    -- Add terminal options
    local cterm_opts = {}
    if opts.bold then table.insert(cterm_opts, "bold") end
    if opts.italic then table.insert(cterm_opts, "italic") end
    if opts.underline then table.insert(cterm_opts, "underline") end

    if #cterm_opts > 0 then
      cmd = cmd .. " cterm=" .. table.concat(cterm_opts, ",")
    end

    return cmd
  end

  -- Define highlights using config
  vim.cmd(create_highlight_cmd("naichatUser", hl_config.user))
  vim.cmd(create_highlight_cmd("naichatAssistant", hl_config.assistant))
  vim.cmd(create_highlight_cmd("naichatSystem", hl_config.system))
  vim.cmd(create_highlight_cmd("naichatSpecialBlock", hl_config.special_block))
  vim.cmd(create_highlight_cmd("naichatErrorBlock", hl_config.error_block))
  vim.cmd(create_highlight_cmd("naichatContentStart", hl_config.content_start))
  vim.cmd(create_highlight_cmd("naichatSignature", hl_config.signature or { fg = "#777777", italic = true }))

  -- highlight group for placeholders
  vim.cmd(create_highlight_cmd("naichatPlaceholder", {
    fg = hl_config.placeholder and hl_config.placeholder.fg or "#FFCC66",
    bg = hl_config.placeholder and hl_config.placeholder.bg or "",
    bold = hl_config.placeholder and hl_config.placeholder.bold or true,
    italic = hl_config.placeholder and hl_config.placeholder.italic or false,
    underline = hl_config.placeholder and hl_config.placeholder.underline or false,
  }))
end

-- Apply our syntax highlighting to a buffer while preserving existing syntax
function M.apply_to_buffer(bufnr)
  local config = require('nai.config')
  local constants = require('nai.constants')

  -- Get the markers from config
  local markers = constants.MARKERS

  -- Ensure highlight groups exist
  M.define_highlight_groups()

  -- Create a unique namespace for our overlay
  local ns_id = vim.api.nvim_create_namespace('nai_syntax_overlay')

  -- Function to apply highlighting to a single line
  local function highlight_line(line_nr, line)
    -- User marker
    if line:match("^" .. vim.pesc(markers.USER) .. "$") then
      -- Get the full line length
      local line_length = #line
      vim.api.nvim_buf_add_highlight(bufnr, ns_id, "naichatUser", line_nr, 0, line_length)

      -- Assistant marker
    elseif line:match("^" .. vim.pesc(markers.ASSISTANT) .. "$") then
      local line_length = #line
      vim.api.nvim_buf_add_highlight(bufnr, ns_id, "naichatAssistant", line_nr, 0, line_length)

      -- System marker
    elseif line:match("^" .. vim.pesc(markers.SYSTEM) .. "$") then
      local line_length = #line
      vim.api.nvim_buf_add_highlight(bufnr, ns_id, "naichatSystem", line_nr, 0, line_length)
    elseif line:match("^" .. vim.pesc(markers.CONFIG) .. "$") then
      local line_length = #line
      vim.api.nvim_buf_add_highlight(bufnr, ns_id, "naichatSpecialBlock", line_nr, 0, line_length)

      -- Signature line
    elseif line:match("^<<< signature") then
      local line_length = #line
      vim.api.nvim_buf_add_highlight(bufnr, ns_id, "naichatSignature", line_nr, 0, line_length)

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
    -- Add placeholder highlighting
    local placeholder_patterns = {
      "%%FILE_CONTENTS%%",
      "${FILE_CONTENTS}",
      "$FILE_CONTENTS"
    }

    for _, pattern in ipairs(placeholder_patterns) do
      local start_idx, end_idx = line:find(vim.pesc(pattern))
      if start_idx then
        vim.api.nvim_buf_add_highlight(bufnr, ns_id, "naichatPlaceholder", line_nr, start_idx - 1, end_idx)
      end
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
