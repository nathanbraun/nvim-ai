-- lua/nai/parser/processors/scrape.lua
local MARKERS = require('nai.constants').MARKERS

return {
  marker = MARKERS.SCRAPE,
  role = "user",
  
  process_content = function(text_buffer)
    -- Special handling for scrape blocks
    -- In API requesting mode, we want to reference the content, not the command
    local in_content_section = false
    local content_lines = {}

    for _, line in ipairs(text_buffer) do
      if line:match("^<<< content%s+%[") then
        in_content_section = true
      elseif in_content_section then
        table.insert(content_lines, line)
      end
    end

    if #content_lines > 0 then
      -- If we have content, use that
      return table.concat(content_lines, "\n"):gsub("^%s*(.-)%s*$", "%1") -- trim
    else
      -- Otherwise, use the raw text
      return table.concat(text_buffer, "\n"):gsub("^%s*(.-)%s*$", "%1") -- trim
    end
  end,
  
  format = function(content)
    return "\n >>> scrape\n\n" .. content
  end
}

