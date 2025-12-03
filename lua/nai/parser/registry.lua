-- lua/nai/parser/registry.lua
-- Registry for message/block type processors

local M = {}

-- Storage for registered processors
M.processors = {}

-- Register a message processor
-- processor should have:
--   - marker: string or function(line) -> boolean
--   - role: string (API role like "user", "system", "assistant")
--   - process_content: optional function(text_buffer) -> string
--   - format: function(content) -> string
function M.register(name, processor)
  -- Validate processor interface
  if not processor.marker then
    error("Processor must have a 'marker' field")
  end
  if not processor.role then
    error("Processor must have a 'role' field")
  end
  if not processor.format then
    error("Processor must have a 'format' function")
  end

  M.processors[name] = processor
end

-- Get a processor by name
function M.get(name)
  return M.processors[name]
end

-- Check if a line matches any registered processor
-- Returns: processor_name, processor or nil, nil
function M.match_line(line)
  for name, processor in pairs(M.processors) do
    local matches = false

    if type(processor.marker) == "string" then
      matches = line:match("^" .. vim.pesc(processor.marker))
    elseif type(processor.marker) == "function" then
      matches = processor.marker(line)
    end

    if matches then
      return name, processor
    end
  end

  return nil, nil
end

return M
