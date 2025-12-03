-- lua/nai/parser/processors/snapshot.lua
local MARKERS = require('nai.constants').MARKERS

return {
  marker = MARKERS.SNAPSHOT,
  role = "user",
  
  process_content = function(text_buffer)
    local snapshot_module = require('nai.fileutils.snapshot')
    return snapshot_module.process_snapshot_block(text_buffer)
  end,
  
  format = function(timestamp)
    local timestamp_str = timestamp or os.date("%Y-%m-%d %H:%M:%S")
    return "\n >>> snapshot [" .. timestamp_str .. "]\n\n"
  end
}

