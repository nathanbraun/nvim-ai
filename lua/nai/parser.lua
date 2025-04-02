-- lua/nai/parser.lua
-- Handles parsing chat buffers and formatting messages

local M = {}

local config = require('nai.config')

-- Parse chat buffer content into messages for API
function M.parse_chat_buffer(content)
  local lines = vim.split(content, "\n")
  local messages = {}
  local current_message = nil
  local current_type = nil
  local text_buffer = {}

  for _, line in ipairs(lines) do
    -- Skip YAML header
    if line == "---" then
      -- If we find a second '---', we're exiting the header
      if current_type == "yaml_header" then
        current_type = nil
      else
        current_type = "yaml_header"
      end
      goto continue
    end

    -- Skip YAML header content
    if current_type == "yaml_header" then
      goto continue
    end

    -- Process message markers
    if line:match("^>>> system") then
      -- Finish previous message if exists
      if current_message then
        current_message.content = table.concat(text_buffer, "\n")
        table.insert(messages, current_message)
        text_buffer = {}
      end
      current_message = { role = "system" }
      current_type = "system"
    elseif line:match("^>>> user") then
      -- Finish previous message if exists
      if current_message then
        current_message.content = table.concat(text_buffer, "\n")
        table.insert(messages, current_message)
        text_buffer = {}
      end
      current_message = { role = "user" }
      current_type = "user"
    elseif line:match("^<<< assistant") then
      -- Finish previous message if exists
      if current_message then
        current_message.content = table.concat(text_buffer, "\n")
        table.insert(messages, current_message)
        text_buffer = {}
      end
      current_message = { role = "assistant" }
      current_type = "assistant"
    elseif current_message then
      -- Skip the first empty line after a marker
      if #text_buffer == 0 and line == "" then
        goto continue
      end
      table.insert(text_buffer, line)
    end

    ::continue::
  end

  -- Add the last message if there is one
  if current_message then
    current_message.content = table.concat(text_buffer, "\n"):gsub("^%s*(.-)%s*$", "%1") -- trim
    table.insert(messages, current_message)
  end

  -- After parsing all messages, check if we have a system message
  local has_system_message = false
  for _, msg in ipairs(messages) do
    if msg.role == "system" then
      has_system_message = true
      break
    end
  end

  -- If no system message was found, add a default one at the beginning
  if not has_system_message then
    table.insert(messages, 1, {
      role = "system",
      content = config.options.default_system_prompt
    })
  end

  return messages
end

-- Format a new assistant message for the buffer
function M.format_assistant_message(content)
  return "\n<<< assistant\n\n" .. content
end

-- Format a new user message for the buffer
function M.format_user_message(content)
  -- No leading newline for new chats, but keep it for continuing chats
  return ">>> user\n\n" .. content
end

-- Format a system message for the buffer
function M.format_system_message(content)
  return "\n>>> system\n\n" .. content
end

-- Generate a YAML header with auto title
function M.generate_header(title)
  -- Generate a date in YYYY-MM-DD format
  local date = os.date("%Y-%m-%d")

  -- If no title provided, use a placeholder
  title = title or "New Chat"

  return string.format([[---
title: %s
date: %s
tags: [naichat]
---]], title, date)
end

return M
