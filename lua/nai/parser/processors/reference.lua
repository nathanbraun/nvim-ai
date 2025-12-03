-- lua/nai/parser/processors/reference.lua
local MARKERS = require('nai.constants').MARKERS

return {
  marker = MARKERS.REFERENCE,
  role = "user",
  
  process_content = function(text_buffer)
    local reference_fileutils = require('nai.fileutils.reference')
    return reference_fileutils.process_reference_block(text_buffer)
  end,
  
  format = function(content)
    return "\n >>> reference \n\n" .. content
  end
}

