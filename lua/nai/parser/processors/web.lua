-- lua/nai/parser/processors/web.lua
local MARKERS = require('nai.constants').MARKERS

return {
  marker = MARKERS.WEB,
  role = "user",
  
  process_content = function(text_buffer)
    local web_module = require('nai.fileutils.web')
    return web_module.process_web_block(text_buffer)
  end,
  
  format = function(content)
    return "\n>>> web\n\n" .. content
  end
}

