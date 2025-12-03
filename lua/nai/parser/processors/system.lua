-- lua/nai/parser/processors/system.lua
local MARKERS = require('nai.constants').MARKERS

return {
  marker = MARKERS.SYSTEM,
  role = "system",
  
  format = function(content)
    return "\n >>> system\n\n " .. content
  end
}

