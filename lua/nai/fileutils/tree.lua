-- lua/nai/fileutils/tree.lua
local M = {}
local path = require('nai.utils.path')

-- Check if tree command is available
function M.is_tree_available()
  return vim.fn.executable('tree') == 1
end

-- Process tree block for API requests
function M.process_tree_block(lines)
  -- For API requests, just use the text that's already in the buffer
  -- since we've already expanded the tree
  return table.concat(lines, "\n")
end

-- Create and expand a tree in the buffer
function M.expand_tree_in_buffer(buffer_id, start_line, end_line)
  -- Get the tree block lines
  local lines = vim.api.nvim_buf_get_lines(buffer_id, start_line, end_line, false)

  -- Change marker to show it's in progress
  vim.api.nvim_buf_set_lines(
    buffer_id,
    start_line,
    start_line + 1,
    false,
    { ">>> generating-tree" }
  )

  -- Skip the first line which contains the tree marker
  local directory_path = nil
  local options = ""

  -- Parse the block content - improved to better handle the directory path
  for i = 2, #lines do
    local line = lines[i]
    if line:match("^%s*--") then
      -- Parse options
      local option = line:match("^%s*--(.+)$")
      if option then
        options = options .. " " .. option:gsub("^%s*", ""):gsub("%s*$", "")
      end
    elseif not directory_path and line:match("%S") then
      -- First non-empty, non-option line is the directory path
      directory_path = line:gsub("^%s*", ""):gsub("%s*$", "")
    end
  end

  if not directory_path or directory_path == "" then
    -- If no directory path was found, use current file's directory as fallback
    directory_path = vim.fn.expand('%:p:h')

    -- If still empty, show error
    if directory_path == "" then
      vim.api.nvim_buf_set_lines(
        buffer_id,
        start_line,
        end_line,
        false,
        {
          ">>> tree-error",
          "❌ Error: No directory path provided",
          ""
        }
      )
      return (end_line - start_line)
    end
  end

  -- Expand the path
  directory_path = path.expand(directory_path)

  -- Check if directory exists
  if vim.fn.isdirectory(directory_path) ~= 1 then
    vim.api.nvim_buf_set_lines(
      buffer_id,
      start_line,
      end_line,
      false,
      {
        ">>> tree-error",
        "❌ Error: Directory not found: " .. directory_path,
        ""
      }
    )
    return (end_line - start_line)
  end

  -- Check if tree command is available
  if not M.is_tree_available() then
    vim.api.nvim_buf_set_lines(
      buffer_id,
      start_line,
      end_line,
      false,
      {
        ">>> tree-error",
        "❌ Error: 'tree' command not found. Please install the tree utility.",
        ""
      }
    )
    return (end_line - start_line)
  end

  -- Create a spinner animation at the end of the block
  local indicator = {
    buffer_id = buffer_id,
    start_row = start_line,
    end_row = end_line,
    spinner_row = start_line + 2, -- Add spinner after directory path
    timer = nil
  }

  -- Insert spinner line
  vim.api.nvim_buf_set_lines(
    buffer_id,
    start_line + 2,
    start_line + 2,
    false,
    { "⏳ Generating directory tree..." }
  )

  -- Start the animation
  local animation_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
  local current_frame = 1

  indicator.timer = vim.loop.new_timer()
  indicator.timer:start(0, 120, vim.schedule_wrap(function()
    -- Check if buffer still exists
    if not vim.api.nvim_buf_is_valid(buffer_id) then
      if indicator.timer then
        indicator.timer:stop()
        indicator.timer:close()
        indicator.timer = nil
      end
      return
    end

    -- Update the spinner animation
    local status_text = animation_frames[current_frame] .. " Generating directory tree" .. directory_path

    -- Update the text in the buffer
    vim.api.nvim_buf_set_lines(
      buffer_id,
      indicator.spinner_row,
      indicator.spinner_row + 1,
      false,
      { status_text }
    )

    -- Move to the next animation frame
    current_frame = (current_frame % #animation_frames) + 1
  end))

  -- Run the tree command
  local cmd = "cd " .. vim.fn.shellescape(directory_path) .. " && tree" .. options
  local output_lines = {}
  local error_lines = {}
  local has_error = false

  vim.fn.jobstart(cmd, {
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(output_lines, line)
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(error_lines, line)
            has_error = true
          end
        end
      end
    end,
    on_exit = function(_, exit_code)
      -- Stop the timer
      if indicator.timer then
        indicator.timer:stop()
        indicator.timer:close()
        indicator.timer = nil
      end

      -- Check if buffer is still valid
      if not vim.api.nvim_buf_is_valid(buffer_id) then
        return
      end

      if exit_code ~= 0 or has_error then
        -- Format the error
        local error_result = {
          ">>> tree-error",
          directory_path,
          "",
          "❌ Error generating directory tree:"
        }

        -- Add error details
        if #error_lines > 0 then
          for _, line in ipairs(error_lines) do
            table.insert(error_result, line)
          end
        else
          table.insert(error_result, "Exit code: " .. exit_code)
        end

        -- Add output if available (sometimes tree outputs the tree even with an error)
        if #output_lines > 0 then
          table.insert(error_result, "")
          table.insert(error_result, "Output:")
          for _, line in ipairs(output_lines) do
            table.insert(error_result, line)
          end
        end

        -- Replace the placeholder with the error
        vim.api.nvim_buf_set_lines(
          buffer_id,
          indicator.start_row,
          math.max(indicator.end_row, indicator.start_row + 3),
          false,
          error_result
        )

        -- Show error notification
        vim.schedule(function()
          vim.notify("Error generating directory tree (exit code " .. exit_code .. ")", vim.log.levels.ERROR)
        end)
      else
        -- Format the successful result
        local timestamp = os.date("%Y-%m-%d %H:%M:%S")
        local result_lines = {
          ">>> tree [" .. timestamp .. "]"
        }

        -- Add options as comments if any were provided
        if options ~= "" then
          table.insert(result_lines, "-- " .. options:gsub("^%s*", ""))
        end

        -- Add a blank line
        table.insert(result_lines, "")

        -- Add all tree output lines
        for _, line in ipairs(output_lines) do
          table.insert(result_lines, line)
        end

        -- Replace the placeholder with the result
        vim.api.nvim_buf_set_lines(
          buffer_id,
          indicator.start_row,
          math.max(indicator.end_row, indicator.start_row + 3),
          false,
          result_lines
        )

        -- Notify completion
        vim.schedule(function()
          vim.notify("Directory tree generated successfully", vim.log.levels.INFO)
        end)
      end
    end
  })

  -- Return the changed number of lines in the placeholder
  return 3 -- The marker line + directory path + spinner
end

-- Check if there are unexpanded tree blocks in buffer
function M.has_unexpanded_tree_blocks(buffer_id)
  local lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)
  local constants = require('nai.constants')

  -- Track if we're inside an ignore block
  local in_ignored_block = false

  for i, line in ipairs(lines) do
    if line:match("^" .. vim.pesc(constants.MARKERS.IGNORE or "```ignore") .. "$") then
      in_ignored_block = true
    elseif in_ignored_block and line:match("^" .. vim.pesc(constants.MARKERS.IGNORE_END or "```") .. "$") then
      in_ignored_block = false
    elseif not in_ignored_block and vim.trim(line) == ">>> tree" then
      return true
    end
  end

  return false
end

-- Format a tree block for the buffer
function M.format_tree_block(directory_path, options)
  -- Ensure we have a directory path
  if not directory_path or directory_path == "" then
    directory_path = vim.fn.expand('%:p:h') -- Default to current file's directory
  end

  local result = "\n>>> tree\n"

  -- Add the directory path with a newline
  result = result .. directory_path .. "\n"

  -- Add options if provided
  if options and options ~= "" then
    result = result .. "-- " .. options .. "\n"
  end

  return result
end

function M.debug_tree_block(buffer_id, start_line, end_line)
  -- Get the tree block lines
  local lines = vim.api.nvim_buf_get_lines(buffer_id, start_line, end_line, false)

  return true
end

return M
