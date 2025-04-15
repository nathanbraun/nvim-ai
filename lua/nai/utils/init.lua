-- lua/nai/utils/init.lua
local M = {}

-- The existing utilities
M.get_visual_selection = function()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  local start_line, start_col = start_pos[2], start_pos[3]
  local end_line, end_col = end_pos[2], end_pos[3]

  -- Get the lines in the selection
  local lines = vim.fn.getline(start_line, end_line)

  -- Adjust the first and last line to only include the selected text
  if #lines == 0 then
    return ""
  elseif #lines == 1 then
    lines[1] = string.sub(lines[1], start_col, end_col)
  else
    lines[1] = string.sub(lines[1], start_col)
    lines[#lines] = string.sub(lines[#lines], 1, end_col)
  end

  -- Join the lines with newline characters
  return table.concat(lines, "\n")
end

M.format_with_gq = function(text, wrap_width, buffer_id)
  -- Default wrap width if not specified
  wrap_width = wrap_width or 80
  buffer_id = buffer_id or vim.api.nvim_get_current_buf()

  -- Get current buffer's filetype and other formatting options
  local current_filetype = vim.api.nvim_buf_get_option(buffer_id, 'filetype')

  -- Function to format a paragraph with proper list item handling
  local function format_paragraph(lines, is_list)
    if #lines == 0 then return {} end

    local temp_buf = vim.api.nvim_create_buf(false, true)

    -- Set buffer content
    vim.api.nvim_buf_set_lines(temp_buf, 0, -1, false, lines)

    -- Set appropriate options for formatting
    vim.api.nvim_buf_set_option(temp_buf, 'filetype', current_filetype)
    vim.api.nvim_buf_set_option(temp_buf, 'textwidth', wrap_width)

    -- Copy relevant formatting options from the current buffer
    local options_to_copy = {
      'formatoptions',
      'comments',
      'commentstring',
      'expandtab',
      'tabstop',
      'shiftwidth',
      'softtabstop'
    }

    for _, opt in ipairs(options_to_copy) do
      local success, value = pcall(vim.api.nvim_buf_get_option, buffer_id, opt)
      if success then
        pcall(vim.api.nvim_buf_set_option, temp_buf, opt, value)
      end
    end

    -- For list items, we need the correct formatoptions
    if is_list then
      -- Ensure formatoptions has the right flags for lists and nested lists
      vim.api.nvim_buf_set_option(temp_buf, 'formatoptions', 'tcroqlwnj')

      -- Set formatlistpat for recognizing various list formats and indentation
      vim.api.nvim_buf_set_option(temp_buf, 'formatlistpat',
        '^\\s*\\d\\+[\\]:.)}\\t ]\\s*\\|^\\s*[-*+]\\s\\+\\|^\\s*\\[^\\ze[^\\]]\\+\\]:')
    end

    -- Format the text using gq
    vim.api.nvim_buf_call(temp_buf, function()
      -- For VimWiki, format all at once to handle nested lists
      vim.cmd('normal! ggVGgq')
    end)

    -- Get the formatted text
    local formatted_lines = vim.api.nvim_buf_get_lines(temp_buf, 0, -1, false)

    -- Clean up
    vim.api.nvim_buf_delete(temp_buf, { force = true })

    return formatted_lines
  end

  -- Process the text line by line
  local lines = vim.split(text, "\n")
  local result = {}
  local in_code_block = false
  local current_paragraph = {}
  local is_list_paragraph = false

  for i, line in ipairs(lines) do
    -- Check for code block markers
    if line:match("^```") then
      -- Format any accumulated paragraph before the code block
      if #current_paragraph > 0 then
        local formatted = format_paragraph(current_paragraph, is_list_paragraph)
        vim.list_extend(result, formatted)
        current_paragraph = {}
        is_list_paragraph = false
      end

      -- Toggle code block state
      in_code_block = not in_code_block

      -- Add the code block marker
      table.insert(result, line)
    elseif in_code_block then
      -- Inside code block, add line as is
      table.insert(result, line)
    else
      -- Check if this is a list item
      local is_list_item = line:match("^%s*[-*+]%s") or line:match("^%s*%d\\+%.%s")

      -- Check if this is a header (Markdown or VimWiki)
      local is_header = line:match("^#") or line:match("^=+%s")

      -- Check if the line is empty
      local is_empty = line:match("^%s*$")

      if is_empty then
        -- Empty line - format any accumulated paragraph
        if #current_paragraph > 0 then
          local formatted = format_paragraph(current_paragraph, is_list_paragraph)
          vim.list_extend(result, formatted)
          current_paragraph = {}
          is_list_paragraph = false
        end

        -- Add the empty line
        table.insert(result, "")
      elseif is_list_item then
        -- Mark that we're in a list paragraph
        is_list_paragraph = true

        -- Add to current paragraph
        table.insert(current_paragraph, line)
      elseif is_header then
        -- Format any accumulated paragraph before the header
        if #current_paragraph > 0 then
          local formatted = format_paragraph(current_paragraph, is_list_paragraph)
          vim.list_extend(result, formatted)
          current_paragraph = {}
          is_list_paragraph = false
        end

        -- Add the header directly
        table.insert(result, line)
      else
        -- Add to current paragraph
        table.insert(current_paragraph, line)
      end
    end
  end

  -- Format any remaining paragraph
  if #current_paragraph > 0 then
    local formatted = format_paragraph(current_paragraph, is_list_paragraph)
    vim.list_extend(result, formatted)
  end

  return table.concat(result, "\n")
end

-- Import and expose the indicators module
M.indicators = require('nai.utils.indicators')

return M
