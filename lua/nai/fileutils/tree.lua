-- lua/nai/fileutils/tree.lua
local M = {}
local path = require('nai.utils.path')
local block_processor = require('nai.fileutils.block_processor')

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
  return block_processor.expand_sync_block({
    buffer_id = buffer_id,
    start_line = start_line,
    end_line = end_line,
    block_type = "tree",
    progress_marker = ">>> generating-tree",
    completed_marker = ">>> tree",
    error_marker = ">>> tree-error",
    use_spinner = false,
    
    -- Spinner message
    spinner_message = function(target, options)
      return "Generating directory tree..."
    end,
    
    -- Execute the tree generation
    execute = function(lines, options)
      -- Initialize variables
      local directory_paths = {}
      local tree_options = ""

      -- Skip the first line which contains the tree marker
      for i = 2, #lines do
        local line = lines[i]
        -- Check if line starts with '--' for options
        if line:match("^%s*%-%-") then
          local option = line:match("^%s*%-%-(.+)$")
          if option then
            tree_options = tree_options .. " " .. option:gsub("^%s*", ""):gsub("%s*$", "")
          end
          -- If this line has content and isn't an option
        elseif line:match("%S") then
          -- This is a directory path
          local dir_path = line:gsub("^%s*", ""):gsub("%s*$", "")
          table.insert(directory_paths, dir_path)
        end
      end

      -- Check if we found any directory paths
      if #directory_paths == 0 then
        return nil, "No directory paths provided"
      end

      -- Check if tree command is available
      if not M.is_tree_available() then
        return nil, "'tree' command not found. Please install the tree utility."
      end

      -- Prepare the result
      local timestamp = os.date("%Y-%m-%d %H:%M:%S")
      local result_lines = {
        ">>> tree [" .. timestamp .. "]"
      }

      -- Add all directory paths
      for _, dir in ipairs(directory_paths) do
        table.insert(result_lines, dir)
      end

      -- Add options as comments if any were provided
      if tree_options ~= "" then
        table.insert(result_lines, "-- " .. tree_options:gsub("^%s*", ""))
      end

      -- Add a blank line
      table.insert(result_lines, "")

      -- Process each directory
      for _, dir_path in ipairs(directory_paths) do
        -- Expand the path
        local expanded_path = path.expand(dir_path)

        -- Check if directory exists
        if vim.fn.isdirectory(expanded_path) ~= 1 then
          table.insert(result_lines, "❌ Directory not found: " .. expanded_path)
          table.insert(result_lines, "")
        else
          -- Add a header for this directory
          table.insert(result_lines, "==> " .. expanded_path .. " <==")

          -- Run the tree command synchronously
          local cmd = "tree " .. vim.fn.shellescape(expanded_path) .. tree_options

          local result = vim.fn.system(cmd)
          local exit_code = vim.v.shell_error

          if exit_code ~= 0 then
            -- Add error message
            table.insert(result_lines, "❌ Error generating tree (exit code " .. exit_code .. ")")
            table.insert(result_lines, result)
          else
            -- Add the tree output
            for line in result:gmatch("[^
]+") do
              table.insert(result_lines, line)
            end
          end

          -- Add a blank line between directories
          table.insert(result_lines, "")
        end
      end

      -- Return result (no error)
      return result_lines, nil
    end,
  })
end

-- Check if there are unexpanded tree blocks in buffer
function M.has_unexpanded_tree_blocks(buffer_id)
  local lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)
  local constants = require('nai.constants')

  -- Track if we're inside an ignore block
  local in_ignored_block = false

  for _, line in ipairs(lines) do
    if line:match("^" .. vim.pesc(constants.MARKERS.IGNORE or "```ignore") .. "$") then
      in_ignored_block = true
    elseif in_ignored_block and line:match("^" .. vim.pesc(constants.MARKERS.IGNORE_END or "```") .. "$") then
      in_ignored_block = false
    elseif line == ">>> tree" then
      return true
    end
  end

  return false
end

-- Format a tree block for the buffer
function M.format_tree_block(directory_paths, options)
  -- Handle both string and table inputs
  if type(directory_paths) == "string" then
    directory_paths = { directory_paths }
  end

  -- Ensure we have at least one directory path
  if #directory_paths == 0 then
    directory_paths = { vim.fn.expand('%:p:h') } -- Default to current file's directory
  end

  -- Start with the tree marker
  local block = "\n>>> tree\n"

  -- Add each directory path on a separate line
  for _, dir in ipairs(directory_paths) do
    block = block .. dir .. "\n "
  end

  -- Add options if provided
  if options and options ~= "" then
    block = block .. "-- " .. options .. "\n"
  end

  return block
end

return M
