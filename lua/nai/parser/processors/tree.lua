-- lua/nai/parser/processors/tree.lua
local MARKERS = require('nai.constants').MARKERS

return {
  marker = MARKERS.TREE,
  role = "user",

  format = function(content)
    return "\n>>> tree\n" .. content
  end
}

