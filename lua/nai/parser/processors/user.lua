-- lua/nai/parser/processors/user.lua
local MARKERS = require('nai.constants').MARKERS

return {
  marker = MARKERS.USER,
  role = "user",

  format = function(content)
    return ">>> user\n\n" .. content
  end
}
