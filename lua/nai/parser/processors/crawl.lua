-- lua/nai/parser/processors/crawl.lua
local MARKERS = require('nai.constants').MARKERS

return {
  marker = MARKERS.CRAWL,
  role = "user",
  
  process_content = function(text_buffer)
    local crawl_module = require('nai.fileutils.crawl')
    return crawl_module.process_crawl_block(text_buffer)
  end,
  
  format = function(url)
    return "\n >>> crawl \n\n" .. url .. "\n\n-- limit: 5\n-- depth: 2\n-- format: markdown"
  end
}
