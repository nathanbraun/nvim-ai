-- lua/nai/constants.lua
local M = {}

-- Define fixed block markers
M.MARKERS = {
  USER = ">>> user",
  ASSISTANT = "<<< assistant",
  SYSTEM = ">>> system",
  CONFIG = ">>> config",
  WEB = ">>> web",
  SCRAPE = ">>> scrape",
  YOUTUBE = ">>> youtube",
  INCLUDE = ">>> include",
  SNAPSHOT = ">>> snapshot",
  CRAWL = ">>> crawl",
}

return M
