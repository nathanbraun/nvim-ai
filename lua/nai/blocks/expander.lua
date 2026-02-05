-- lua/nai/blocks/expander.lua
-- Handles expansion of various block types in chat buffers

local M = {}

-- Registry of block processors
M.processors = {}

-- Register a block processor
-- processor should have:
--   - marker: string or function(line) -> boolean (e.g., ">>> scrape")
--   - has_unexpanded: function(buffer_id) -> boolean
--   - expand: function(buffer_id, start_line, end_line) -> new_line_count
--   - has_active_requests: function() -> boolean (optional)
function M.register_processor(name, processor)
  -- Validate processor interface
  if not processor.marker then
    error("Block processor must have a 'marker' field")
  end
  if not processor.has_unexpanded then
    error("Block processor must have a 'has_unexpanded' function")
  end
  if not processor.expand then
    error("Block processor must have an 'expand' function")
  end

  M.processors[name] = processor
end

-- Find block boundaries for a given marker
-- Returns: start_line, end_line (0-indexed)
local function find_block_boundaries(lines, start_index, line_offset)
  local block_start = start_index - 1 + line_offset
  local block_end = #lines - 1 + line_offset
  
  -- Find the end of the block (next >>> or <<<)
  for j = start_index + 1, #lines do
    local line = lines[j]
    if line:match("^>>>") or line:match("^<<<") then
      block_end = j - 2 + line_offset
      break
    end
  end
  
  -- If we didn't find a marker, the block extends to the end of the file
  -- But we need to trim any trailing empty lines from the block
  if block_end == #lines - 1 + line_offset then
    -- Work backwards from the end to find the last non-empty line
    for j = #lines, start_index + 1, -1 do
      if lines[j]:match("%S") then -- Has non-whitespace content
        block_end = j - 1 + line_offset
        break
      end
    end
  end
  
  return block_start, block_end
end

-- Expand a single block type in the buffer
-- Returns: number of blocks expanded, whether async requests are pending
local function expand_block_type(buffer_id, processor)
  local config = require('nai.config')
  local constants = require('nai.constants')
  local expanded_count = 0
  local max_iterations = 100  -- Safety limit to prevent infinite loops
  local iteration = 0

  -- Keep expanding until no more unexpanded blocks found
  while processor.has_unexpanded(buffer_id) and iteration < max_iterations do
    iteration = iteration + 1
    
    if config.options.debug and config.options.debug.enabled then
      local marker_str = type(processor.marker) == "function" and "function" or processor.marker
      vim.notify(string.format("DEBUG: Iteration %d for %s", iteration, marker_str), vim.log.levels.DEBUG)
    end

    -- Fetch fresh buffer lines for each iteration
    local lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)
    local in_ignore_block = false
    local found_and_expanded = false

    -- Find and expand the first unexpanded block
    for i, line in ipairs(lines) do
      -- Check for ignore block markers
      if line == constants.MARKERS.IGNORE or vim.trim(line) == constants.MARKERS.IGNORE then
        in_ignore_block = true
        goto continue
      elseif line == constants.MARKERS.IGNORE_END or vim.trim(line) == constants.MARKERS.IGNORE_END then
        in_ignore_block = false
        goto continue
      end

      -- Skip processing if we're inside an ignore block
      if in_ignore_block then
        goto continue
      end

      -- Check if this line matches the processor's marker
      local matches = false
      if type(processor.marker) == "string" then
        matches = (line == processor.marker or vim.trim(line) == processor.marker)
      elseif type(processor.marker) == "function" then
        matches = processor.marker(line)
      end

      if matches then
        local block_start, block_end = find_block_boundaries(lines, i, 0)

        -- Expand the block
        local success, new_line_count = pcall(processor.expand, buffer_id, block_start, block_end + 1)

        if success then
          expanded_count = expanded_count + 1
          found_and_expanded = true
          
          if config.options.debug and config.options.debug.enabled then
            vim.notify(string.format("DEBUG: Expanded block at line %d", block_start), vim.log.levels.DEBUG)
          end
          
          -- Break inner loop to restart from beginning with fresh buffer state
          break
        else
          -- Log error but continue processing other blocks
          vim.notify("Error expanding block at line " .. block_start .. ": " .. tostring(new_line_count),
            vim.log.levels.ERROR)
        end
      end

      ::continue::
    end

    -- If we didn't find any block to expand, we're done
    if not found_and_expanded then
      break
    end
  end

  -- Warn if we hit the iteration limit
  if iteration >= max_iterations then
    local marker_str = type(processor.marker) == "function" and "function" or processor.marker
    vim.notify(
      string.format("Warning: Hit maximum iterations (%d) for %s. Some blocks may not have expanded.", 
        max_iterations, marker_str),
      vim.log.levels.WARN
    )
  end

  -- Check if there are active async requests
  local has_pending = false
  if processor.has_active_requests then
    has_pending = processor.has_active_requests()
  end

  return expanded_count, has_pending
end

-- Expand all registered block types in the buffer
-- Returns: true if any blocks were expanded or are pending
function M.expand_all(buffer_id)
  buffer_id = buffer_id or vim.api.nvim_get_current_buf()

  local total_expanded = 0
  local any_pending = false
  local results = {}

  -- Process each registered block type
  for name, processor in pairs(M.processors) do
    local count, pending = expand_block_type(buffer_id, processor)

    if count > 0 or pending then
      results[name] = {
        expanded = count,
        pending = pending
      }
      total_expanded = total_expanded + count
      any_pending = any_pending or pending
    end
  end

  -- Notify about results if anything happened
  if total_expanded > 0 then
    local msg_parts = {}
    for name, result in pairs(results) do
      if result.expanded > 0 then
        table.insert(msg_parts, string.format("%s: %d", name, result.expanded))
      end
    end
    if #msg_parts > 0 then
      vim.notify("Expanded blocks - " .. table.concat(msg_parts, ", "), vim.log.levels.INFO)
    end
  end

  -- Notify about pending requests
  if any_pending then
    local pending_types = {}
    for name, result in pairs(results) do
      if result.pending then
        table.insert(pending_types, name)
      end
    end
    if #pending_types > 0 then
      vim.notify("Async requests in progress: " .. table.concat(pending_types, ", "), vim.log.levels.INFO)
    end
  end

  return total_expanded > 0 or any_pending
end

return M
