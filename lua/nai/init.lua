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

-- Chat function
function M.chat(opts)
  -- Implementation for chat
  -- Will implement in next iteration
  vim.notify("NAIChat not yet implemented", vim.log.levels.INFO)
end

-- Development helper to reload the plugin
function M.reload()
  -- Clear the module cache for the plugin
  for k in pairs(package.loaded) do
    if k:match("^nai") then
      package.loaded[k] = nil
    end
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
  local parser = require('nai.parser')
  local fileutils = require('nai.fileutils')

  -- Get buffer content
  local buffer_id = vim.api.nvim_get_current_buf()
  local buffer_type = vim.bo.filetype
  local is_chat_buffer = buffer_type == "naichat"

  -- Handle different scenarios:
  -- 1. Opening a new chat with potential selection/text
  -- 2. Continuing an existing chat

  if is_chat_buffer then
    -- Continuing an existing chat
    -- Get all buffer content
    local lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)
    local buffer_content = table.concat(lines, "\n")

    -- Parse buffer content into messages
    local messages = parser.parse_chat_buffer(buffer_content)

    -- Check if we have a user message at the end
    local last_message = messages[#messages]
    if not last_message or last_message.role ~= "user" then
      vim.notify("No user message to respond to", vim.log.levels.WARN)
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
        -- We need to figure out how many lines the placeholder took up
        local placeholder_height = indicator.end_row - indicator.start_row
        vim.api.nvim_buf_set_lines(
          buffer_id,
          insertion_row,
          insertion_row + placeholder_height,
          false,
          lines_to_append
        )

        -- Auto-save if enabled
        if config.options.chat_files.auto_save then
          fileutils.save_chat_buffer(buffer_id)
        end

        -- Move cursor to end
        local new_line_count = vim.api.nvim_buf_line_count(buffer_id)
        vim.api.nvim_win_set_cursor(0, { new_line_count, 0 })

        -- Notify completion
        vim.notify("AI response complete", vim.log.levels.INFO)
        M.active_request = nil
        M.active_indicator = nil
      end,
      function(error_msg)
        -- Get the position where we need to insert the error message
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
  else
    -- Starting a new chat
    -- Get the text from selection or command args
    local text = ""
    if opts.range > 0 then
      text = utils.get_visual_selection()
    end

    -- Get the prompt from command arguments
    local prompt = opts.args or ""

    -- Combine text and prompt
    local user_input = prompt
    if text ~= "" then
      if prompt ~= "" then
        user_input = prompt .. ":\n" .. text
      else
        user_input = text
      end
    end

    -- Don't do anything if no input
    if user_input == "" then
      vim.notify("No input provided", vim.log.levels.WARN)
      return
    end

    -- Create a title from user input
    local title = user_input:sub(1, 40) .. (user_input:len() > 40 and "..." or "")

    -- Generate filename based on title
    local filename = fileutils.generate_filename(title)

    -- Create new buffer with filename
    vim.cmd("enew")
    vim.api.nvim_buf_set_name(0, filename)
    vim.bo.filetype = "naichat"

    -- Generate header
    local header = parser.generate_header(title)
    local header_lines = vim.split(header, "\n")

    -- Add user message right after header with exactly one blank line
    table.insert(header_lines, "")         -- One blank line after YAML header
    table.insert(header_lines, ">>> user") -- User prompt
    table.insert(header_lines, "")         -- One blank line after user prompt
    table.insert(header_lines, user_input) -- User input

    -- Add all lines to the buffer
    vim.api.nvim_buf_set_lines(0, 0, 0, false, header_lines)

    -- Create messages for API
    local messages = {
      {
        role = "system",
        content = config.options.default_system_prompt
      },
      {
        role = "user",
        content = user_input
      }
    }

    -- Position cursor at the end
    local line_count = vim.api.nvim_buf_line_count(0)
    vim.api.nvim_win_set_cursor(0, { line_count, 0 })

    -- Create indicator with nice placeholder
    local indicator = utils.indicators.create_assistant_placeholder(0, line_count)

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

        -- Move cursor to end
        local new_line_count = vim.api.nvim_buf_line_count(0)
        vim.api.nvim_win_set_cursor(0, { new_line_count - 1, 0 })

        -- Notify completion
        vim.notify("AI chat saved to " .. filename, vim.log.levels.INFO)
        M.active_request = nil
        M.active_indicator = nil
      end,
      function(error_msg)
        -- Get the position where we need to insert the error message
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

  -- Create new buffer with filename
  vim.cmd("enew")
  vim.api.nvim_buf_set_name(0, filename)
  vim.bo.filetype = "naichat"

  -- Generate header
  local header = parser.generate_header("Untitled")

  -- Split header and add exactly what we want
  local header_lines = vim.split(header, "\n")

  -- Add user message right after header with exactly one blank line
  table.insert(header_lines, "")         -- One blank line after YAML header
  table.insert(header_lines, ">>> user") -- User prompt
  table.insert(header_lines, "")         -- One blank line after user prompt

  -- Add all lines to the buffer
  vim.api.nvim_buf_set_lines(0, 0, 0, false, header_lines)

  -- Position cursor where user should start typing
  vim.api.nvim_win_set_cursor(0, { #header_lines, 0 })

  -- Auto-save the empty file if configured
  if config.options.chat_files.auto_save then
    vim.cmd("write")
  end

  -- Notify
  vim.notify("New AI chat file created", vim.log.levels.INFO)
end

return M
