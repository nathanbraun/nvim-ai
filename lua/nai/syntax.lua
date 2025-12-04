local M = {}

-- Helper function to escape pattern characters consistently
local function escape_pattern(str)
  -- Lua pattern special characters that need escaping
  return str:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
end

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

    -- Add background color if specified (and not empty)
    if opts.bg and opts.bg ~= "" then
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

    -- Add terminal background if specified (and not empty)
    if opts.ctermbg and opts.ctermbg ~= "" then
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
    bg = hl_config.placeholder and hl_config.placeholder.bg or nil,
    bold = hl_config.placeholder and hl_config.placeholder.bold or true,
    italic = hl_config.placeholder and hl_config.placeholder.italic or false,
    underline = hl_config.placeholder and hl_config.placeholder.underline or false,
  }))

  -- highlight groups for spinner (more granular)
  vim.cmd(create_highlight_cmd("naichatSpinnerIcon", {
    fg = hl_config.spinner_icon and hl_config.spinner_icon.fg or "#61AFEF",
    bg = hl_config.spinner_icon and hl_config.spinner_icon.bg or nil,
    bold = hl_config.spinner_icon and hl_config.spinner_icon.bold or true,
    italic = hl_config.spinner_icon and hl_config.spinner_icon.italic or false,
  }))

  vim.cmd(create_highlight_cmd("naichatSpinnerText", {
    fg = hl_config.spinner_text and hl_config.spinner_text.fg or "#ABB2BF",
    bg = hl_config.spinner_text and hl_config.spinner_text.bg or nil,
    bold = hl_config.spinner_text and hl_config.spinner_text.bold or false,
    italic = hl_config.spinner_text and hl_config.spinner_text.italic or true,
  }))

  vim.cmd(create_highlight_cmd("naichatSpinnerNumber", {
    fg = hl_config.spinner_number and hl_config.spinner_number.fg or "#D19A66",
    bg = hl_config.spinner_number and hl_config.spinner_number.bg or nil,
    bold = hl_config.spinner_number and hl_config.spinner_number.bold or false,
    italic = hl_config.spinner_number and hl_config.spinner_number.italic or false,
  }))

  vim.cmd(create_highlight_cmd("naichatSpinnerModel", {
    fg = hl_config.spinner_model and hl_config.spinner_model.fg or "#98C379",
    bg = hl_config.spinner_model and hl_config.spinner_model.bg or nil,
    bold = hl_config.spinner_model and hl_config.spinner_model.bold or false,
    italic = hl_config.spinner_model and hl_config.spinner_model.italic or true,
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

  -- Define marker-to-highlight mappings
  -- This makes it easy to add/remove markers without duplicating code
  local marker_highlights = {
    { pattern = "^" .. escape_pattern(markers.USER) .. "$", highlight = "naichatUser" },
    { pattern = "^" .. escape_pattern(markers.ASSISTANT) .. "$", highlight = "naichatAssistant" },
    { pattern = "^" .. escape_pattern(markers.SYSTEM) .. "$", highlight = "naichatSystem" },
    { pattern = "^" .. escape_pattern(markers.CONFIG) .. "$", highlight = "naichatSpecialBlock" },
    { pattern = "^" .. escape_pattern(markers.SNAPSHOT) .. "$", highlight = "naichatSpecialBlock" },
    { pattern = "^" .. escape_pattern(markers.REFERENCE) .. "$", highlight = "naichatSpecialBlock" },
    { pattern = "^" .. escape_pattern(markers.IGNORE) .. "$", highlight = "Comment" },
    { pattern = "^" .. escape_pattern(markers.IGNORE_END) .. "$", highlight = "Comment" },
    { pattern = "^<<< signature", highlight = "naichatSignature" },
    { pattern = "^<<< content", highlight = "naichatContentStart" },
  }

  -- Placeholder patterns to highlight
  local placeholder_patterns = {
    "%%FILE_CONTENTS%%",
    "${FILE_CONTENTS}",
    "$FILE_CONTENTS"
  }

  -- Function to apply highlighting to a single line
  local function highlight_line(line_nr, line)
    -- Check for marker patterns
    for _, marker_def in ipairs(marker_highlights) do
      if line:match(marker_def.pattern) then
        local line_length = #line
        vim.api.nvim_buf_add_highlight(bufnr, ns_id, marker_def.highlight, line_nr, 0, line_length)
        return -- Only one marker per line, so we can return early
      end
    end

    -- Special handling for >>> blocks (with variable names)
    if line:match("^>>> [a-z%-]+") then
      local line_length = #line
      if line:match("error") then
        vim.api.nvim_buf_add_highlight(bufnr, ns_id, "naichatErrorBlock", line_nr, 0, line_length)
      else
        vim.api.nvim_buf_add_highlight(bufnr, ns_id, "naichatSpecialBlock", line_nr, 0, line_length)
      end
      return
    end

    -- Check for placeholders in the line
    for _, pattern in ipairs(placeholder_patterns) do
      local escaped_pattern = escape_pattern(pattern)
      local start_idx, end_idx = line:find(escaped_pattern)
      if start_idx then
        vim.api.nvim_buf_add_highlight(bufnr, ns_id, "naichatPlaceholder", line_nr, start_idx - 1, end_idx)
        -- Note: We don't return here because a line could have multiple placeholders
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
