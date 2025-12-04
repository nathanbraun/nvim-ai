-- lua/nai/parser.lua
-- Handles parsing chat buffers and formatting messages

local M = {}

local config = require('nai.config')

-- Initialize registry and register core processors
local registry = require('nai.parser.registry')
registry.register('user', require('nai.parser.processors.user'))
registry.register('assistant', require('nai.parser.processors.assistant'))
registry.register('system', require('nai.parser.processors.system'))
registry.register('tree', require('nai.parser.processors.tree'))
registry.register('alias', require('nai.parser.processors.alias'))
registry.register('reference', require('nai.parser.processors.reference'))
registry.register('snapshot', require('nai.parser.processors.snapshot'))
registry.register('web', require('nai.parser.processors.web'))
registry.register('youtube', require('nai.parser.processors.youtube'))
registry.register('crawl', require('nai.parser.processors.crawl'))
registry.register('scrape', require('nai.parser.processors.scrape'))

-- Parse chat buffer content into messages for API
function M.parse_chat_buffer(content, buffer_id)
  local lines = vim.split(content, "\n")
  local messages = {}
  local current_message = nil
  local current_type = nil
  local text_buffer = {}
  local MARKERS = require('nai.constants').MARKERS
  local chat_config = {} -- Store conversation-specific config
  local in_ignore_block = false
  local yaml_header_processed = false
  local has_content = false

  for i, line in ipairs(lines) do
    -- Check for ignore block markers first (before any other processing)
    if line:match("^" .. vim.pesc(MARKERS.IGNORE)) then
      in_ignore_block = true
      goto continue
    elseif line:match("^" .. vim.pesc(MARKERS.IGNORE_END)) then
      in_ignore_block = false
      goto continue
    end

    -- If we're inside an ignore block, add the line as plain text to current message
    if in_ignore_block then
      if current_message then
        table.insert(text_buffer, line)
      end
      goto continue
    end

    -- Skip YAML header (only at the beginning of the file, before any content)
    if line == "---" and not yaml_header_processed and not has_content then
      -- If we find a second '---', we're exiting the header
      if current_type == "yaml_header" then
        current_type = nil
        yaml_header_processed = true
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
      has_content = true -- We've encountered actual content
      -- Config block starts
      if current_message then
        current_message.content = table.concat(text_buffer, "\n")
        table.insert(messages, current_message)
        text_buffer = {}
      end
      current_message = nil -- Config isn't a message
      current_type = "config"
    else
      -- Check if line matches any registered processor
      local processor_name, processor = registry.match_line(line)
      if processor_name then
        has_content = true -- We've encountered actual content
        -- Finish previous message if exists
        if current_message then
          current_message.content = table.concat(text_buffer, "\n")
          table.insert(messages, current_message)
          text_buffer = {}
        end
        current_message = { role = processor.role }

        -- Handle special parsing (e.g., alias name extraction)
        if processor.parse_line then
          local extra_data = processor.parse_line(line)
          for k, v in pairs(extra_data) do
            current_message[k] = v
          end
        end

        current_type = processor_name
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
    end

    ::continue::
  end

  -- Add the last message if there is one
  if current_message then
    -- Check if this message type has special content processing
    local processor = registry.get(current_type)
    if processor and processor.process_content then
      current_message.content = processor.process_content(text_buffer)
    else
      current_message.content = table.concat(text_buffer, "\n"):gsub("^%s*(.-)%s*$", "%1") -- trim
    end
    table.insert(messages, current_message)
  end
  -- Process any alias messages
  local processed_messages, alias_chat_config = M.process_alias_messages(messages)

  -- Merge alias_chat_config into chat_config
  for key, value in pairs(alias_chat_config) do
    chat_config[key] = value
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

-- Generic formatter that delegates to processors
local function format_via_processor(processor_name, content)
  local processor = registry.get(processor_name)
  if processor then
    return processor.format(content)
  else
    error("Unknown processor: " .. processor_name)
  end
end

-- Format a new assistant message for the buffer
function M.format_assistant_message(content)
  return format_via_processor('assistant', content)
end

-- Format a new user message for the buffer
function M.format_user_message(content)
  return format_via_processor('user', content)
end

-- Format a system message for the buffer
function M.format_system_message(content)
  return format_via_processor('system', content)
end

function M.format_tree_block(content)
  return format_via_processor('tree', content)
end

function M.format_web_block(content)
  return format_via_processor('web', content)
end

function M.format_scrape_block(content)
  return format_via_processor('scrape', content)
end

function M.format_crawl_block(url)
  return format_via_processor('crawl', url)
end

function M.format_reference_block(content)
  return format_via_processor('reference', content)
end

function M.format_youtube_block(url)
  return format_via_processor('youtube', url)
end

function M.format_snapshot(timestamp)
  return format_via_processor('snapshot', timestamp)
end

function M.format_config_block(config_options)
  local lines = { "\n >>> config \n" }

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
  local constants = require('nai.constants')

  -- If auto-titling is enabled and this is an untitled chat, append the title instruction
  if config.options.chat_files.auto_title and is_untitled then
    return base_prompt .. constants.AUTO_TITLE_INSTRUCTION
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

function M.process_alias_messages(messages)
  local config = require('nai.config')

  -- Process any alias messages
  local processed_messages = {}
  local chat_config = {}

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

  return processed_messages, chat_config
end

return M
