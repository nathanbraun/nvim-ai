-- lua/nai/parser/processors/youtube.lua
local MARKERS = require('nai.constants').MARKERS

return {
  marker = MARKERS.YOUTUBE,
  role = "user",
  
  process_content = function(text_buffer)
    local youtube_module = require('nai.fileutils.youtube')
    return youtube_module.process_youtube_block(text_buffer)
  end,
  
  format = function(url)
    return "\n>>> youtube \n\n" .. url
  end
}

