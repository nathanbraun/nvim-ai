local M = {}
local config = require('nai.config')

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
  dir = dir:gsub("/*$", "/") -- Remove trailing slashes and add one back
  vim.fn.mkdir(dir, "p")

  -- Format the variable parts
  local date = os.date("%Y%m%d")
  local id
  if config.options.chat_files.use_timestamp then
    id = M.generate_timestamp()
  else
    id = M.generate_id(config.options.chat_files.id_length)
  end

  -- Clean the title for use in a filename
  local clean_title = title:gsub("[^%w%s-]", ""):gsub("%s+", "-"):lower()
  if #clean_title > 40 then
    clean_title = clean_title:sub(1, 40)
  end

  -- Apply the filename format from config but use .md instead of .naichat
  local filename = config.options.chat_files.format
  filename = filename:gsub("{date}", date)
  filename = filename:gsub("{id}", id)
  filename = filename:gsub("{title}", clean_title)
  filename = filename:gsub("%.naichat$", ".md") -- Replace .naichat with .md

  return vim.fn.expand(dir .. filename)
end

-- Save buffer to a file
function M.save_chat_buffer(buffer_id, filename)
  -- If no filename provided, generate one from buffer header
  if not filename then
    local lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)
    local title = "chat"

    -- Try to find a title in the YAML header
    for i, line in ipairs(lines) do
      local title_match = line:match("^title:%s*(.+)$")
      if title_match then
        title = title_match
        break
      end
      if line == "---" and i > 1 then
        break -- End of header
      end
    end

    filename = M.generate_filename(title)
  end

  -- Save buffer to file
  vim.api.nvim_buf_set_name(buffer_id, filename)
  vim.api.nvim_command("write")

  return filename
end

return M
