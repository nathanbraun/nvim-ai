-- lua/nai/parser/processors/assistant.lua
local MARKERS = require('nai.constants').MARKERS

return {
  marker = MARKERS.ASSISTANT,
  role = "assistant",

  format = function(content)
    return "\n<<< assistant\n\n" .. content
  end
}
