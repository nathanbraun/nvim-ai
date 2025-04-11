local M = {}
local config = require('nai.config')
local path = require('nai.utils.path')

-- Generate a random ID for filenames
function M.generate_id(length)
  local id = ""
  local chars = "abcdefghijklmnopqrstuvwxyz0123456789"
  for i = 1, length do
    local rand = math.random(1, #chars)
    id = id .. string.sub(chars, rand, rand)
  end
  return id
end

-- Generate a timestamp for filenames
function M.generate_timestamp()
  return os.date("%Y%m%d%H%M%S")
end

-- Generate a filename from a title
function M.generate_filename(title)
  -- Ensure directory exists
  local dir = config.options.chat_files.directory

  -- Normalize directory path with trailing separator
  if dir:sub(-1) ~= path.separator then
    dir = dir .. path.separator
  end

  path.mkdir(path.expand(dir))

  -- Format the variable parts
  local date = os.date("%Y%m%d")
  local id = config.options.chat_files.use_timestamp and M.generate_timestamp() or
      M.generate_id(config.options.chat_files.id_length)

  -- Clean the title for use in a filename
  local clean_title = title:gsub("[^%w%s-]", ""):gsub("%s+", "-"):lower()

  -- Windows has additional filename restrictions
  if path.is_windows then
    clean_title = clean_title:gsub("[<>:\"/\\|?*]", "")
  end

  -- Truncate if too long
  if #clean_title > 40 then
    clean_title = clean_title:sub(1, 40)
  end

  -- Apply the filename format from config but use .md instead of .naichat
  local filename = config.options.chat_files.format
      :gsub("{date}", date)
      :gsub("{id}", id)
      :gsub("{title}", clean_title)
      :gsub("%.naichat$", ".md") -- Replace .naichat with .md

  return path.expand(path.join(dir, filename))
end

return M
