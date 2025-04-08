-- lua/nai/init.lua
-- Main module for nvim-ai plugin

local M = {}
local config = require('nai.config')
local api = require('nai.api')
local utils = require('nai.utils')

-- Setup function that should be called by the user
function M.setup(opts)
  config.setup(opts)

  -- Additional setup if needed
  return M
end

M.active_request = nil

function M.cancel()
  if M.active_request then
    if vim.system and M.active_request.terminate then
      M.active_request:terminate()
    elseif not vim.system and M.active_request.close then
      M.active_request:close()
    end
    M.active_request = nil

    -- Remove the indicator if it exists
    if M.active_indicator then
      utils.indicators.remove(M.active_indicator)
      M.active_indicator = nil
    end

    vim.notify("AI completion cancelled", vim.log.levels.INFO)
  end
end

-- Development helper to reload the plugin
function M.reload()
  -- Clear the module cache for the plugin
  for k in pairs(package.loaded) do
    if k:match("^nai") then
      package.loaded[k] = nil
    end
  end

  local current_buf = vim.api.nvim_get_current_buf()
  if require('nai.buffer').activated_buffers[current_buf] then
    require('nai.buffer').apply_syntax_overlay(current_buf)
  end

  -- Reload the main module
  return require("nai")
end

-- Function to switch between providers
function M.switch_provider(provider)
  if provider ~= "openai" and provider ~= "openrouter" then
    vim.notify("Invalid provider. Use 'openai' or 'openrouter'", vim.log.levels.ERROR)
    return
  end

  require('nai.config').options.provider = provider
  require('nai.config').init_config() -- Make sure API key is loaded
  vim.notify("Switched to " .. provider .. " provider", vim.log.levels.INFO)
end

function M.chat(opts)
  local profiler = require('nai.utils.profiler')
  return profiler.measure("chat_command", function(opts)
    local parser = require('nai.parser')
    local fileutils = require('nai.fileutils')
    local buffer_id = vim.api.nvim_get_current_buf()
    local buffer_module = require('nai.buffer')

    -- Force activation for this buffer if it contains user prompts
    local contains_chat_markers = buffer_module.detect_chat_markers(buffer_id)
    if contains_chat_markers and not buffer_module.activated_buffers[buffer_id] then
      vim.notify("Found chat markers, activating buffer...", vim.log.levels.INFO)
      buffer_module.activate_buffer(buffer_id)
    end

    -- Check if buffer is activated after our attempt
    if not buffer_module.activated_buffers[buffer_id] then
      vim.notify("Buffer not activated, creating new chat...", vim.log.levels.INFO)
      -- If not in an activated buffer, use the old behavior (create a new chat)
      local text = ""
      if opts.range > 0 then
        text = utils.get_visual_selection()
      end

      local prompt = opts.args or ""
      local user_input = prompt
      if text ~= "" then
        if prompt ~= "" then
          user_input = prompt .. ":\n" .. text
        else
          user_input = text
        end
      end

      if user_input == "" then
        return M.new_chat()
      else
        return M.new_chat_with_content(user_input)
      end
    end

    -- Check for unexpanded blocks
    local scrape = require('nai.fileutils.scrape')
    local snapshot = require('nai.fileutils.snapshot')

    -- First, check for unexpanded scrape blocks
    if scrape.has_unexpanded_scrape_blocks(buffer_id) then
      -- Handle the case where we have unexpanded scrape blocks
      vim.notify("Expanding scrape blocks. Press <Leader>r again after completion to chat.", vim.log.levels.INFO)

      -- Only expand scrape blocks and return - don't continue with chat
      scrape.expand_scrape_blocks_in_buffer(buffer_id)
      return
    end

    -- Check if there are any active scrape requests still in progress
    if scrape.has_active_requests() then
      vim.notify("Scrape requests are still in progress. Please wait for completion before chatting.",
        vim.log.levels.WARN)
      return
    end

    -- Check for unexpanded snapshot blocks
    if snapshot.has_unexpanded_snapshot_blocks(buffer_id) then
      -- Handle the case where we have unexpanded snapshot blocks
      vim.notify("Expanding snapshot blocks. Press <Leader>r again to chat.", vim.log.levels.INFO)

      -- Process lines in buffer to expand snapshots
      local lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)
      local line_offset = 0

      -- Find and expand snapshot blocks
      for i, line in ipairs(lines) do
        if line == ">>> snapshot" then
          -- This is an unexpanded snapshot
          local block_start = i - 1 + line_offset

          -- Find the end of the snapshot block (next >>> or <<<)
          local block_end = #lines
          for j = i + 1, #lines do
            if lines[j]:match("^>>>") or lines[j]:match("^<<<") then
              block_end = j - 1 + line_offset
              break
            end
          end

          -- Expand the snapshot directly in the buffer
          local new_line_count = snapshot.expand_snapshot_in_buffer(buffer_id, block_start, block_end + 1)

          -- Adjust line offset for any additional lines added
          line_offset = line_offset + (new_line_count - (block_end - block_start + 1))

          -- Re-fetch buffer lines since they've changed
          lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)
        end
      end

      return
    end

    -- Check for unexpanded YouTube blocks
    local youtube = require('nai.fileutils.youtube')
    if youtube.has_unexpanded_youtube_blocks(buffer_id) then
      -- Handle the case where we have unexpanded YouTube blocks
      vim.notify("Expanding YouTube transcript blocks. Press <Leader>r again to chat.", vim.log.levels.INFO)

      -- Process lines in buffer to expand YouTube blocks
      local lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)
      local line_offset = 0

      -- Find and expand YouTube blocks
      for i, line in ipairs(lines) do
        if line == ">>> youtube" then
          -- This is an unexpanded YouTube block
          local block_start = i - 1 + line_offset

          -- Find the end of the YouTube block (next >>> or <<<)
          local block_end = #lines
          for j = i + 1, #lines do
            if lines[j]:match("^>>>") or lines[j]:match("^<<<") then
              block_end = j - 1 + line_offset
              break
            end
          end

          -- Expand the YouTube block directly in the buffer
          local new_line_count = youtube.expand_youtube_block(buffer_id, block_start, block_end + 1)

          -- Adjust line offset for any additional lines added
          line_offset = line_offset + (new_line_count - (block_end - block_start + 1))

          -- Re-fetch buffer lines since they've changed
          lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)
        end
      end

      return
    end

    -- At this point, no unexpanded blocks were found, proceed with chat

    -- Get all buffer content
    local lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)
    local buffer_content = table.concat(lines, "\n")

    -- Check if we need to enable auto-title
    local needs_auto_title = false
    if config.options.chat_files.auto_title then
      -- Look for "title: Untitled" in the YAML header
      for i, line in ipairs(lines) do
        if line:match("^title:%s*Untitled") then
          needs_auto_title = true
          break
        end
        -- Exit the loop if we're past the YAML header
        if line == "---" and i > 1 then
          break
        end
      end
    end

    -- Parse buffer content into messages
    local messages = parser.parse_chat_buffer(buffer_content)

    -- Check if we have a user message at the end
    local last_message = messages[#messages]
    if not last_message or last_message.role ~= "user" then
      -- No user message, add one now
      local user_template = parser.format_user_message("")
      local user_lines = vim.split(user_template, "\n")
      vim.api.nvim_buf_set_lines(buffer_id, -1, -1, false, user_lines)

      -- Position cursor on the 3rd line of new user message (after the blank line)
      local line_count = vim.api.nvim_buf_line_count(buffer_id)
      vim.api.nvim_win_set_cursor(0, { line_count, 0 })

      -- Exit early - user needs to add their message
      vim.notify("Please add your message first, then run NAIChat again", vim.log.levels.INFO)
      return
    end

    -- Position cursor at the end of the buffer
    local line_count = vim.api.nvim_buf_line_count(buffer_id)
    vim.api.nvim_win_set_cursor(0, { line_count, 0 })

    -- Create indicator at the end of buffer
    local indicator = utils.indicators.create_assistant_placeholder(buffer_id, line_count)

    -- Cancel any ongoing requests
    if M.active_request then
      M.cancel()
    end

    -- If we need auto-title, modify the system message
    if needs_auto_title then
      -- Find the system message
      for i, msg in ipairs(messages) do
        if msg.role == "system" then
          -- Append the title request to the system message
          msg.content = parser.get_system_prompt_with_title_request(true)
          break
        end
      end
    end

    -- Call API
    M.active_request = api.chat_request(
      messages,
      function(response)
        -- Get the position where we need to replace the placeholder
        local insertion_row = utils.indicators.remove(indicator)

        -- Extract title if present
        local modified_response = response

        -- Check if response starts with "Proposed Title:"
        local title_match = response:match("^Proposed Title:%s*(.-)[\r\n]")
        if title_match then
          -- Remove the title line from the response
          modified_response = response:gsub("^Proposed Title:%s*.-%s*[\r\n]+", "")

          -- Update the YAML frontmatter if we found a title
          if title_match and title_match:len() > 0 then
            -- Get all buffer content
            local buffer_lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)

            -- Find and update the title line in the YAML header
            for i, line in ipairs(buffer_lines) do
              if line:match("^title:%s*Untitled") then
                buffer_lines[i] = "title: " .. title_match
                vim.api.nvim_buf_set_lines(buffer_id, 0, -1, false, buffer_lines)
                break
              end
            end
          end
        end

        -- Format response and append to buffer
        local formatted_response = parser.format_assistant_message(modified_response)
        local lines_to_append = vim.split(formatted_response, "\n")

        -- Replace the placeholder with the actual content
        local placeholder_height = indicator.end_row - indicator.start_row
        vim.api.nvim_buf_set_lines(
          buffer_id,
          insertion_row,
          insertion_row + placeholder_height,
          false,
          lines_to_append
        )

        -- Add a new user message template if not at the end
        local new_line_count = vim.api.nvim_buf_line_count(buffer_id)
        if new_line_count == insertion_row + #lines_to_append then
          local new_user = parser.format_user_message("")
          vim.api.nvim_buf_set_lines(buffer_id, -1, -1, false, vim.split(new_user, "\n"))
        end

        -- Auto-save if enabled
        if config.options.chat_files.auto_save then
          fileutils.save_chat_buffer(buffer_id)
        end

        -- Move cursor to end safely
        local final_line_count = vim.api.nvim_buf_line_count(buffer_id)
        local safe_pos = math.min(final_line_count, insertion_row + #lines_to_append)
        -- Check if buffer is still valid before setting cursor
        if vim.api.nvim_buf_is_valid(buffer_id) then
          -- Only set cursor if the window is still showing this buffer
          local current_buf = vim.api.nvim_get_current_buf()
          if current_buf == buffer_id then
            vim.api.nvim_win_set_cursor(0, { safe_pos, 0 })
          end
        end

        -- Notify completion
        vim.notify("AI response complete", vim.log.levels.INFO)
        M.active_request = nil
        M.active_indicator = nil
      end,
      function(error_msg)
        -- Handle errors (same as before)
        local insertion_row = utils.indicators.remove(indicator)

        -- Create error message
        local error_lines = {
          "",
          "<<< assistant",
          "",
          "❌ Error: " .. error_msg,
          "",
        }

        -- Replace placeholder with error message
        local placeholder_height = indicator.end_row - indicator.start_row
        vim.api.nvim_buf_set_lines(
          buffer_id,
          insertion_row,
          insertion_row + placeholder_height,
          false,
          error_lines
        )

        -- Show error notification
        vim.notify(error_msg, vim.log.levels.ERROR)
        M.active_request = nil
        M.active_indicator = nil
      end
    )

    -- Store indicator for cancellation
    M.active_indicator = indicator
  end, opts)
end

function M.cancel()
  if M.active_request then
    if vim.system and M.active_request.terminate then
      M.active_request:terminate()
    elseif not vim.system and M.active_request.close then
      M.active_request:close()
    end
    M.active_request = nil

    -- Handle indicator cleanup
    if M.active_indicator then
      if M.active_indicator.legacy then
        -- Handle legacy indicators (the simple virt_text ones)
        utils.indicators.remove_legacy(M.active_indicator)
      else
        -- Get insertion point for replacing with cancellation message
        local buffer_id = M.active_indicator.buffer_id
        local insertion_row = utils.indicators.remove(M.active_indicator)

        -- Create cancelled message
        local cancelled_lines = {
          "",
          "<<< assistant",
          "",
          "⚠️ Request cancelled",
          "",
        }

        -- Replace placeholder with cancelled message
        local placeholder_height = M.active_indicator.end_row - M.active_indicator.start_row
        if vim.api.nvim_buf_is_valid(buffer_id) then
          vim.api.nvim_buf_set_lines(
            buffer_id,
            insertion_row,
            insertion_row + placeholder_height,
            false,
            cancelled_lines
          )
        end
      end

      M.active_indicator = nil
    end

    vim.notify("AI completion cancelled", vim.log.levels.INFO)
  end
end

function M.new_chat()
  local parser = require('nai.parser')
  local fileutils = require('nai.fileutils')

  -- Generate a filename for the untitled chat
  local filename = fileutils.generate_filename("Untitled")

  -- Create new buffer with filename (using .md extension instead of .naichat)
  vim.cmd("enew")
  local buffer_id = vim.api.nvim_get_current_buf()

  -- Make sure the extension is .md instead of .naichat
  local md_filename = filename
  if filename:match("%.naichat$") then
    md_filename = filename:gsub("%.naichat$", ".md")
  end

  -- Set buffer name with both arguments (buffer_id and name)
  vim.api.nvim_buf_set_name(buffer_id, md_filename)

  -- Activate the buffer with our chat functionality
  require('nai.buffer').activate_buffer(buffer_id)

  -- Generate header
  local header = parser.generate_header("Untitled")

  -- Split header and add exactly what we want
  local header_lines = vim.split(header, "\n")

  -- Add user message right after header with exactly one blank line
  table.insert(header_lines, "")         -- One blank line after YAML header
  table.insert(header_lines, ">>> user") -- User prompt
  table.insert(header_lines, "")         -- One blank line after user prompt

  -- Add all lines to the buffer
  vim.api.nvim_buf_set_lines(buffer_id, 0, 0, false, header_lines)

  -- Position cursor where user should start typing
  vim.api.nvim_win_set_cursor(0, { #header_lines, 0 })

  -- Auto-save the empty file if configured
  if config.options.chat_files.auto_save then
    vim.cmd("write")
  end

  -- Notify
  vim.notify("New AI chat file created", vim.log.levels.INFO)

  return buffer_id
end

-- Create a new chat with initial user content
function M.new_chat_with_content(user_input)
  local parser = require('nai.parser')
  local fileutils = require('nai.fileutils')

  -- Create a title from user input
  local title_text = user_input:sub(1, 40) .. (user_input:len() > 40 and "..." or "")
  local filename = fileutils.generate_filename(title_text)

  -- Create new buffer with filename
  vim.cmd("enew")
  vim.api.nvim_buf_set_name(0, filename)
  vim.bo.filetype = "naichat"

  -- Generate header
  local header = parser.generate_header(title_text)
  local header_lines = vim.split(header, "\n")

  -- Add user message right after header with exactly one blank line
  table.insert(header_lines, "")         -- One blank line after YAML header
  table.insert(header_lines, ">>> user") -- User prompt
  table.insert(header_lines, "")         -- One blank line after user prompt
  table.insert(header_lines, user_input) -- User input

  -- Add all lines to the buffer
  vim.api.nvim_buf_set_lines(0, 0, 0, false, header_lines)

  -- Position cursor at the end
  local line_count = vim.api.nvim_buf_line_count(0)
  vim.api.nvim_win_set_cursor(0, { line_count, 0 })

  -- Create indicator with nice placeholder
  local indicator = utils.indicators.create_assistant_placeholder(0, line_count)

  -- Create messages for API
  local is_untitled = title_text:match("Untitled") ~= nil
  local messages = {
    {
      role = "system",
      content = parser.get_system_prompt_with_title_request(is_untitled)
    },
    {
      role = "user",
      content = user_input
    }
  }

  -- Cancel any ongoing requests
  if M.active_request then
    M.cancel()
  end

  -- Call API
  M.active_request = api.chat_request(
    messages,
    function(response)
      -- Get the position where we need to replace the placeholder
      local insertion_row = utils.indicators.remove(indicator)

      -- Format response and append to buffer
      local formatted_response = parser.format_assistant_message(response)
      local lines_to_append = vim.split(formatted_response, "\n")

      -- Replace the placeholder with the actual content
      local placeholder_height = indicator.end_row - indicator.start_row
      vim.api.nvim_buf_set_lines(
        0,
        insertion_row,
        insertion_row + placeholder_height,
        false,
        lines_to_append
      )

      -- Add a new user message template
      local new_user = parser.format_user_message("")
      vim.api.nvim_buf_set_lines(0, -1, -1, false, vim.split(new_user, "\n"))

      -- Save the file
      vim.cmd("write")

      -- Move cursor to end safely
      local new_line_count = vim.api.nvim_buf_line_count(0)
      local safe_pos = math.min(new_line_count, insertion_row + #lines_to_append + 2)

      -- Check if we can safely set the cursor
      local current_buf = vim.api.nvim_get_current_buf()
      if vim.api.nvim_buf_is_valid(current_buf) then
        vim.api.nvim_win_set_cursor(0, { safe_pos, a0 })
      end

      -- Notify completion
      vim.notify("AI chat saved to " .. filename, vim.log.levels.INFO)
      M.active_request = nil
      M.active_indicator = nil
    end,
    function(error_msg)
      -- Handle errors (same as before)
      local insertion_row = utils.indicators.remove(indicator)

      -- Create error message
      local error_lines = {
        "",
        "<<< assistant",
        "",
        "❌ Error: " .. error_msg,
        "",
      }

      -- Replace placeholder with error message
      local placeholder_height = indicator.end_row - indicator.start_row
      vim.api.nvim_buf_set_lines(
        0,
        insertion_row,
        insertion_row + placeholder_height,
        false,
        error_lines
      )

      -- Show error notification
      vim.notify(error_msg, vim.log.levels.ERROR)
      M.active_request = nil
      M.active_indicator = nil
    end
  )

  -- Store indicator for cancellation
  M.active_indicator = indicator
end

return M
