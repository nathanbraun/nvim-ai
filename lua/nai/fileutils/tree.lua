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

-- Parse options from the tree marker line
local function parse_marker_options(marker_line)
  local options = ""

  -- Extract everything after ">>> tree"
  local after_marker = marker_line:match("^>>>%s*tree%s+(.*)$")

  if after_marker and after_marker ~= "" then
    options = after_marker
  end

  return options
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

      -- Parse options from the first line (marker line)
      if lines[1] then
        tree_options = parse_marker_options(lines[1])
      end

      -- Skip the first line which contains the tree marker
      -- and collect directory paths and additional options from comment lines
      for i = 2, #lines do
        local line = lines[i]
        -- Check if line starts with '--' for additional options
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
        ">>> tree" .. (tree_options ~= "" and " " .. tree_options or "") .. " [" .. timestamp .. "]"
      }

      -- Add all directory paths
      for _, dir in ipairs(directory_paths) do
        table.insert(result_lines, dir)
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
          local cmd = "tree " .. vim.fn.shellescape(expanded_path)
          if tree_options ~= "" then
            cmd = cmd .. " " .. tree_options
          end

          local result = vim.fn.system(cmd)
          local exit_code = vim.v.shell_error

          if exit_code ~= 0 then
            -- Add error message
            table.insert(result_lines, "❌ Error generating tree (exit code " .. exit_code .. ")")
            table.insert(result_lines, result)
          else
            -- Add the tree output
            for line in result:gmatch("[^\r\n]+") do
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
    elseif line:match("^>>>%s*tree") and not line:match("%[%d%d%d%d%-%d%d%-%d%d") then
      return true
    end
  end

  return false
end

-- Format a tree block for the buffer
function M.format_tree_block(directory_paths, ignore_patterns)
  -- Handle both string and table inputs
  if type(directory_paths) == "string" then
    directory_paths = { directory_paths }
  end

  -- Ensure we have at least one directory path
  if #directory_paths == 0 then
    directory_paths = { vim.fn.expand('%:p:h') } -- Default to current file's directory
  end

  -- Start with the tree marker
  local marker = ">>> tree"

  -- Add ignore patterns if provided
  if ignore_patterns and ignore_patterns ~= "" then
    marker = marker .. " -I '" .. ignore_patterns .. "'"
  end

  local block = "\n" .. marker .. "\n"

  -- Add each directory path on a separate line
  for _, dir in ipairs(directory_paths) do
    block = block .. dir .. "\n"
  end

  -- Add trailing space
  block = block .. " "

  return block
end

-- Register tree processor with the expander
local function register_with_expander()
  local expander = require('nai.blocks.expander')

  expander.register_processor('tree', {
    marker = function(line)
      return line:match("^>>>%s*tree") ~= nil
    end,

    has_unexpanded = M.has_unexpanded_tree_blocks,

    expand = M.expand_tree_in_buffer,

    -- No active requests tracking for tree (synchronous operation)
    has_active_requests = nil,
  })
end

-- Auto-register when module is loaded
register_with_expander()

return M
