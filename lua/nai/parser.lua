-- lua/nai/parser.lua
-- Handles parsing chat buffers and formatting messages

local M = {}

local config = require('nai.config')

-- Parse chat buffer content into messages for API
function M.parse_chat_buffer(content, buffer_id)
  local lines = vim.split(content, "\n")
  local messages = {}
  local current_message = nil
  local current_type = nil
  local text_buffer = {}
  local reference_fileutils = require('nai.fileutils.reference')
  local MARKERS = require('nai.constants').MARKERS
  local chat_config = {} -- Store conversation-specific config

  for i, line in ipairs(lines) do
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
    if line:match("^" .. vim.pesc(MARKERS.CONFIG or ">>> config")) then
      -- Config block starts
      if current_message then
        current_message.content = table.concat(text_buffer, "\n")
        table.insert(messages, current_message)
        text_buffer = {}
      end
      current_message = nil -- Config isn't a message
      current_type = "config"
    elseif line:match("^" .. vim.pesc(MARKERS.SYSTEM)) then
      -- Finish previous message if exists
      if current_message then
        current_message.content = table.concat(text_buffer, "\n")
        table.insert(messages, current_message)
        text_buffer = {}
      end
      current_message = { role = "system" }
      current_type = "system"
    elseif line:match("^" .. vim.pesc(MARKERS.USER)) then
      -- Finish previous message if exists
      if current_message then
        current_message.content = table.concat(text_buffer, "\n")
        table.insert(messages, current_message)
        text_buffer = {}
      end
      current_message = { role = "user" }
      current_type = "user"
    elseif line:match("^" .. vim.pesc(MARKERS.ASSISTANT)) then
      -- Finish previous message if exists
      if current_message then
        current_message.content = table.concat(text_buffer, "\n")
        table.insert(messages, current_message)
        text_buffer = {}
      end
      current_message = { role = "assistant" }
      current_type = "assistant"
    elseif line:match("^" .. vim.pesc(MARKERS.REFERENCE)) then
      -- Finish previous message if exists
      if current_message then
        current_message.content = table.concat(text_buffer, "\n")
        table.insert(messages, current_message)
        text_buffer = {}
      end
      current_message = { role = "user" }
      current_type = "reference"
    elseif line:match("^" .. vim.pesc(MARKERS.SNAPSHOT)) then
      -- Finish previous message if exists
      if current_message then
        current_message.content = table.concat(text_buffer, "\n")
        table.insert(messages, current_message)
        text_buffer = {}
      end
      current_message = { role = "user" }
      current_type = "snapshot"
    elseif line:match("^" .. vim.pesc(MARKERS.WEB)) then
      -- Finish previous message if exists
      if current_message then
        current_message.content = table.concat(text_buffer, "\n")
        table.insert(messages, current_message)
        text_buffer = {}
      end
      current_message = { role = "user" }
      current_type = "web"
    elseif line:match("^" .. vim.pesc(MARKERS.CRAWL)) then
      -- Finish previous message if exists
      if current_message then
        current_message.content = table.concat(text_buffer, "\n")
        table.insert(messages, current_message)
        text_buffer = {}
      end
      current_message = { role = "user" }
      current_type = "crawl"
    elseif line:match("^" .. vim.pesc(MARKERS.SCRAPE)) then
      -- Finish previous message if exists
      if current_message then
        current_message.content = table.concat(text_buffer, "\n")
        table.insert(messages, current_message)
        text_buffer = {}
      end
      current_message = { role = "user" }
      current_type = "scrape"
    elseif line:match("^" .. vim.pesc(MARKERS.YOUTUBE)) then
      -- Finish previous message if exists
      if current_message then
        current_message.content = table.concat(text_buffer, "\n")
        table.insert(messages, current_message)
        text_buffer = {}
      end
      current_message = { role = "user" }
      current_type = "youtube"
    elseif line:match("^" .. vim.pesc(MARKERS.ALIAS)) then
      -- Extract the alias name
      local alias_name = line:match("^" .. vim.pesc(MARKERS.ALIAS) .. "%s*(.+)$")

      -- Finish previous message if exists
      if current_message then
        current_message.content = table.concat(text_buffer, "\n")
        table.insert(messages, current_message)
        text_buffer = {}
      end

      -- Start a new user message for the content under the alias
      current_message = {
        role = "user",
        _alias = alias_name -- Store the alias name for later processing
      }
      current_type = "alias"
    elseif current_message then
      -- Skip the first empty line after a marker
      if #text_buffer == 0 and line == "" then
        goto continue
      end
      table.insert(text_buffer, line)
    elseif current_type == "config" then
      -- Process config lines
      if line ~= "" then -- Skip empty lines
        local key, value = line:match("^%s*([%w_]+)%s*:%s*(.+)$")
        if key and value then
          -- Trim whitespace
          value = value:gsub("^%s*(.-)%s*$", "%1")

          -- Convert certain values
          if key == "temperature" then
            value = tonumber(value)
          elseif key == "max_tokens" then
            value = tonumber(value)
          elseif key == "expand_placeholders" then
            -- Convert string boolean to actual boolean
            value = value:lower() == "true"
            vim.notify("Setting expand_placeholders to: " .. tostring(value), vim.log.levels.DEBUG)
          end

          chat_config[key] = value
        else
          vim.notify("Failed to parse config line: " .. line, vim.log.levels.DEBUG)
        end
      else
        -- Empty line after config marker means end of config block
        current_type = nil
      end
    end

    ::continue::
  end

  -- Add the last message if there is one
  if current_message then
    -- Special processing for reference blocks
    if current_type == "reference" then
      current_message.content = reference_fileutils.process_reference_block(text_buffer)
    elseif current_type == "snapshot" then
      local snapshot_module = require('nai.fileutils.snapshot')
      current_message.content = snapshot_module.process_snapshot_block(text_buffer)
    elseif current_type == "web" then
      local web_module = require('nai.fileutils.web')
      current_message.content = web_module.process_web_block(text_buffer)
    elseif current_type == "youtube" then
      local youtube_module = require('nai.fileutils.youtube')
      current_message.content = youtube_module.process_youtube_block(text_buffer)
    elseif current_type == "crawl" then
      local crawl_module = require('nai.fileutils.crawl')
      current_message.content = crawl_module.process_crawl_block(text_buffer)
    elseif current_type == "scrape" then
      -- Special handling for scrape blocks
      -- In API requesting mode, we want to reference the content, not the command
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
  -- Process any alias messages
  local processed_messages = {}
  local i = 1
  while i <= #messages do
    local msg = messages[i]

    if msg.role == "user" and msg._alias then
      local alias_name = msg._alias
      local alias_config = config.options.aliases[alias_name]

      if alias_config then
        -- Insert the system message from the alias config
        table.insert(processed_messages, {
          role = "system",
          content = alias_config.system
        })

        -- Add the user message (optionally with prefix)
        local user_content = msg.content
        if alias_config.user_prefix and alias_config.user_prefix ~= "" then
          user_content = alias_config.user_prefix .. "\n\n" .. user_content
        end

        table.insert(processed_messages, {
          role = "user",
          content = user_content
        })

        if alias_config.config then
          -- Merge alias config with chat_config (alias takes precedence)
          for key, value in pairs(alias_config.config) do
            chat_config[key] = value
          end
        end
      else
        -- If alias not found, just add the original message
        table.insert(processed_messages, msg)
      end
    else
      -- For non-alias messages, just add them as-is
      table.insert(processed_messages, msg)
    end

    i = i + 1
  end


  -- After parsing all messages, check if we have a system message
  local has_system_message = false
  for _, msg in ipairs(processed_messages) do
    if msg.role == "system" then
      has_system_message = true
      break
    end
  end

  -- If no system message was found, add a default one at the beginning
  if not has_system_message then
    table.insert(processed_messages, 1, {
      role = "system",
      content = config.options.default_system_prompt
    })
  end


  return processed_messages, chat_config
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

-- Format a crawl block for the buffer
function M.format_crawl_block(url)
  return "\n>>> crawl\n\n" .. url .. "\n\n-- limit: 5\n-- depth: 2\n-- format: markdown"
end

-- Format a reference block for the buffer
function M.format_reference_block(content)
  return "\n>>> reference\n\n" .. content
end

function M.format_youtube_block(url)
  return "\n>>> youtube\n\n" .. url
end

-- Format a snapshot block for the buffer
function M.format_snapshot(timestamp)
  local timestamp_str = timestamp or os.date("%Y-%m-%d %H:%M:%S")
  return "\n>>> snapshot [" .. timestamp_str .. "]\n\n"
end

function M.format_config_block(config_options)
  local lines = { "\n>>> config\n" }

  -- Add each option
  for key, value in pairs(config_options or {}) do
    -- For boolean values, ensure they're formatted properly
    if type(value) == "boolean" then
      value = value and "true" or "false"
    end
    table.insert(lines, key .. ": " .. tostring(value))
  end

  table.insert(lines, "")
  return table.concat(lines, "\n")
end

-- Generate a YAML header with auto title
function M.generate_header(title)
  -- Get header configuration
  local header_config = config.options.chat_files.header or {}

  -- Check if headers are enabled (default to true if not specified)
  if header_config.enabled == false then
    return "" -- Return empty string if disabled
  end

  -- Generate a date in YYYY-MM-DD format
  local date = os.date("%Y-%m-%d")

  -- If no title provided, use a placeholder
  title = title or "New Chat"

  -- Get template from config or use default
  local template = header_config.template or [[---
title: {title}
date: {date}
tags: [ai]
---]]

  -- Replace variables in template
  local header = template:gsub("{title}", title):gsub("{date}", date)

  return header
end

-- Generate a system prompt that references title instruction when needed
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

function M.replace_placeholders(content, buffer_id)
  -- Check for various file content placeholder formats
  local placeholders = {
    "%%FILE_CONTENTS%%",
    "${FILE_CONTENTS}",
    "$FILE_CONTENTS"
  }

  for _, placeholder in ipairs(placeholders) do
    if content:match(vim.pesc(placeholder)) then
      -- Get the current buffer content up to the first chat marker
      local lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)
      local file_content = {}

      -- Find the first chat marker
      for i, line in ipairs(lines) do
        if line:match("^>>>") or line:match("^<<<") then
          break
        end
        table.insert(file_content, line)
      end

      -- Replace the placeholder with the file content
      content = content:gsub(vim.pesc(placeholder), table.concat(file_content, "\n"))
    end
  end

  return content
end

return M
