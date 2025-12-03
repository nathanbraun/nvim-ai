-- lua/nai/parser/processors/alias.lua
local MARKERS = require('nai.constants').MARKERS

return {
  marker = function(line)
    return line:match("^" .. vim.pesc(MARKERS.ALIAS)) ~= nil
  end,
  role = "user",

  -- Special handling: extract alias name and store it
  parse_line = function(line)
    local alias_name = line:match("^" .. vim.pesc(MARKERS.ALIAS) .. "%s*(.+)$")
    return { _alias = alias_name }
  end,

  format = function(content, alias_name)
    if alias_name then
      return "\n>>> alias: " .. alias_name .. "\n\n" .. content
    else
      return "\n>>> alias:\n\n" .. content
    end
  end
}
