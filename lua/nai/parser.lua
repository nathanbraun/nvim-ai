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
  local include_fileutils = require('nai.fileutils.include')

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
    elseif line:match("^>>> include") then
      -- Finish previous message if exists
      if current_message then
        current_message.content = table.concat(text_buffer, "\n")
        table.insert(messages, current_message)
        text_buffer = {}
      end
      current_message = { role = "user" }
      current_type = "include"
    elseif line:match("^>>> snapshot") then
      -- Finish previous message if exists
      if current_message then
        current_message.content = table.concat(text_buffer, "\n")
        table.insert(messages, current_message)
        text_buffer = {}
      end
      current_message = { role = "user" }
      current_type = "snapshot"
    elseif line:match("^>>> web") then
      -- Finish previous message if exists
      if current_message then
        current_message.content = table.concat(text_buffer, "\n")
        table.insert(messages, current_message)
        text_buffer = {}
      end
      current_message = { role = "user" }
      current_type = "web"
    elseif line:match("^>>> scrape") then
      -- Finish previous message if exists
      if current_message then
        current_message.content = table.concat(text_buffer, "\n")
        table.insert(messages, current_message)
        text_buffer = {}
      end
      current_message = { role = "user" }
      current_type = "scrape"
    elseif line:match("^>>> youtube") then
      -- Finish previous message if exists
      if current_message then
        current_message.content = table.concat(text_buffer, "\n")
        table.insert(messages, current_message)
        text_buffer = {}
      end
      current_message = { role = "user" }
      current_type = "youtube"
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
    -- Special processing for include blocks
    if current_type == "include" then
      current_message.content = include_fileutils.process_include_block(text_buffer)
    elseif current_type == "snapshot" then
      local snapshot_module = require('nai.fileutils.snapshot')
      current_message.content = snapshot_module.process_snapshot_block(text_buffer)
    elseif current_type == "web" then
      local web_module = require('nai.fileutils.web')
      current_message.content = web_module.process_web_block(text_buffer)
    elseif current_type == "youtube" then
      local youtube_module = require('nai.fileutils.youtube')
      current_message.content = youtube_module.process_youtube_block(text_buffer)
    elseif current_type == "scrape" then
      -- Special handling for scrape blocks
      -- In API requesting mode, we want to include the content, not the command
      local in_content_section = false
      local content_lines = {}

      for _, line in ipairs(text_buffer) do
        if line:match("^<<< content%s+%[") then
          in_content_section = true
        elseif in_content_section then
          table.insert(content_lines, line)
        end
      end

      if #content_lines > 0 then
        -- If we have content, use that
        current_message.content = table.concat(content_lines, "\n"):gsub("^%s*(.-)%s*$", "%1") -- trim
      else
        -- Otherwise, use the raw text
        current_message.content = table.concat(text_buffer, "\n"):gsub("^%s*(.-)%s*$", "%1") -- trim
      end
    else
      current_message.content = table.concat(text_buffer, "\n"):gsub("^%s*(.-)%s*$", "%1") -- trim
    end
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

-- In lua/nai/parser.lua
function M.format_web_block(content)
  return "\n>>> web\n\n" .. content
end

-- Format a system message for the buffer
function M.format_system_message(content)
  return "\n>>> system\n\n" .. content
end

-- Format an include block for the buffer
function M.format_include_block(content)
  return "\n>>> include\n\n" .. content
end

function M.format_youtube_block(url)
  return "\n>>> youtube\n\n" .. url
end

-- Format a snapshot block for the buffer
function M.format_snapshot(timestamp)
  local timestamp_str = timestamp or os.date("%Y-%m-%d %H:%M:%S")
  return "\n>>> snapshot [" .. timestamp_str .. "]\n\n"
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

-- Generate a system prompt that includes title instruction when needed
function M.get_system_prompt_with_title_request(is_untitled)
  local base_prompt = config.options.default_system_prompt

  -- If auto-titling is enabled and this is an untitled chat, append the title instruction
  if config.options.chat_files.auto_title and is_untitled then
    return base_prompt ..
        "\nFor your first response, please begin with 'Proposed Title: ' followed by a concise 3-7 word title summarizing this conversation. Place this on the first line of your response."
  else
    return base_prompt
  end
end

return M
