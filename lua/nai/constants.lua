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
  REFERENCE = ">>> reference",
  SNAPSHOT = ">>> snapshot",
  CRAWL = ">>> crawl",
  TREE = ">>> tree",
  ALIAS = ">>> alias:",
  IGNORE = "```ignore",
  IGNORE_END = "```",
}

M.AUTO_TITLE_INSTRUCTION =
"\nFor your first response, please begin with 'Proposed Title: ' followed by a concise 3-7 word title summarizing this conversation. Place this on the first line of your response."

return M
