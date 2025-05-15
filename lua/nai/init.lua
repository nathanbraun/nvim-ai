-- lua/nai/init.lua
-- Main module for nvim-ai plugin

local M = {}
local config = require('nai.config')
local api = require('nai.api')
local utils = require('nai.utils')
local error_utils = require('nai.utils.error')

local function check_platform_compatibility()
  local path = require('nai.utils.path')

  -- Check for platform-specific issues
  if path.is_windows then
    -- Check for long path support on Windows
    local long_paths_enabled = vim.fn.system(
      'powershell -Command "[System.Environment]::GetEnvironmentVariable(\'USERDNSDOMAIN\', \'Process\') -ne $null"')

    if vim.trim(long_paths_enabled) ~= "True" then
      vim.notify("Windows: Long path support may not be enabled. Some file operations might fail with long paths.",
        vim.log.levels.WARN)
    end

    -- Check for curl on Windows
    if vim.fn.executable('curl') ~= 1 and vim.fn.executable('curl.exe') ~= 1 then
      vim.notify("Windows: curl not found in PATH. Please install curl for API requests to work.", vim.log.levels.ERROR)
    end
  end
end

local function check_dependencies()
  local has_curl = error_utils.check_executable("curl", "Please install curl for API requests")

  -- These are optional but good to check
  error_utils.check_executable("html2text", "Install for better web content formatting")

  if not has_curl then
    error_utils.log("nvim-ai may not function correctly without required dependencies", error_utils.LEVELS.WARNING)
  end
end

-- Setup function that should be called by the user
function M.setup(opts)
  config.setup(opts)
  require('nai.mappings').setup(opts)

  -- Check dependencies
  check_dependencies()

  -- Check platform compatibility
  check_platform_compatibility()

  -- Check if API key is configured for the active provider
  local provider = config.options.active_provider
  local api_key = config.get_api_key(provider)

  if not api_key then
    vim.defer_fn(function()
      vim.notify(
        "No API key found for " .. provider .. ".\n" ..
        "Please set your API key with :NAISetKey " .. provider,
        vim.log.levels.WARN
      )
    end, 1000) -- Delay to ensure it's seen after startup
  end

  -- Additional setup if needed
  return M
end

-- Development helper to reload the plugin
function M.reload()
  -- Clear the module cache for the plugin
  for k in pairs(package.loaded) do
    if k:match("^nai") then
      package.loaded[k] = nil
    end
  end

  local state = require('nai.state') -- Add this line
  local current_buf = vim.api.nvim_get_current_buf()
  if state.is_buffer_activated(buffer_id) then
    require('nai.buffer').apply_syntax_overlay(current_buf)
  end

  -- Reload the main module
  return require("nai")
end

-- Function to switch between providers
function M.switch_provider(provider)
  if provider ~= "openai" and provider ~= "openrouter" and provider ~= "ollama" then
    vim.notify("Invalid provider. Use 'openai', 'openrouter', or 'ollama'", vim.log.levels.ERROR)
    return
  end

  local config = require('nai.config')
  config.options.active_provider = provider

  -- Update state
  require('nai.state').set_current_provider(provider)

  -- If switching to Ollama, ensure the model is valid
  if provider == "ollama" then
    config.ensure_valid_ollama_model(config.options.providers.ollama)
  end

  vim.notify("Switched to " .. provider .. " provider", vim.log.levels.INFO)
end

function M.chat(opts, force_signature)
  local parser = require('nai.parser')
  local fileutils = require('nai.fileutils')
  local buffer_id = vim.api.nvim_get_current_buf()
  local buffer_module = require('nai.buffer')
  local state = require('nai.state') -- Add this line

  -- Force activation for this buffer if it contains user prompts
  local contains_chat_markers = buffer_module.detect_chat_markers(buffer_id)
  if contains_chat_markers and not state.is_buffer_activated(buffer_id) then
    vim.notify("Found chat markers, activating buffer...", vim.log.levels.INFO)
    buffer_module.activate_buffer(buffer_id)
  end

  -- Check if buffer is activated after our attempt
  if not state.is_buffer_activated(buffer_id) then
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

  -- Try to expand blocks first
  local expanded = M.expand_blocks(buffer_id)

  -- If blocks were expanded or are being processed, don't continue with chat
  if expanded then
    return
  end

  -- At this point, no unexpanded blocks were found, proceed with chat

  -- Get all buffer content
  local lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)
  local buffer_content = table.concat(lines, "\n")

  -- Parse buffer content into messages
  local messages, chat_config = parser.parse_chat_buffer(buffer_content, buffer_id)

  local should_expand_placeholders

  -- Check if expand_placeholders is explicitly set in chat_config
  if chat_config and chat_config.expand_placeholders ~= nil then
    -- Use the chat-specific setting
    should_expand_placeholders = chat_config.expand_placeholders
  else
    -- Fall back to global setting
    should_expand_placeholders = config.options.expand_placeholders
  end

  if should_expand_placeholders then
    if messages then
      for _, msg in ipairs(messages) do
        if msg.content and type(msg.content) == "string" then
          msg.content = parser.replace_placeholders(msg.content, buffer_id)
        end
      end
    end
  end

  local needs_auto_title = false

  if config.options.debug.auto_title then
    vim.notify("needs_auto_title" .. tostring(needs_auto_title), vim.log.levels.DEBUG)
  end

  if config.options.chat_files.auto_title then
    -- Check if there's a user-provided system message (not the default one)
    local has_user_system_message = false
    for i, line in ipairs(lines) do
      if line:match("^>>> system$") then
        -- Found a user-provided system message marker
        has_user_system_message = true
        break
      end
    end

    if config.options.debug.auto_title then
      vim.notify("has_user_system_message" .. tostring(has_user_system_message), vim.log.levels.DEBUG)
    end

    -- Only enable auto-title if there's no user-provided system message
    if not has_user_system_message then
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
      if config.options.debug.auto_title then
        vim.notify("needs_auto_title" .. tostring(needs_auto_title), vim.log.levels.DEBUG)
      end
    end
  end

  -- Then use throughout code:
  if config.options.debug.auto_title then
    vim.notify("needs_auto_title" .. tostring(needs_auto_title), vim.log.levels.DEBUG)
  end

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

  -- Register the indicator in state
  local state = require('nai.state')
  local indicator_id = "indicator_" .. buffer_id .. "_" .. line_count
  state.register_indicator(indicator_id, indicator)

  -- Update the indicator with the model from chat_config if available
  if chat_config and chat_config.model then
    utils.indicators.update_stats(indicator, {
      model = chat_config.model
    })
  end

  -- Cancel any ongoing requests
  if state.has_active_requests() then
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
  local request_handle = api.chat_request(
    messages,
    function(response)
      -- Get the position where we need to replace the placeholder
      local insertion_row = utils.indicators.remove(indicator)

      -- Clear indicator from state
      state.clear_indicator(indicator_id)

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

      -- Apply formatting if enabled
      if config.options.format_response and config.options.format_response.enabled then
        modified_response = utils.format_with_gq(
          modified_response,
          config.options.format_response.wrap_width
        )
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

      -- Add our verification code right after this:
      -- Add verification signature if enabled
      local verification = require('nai.verification')
      verification.add_signature_after_response(buffer_id, insertion_row + #lines_to_append, messages, modified_response,
        force_signature)

      local is_new_chat = #messages <= 3 -- System message + 1 user message + 1 assistant message

      local new_line_count = vim.api.nvim_buf_line_count(buffer_id)
      local new_user = parser.format_user_message("")
      vim.api.nvim_buf_set_lines(buffer_id, -1, -1, false, vim.split(new_user, "\n"))

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
    end,
    function(error_msg)
      -- Handle errors (same as before)
      local insertion_row = utils.indicators.remove(indicator)

      -- Clear indicator from state
      state.clear_indicator(indicator_id)

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
    end,
    chat_config
  )

  return request_handle
end

function M.cancel()
  local state = require('nai.state')

  -- Get all active requests from state
  local active_requests = state.get_active_requests()
  local request_count = vim.tbl_count(active_requests)

  for request_id, request_data in pairs(active_requests) do
    -- Cancel the request
    api.cancel_request({ request_id = request_id })

    -- Explicitly clear the request from state
    state.clear_request(request_id)
  end

  -- Handle indicators
  for indicator_id, indicator in pairs(state.active_indicators) do
    -- Stop the timer if it exists
    if indicator.timer then
      indicator.timer:stop()
      indicator.timer:close()
    end

    -- Check if buffer is valid
    if vim.api.nvim_buf_is_valid(indicator.buffer_id) then
      -- Get the end row of the indicator
      local end_row = indicator.end_row

      -- Add a new line right after the indicator
      vim.api.nvim_buf_set_lines(
        indicator.buffer_id,
        end_row,
        end_row,
        false,
        { "CANCELLED BY USER" }
      )

      -- Force redraw
      vim.cmd("redraw")
    end

    -- Clear indicator from state
    state.clear_indicator(indicator_id)
  end

  -- Reset the active_request variable directly
  M.active_request = nil
  M.active_indicator = nil

  if request_count > 0 then
    vim.notify("AI completion cancelled", vim.log.levels.INFO)
  else
    vim.notify("No active AI requests to cancel", vim.log.levels.INFO)
  end

  -- Force a complete state reset to ensure we can start fresh
  state.reset_processing_state()
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

  -- Trigger filetype detection based on the filename
  vim.cmd("doautocmd BufRead " .. vim.fn.fnameescape(md_filename))

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
        vim.api.nvim_win_set_cursor(0, { safe_pos, 0 })
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

function M.expand_blocks(buffer_id)
  buffer_id = buffer_id or vim.api.nvim_get_current_buf()
  local buffer_module = require('nai.buffer')
  local constants = require('nai.constants')

  -- Debug info
  if config.options.debug and config.options.debug.enabled then
    vim.notify("DEBUG: expand_blocks called for buffer: " .. buffer_id, vim.log.levels.DEBUG)
  end

  -- Check if buffer is activated
  local state = require('nai.state')
  if not state.is_buffer_activated(buffer_id) then
    vim.notify("Buffer not activated for nvim-ai", vim.log.levels.INFO)
    return false
  end

  -- Track if any blocks were expanded
  local expanded_something = false

  -- Get all buffer content
  local lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)

  -- Check for unexpanded scrape blocks
  local scrape = require('nai.fileutils.scrape')
  if scrape.has_unexpanded_scrape_blocks(buffer_id) then
    if config.options.debug and config.options.debug.enabled then
      vim.notify("DEBUG: Found unexpanded scrape blocks", vim.log.levels.DEBUG)
    end

    local line_offset = 0

    -- Find and expand scrape blocks
    for i, line in ipairs(lines) do
      local actual_line_num = i - 1 + line_offset

      if line:match("^>>> scrape$") then
        -- This is a scrape block
        local block_start = actual_line_num

        -- Find the end of the scrape block (next >>> or <<<)
        local block_end = #lines
        for j = i + 1, #lines do
          local j_line_num = j - 1 + line_offset
          if (lines[j]:match("^>>>") or lines[j]:match("^<<<")) then
            block_end = j_line_num
            break
          end
        end

        -- Expand the scrape block directly in the buffer
        local new_line_count = scrape.expand_scrape_block(buffer_id, block_start, block_end + 1)

        -- Adjust line offset for any additional lines added
        line_offset = line_offset + (new_line_count - (block_end - block_start + 1))

        -- Re-fetch buffer lines since they've changed
        lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)
      end
    end

    expanded_something = true
  end

  -- Check if there are any active scrape requests still in progress
  if scrape.has_active_requests() then
    vim.notify("Scrape requests are still in progress", vim.log.levels.INFO)
    return true -- Return true to indicate we're handling something, but not fully expanded yet
  end

  -- Check for unexpanded snapshot blocks
  local snapshot = require('nai.fileutils.snapshot')
  if snapshot.has_unexpanded_snapshot_blocks(buffer_id) then
    -- Process lines in buffer to expand snapshots

    local line_offset = 0

    -- Find and expand snapshot blocks
    for i, line in ipairs(lines) do
      local actual_line_num = i - 1 + line_offset

      if vim.trim(line) == ">>> snapshot" then
        -- This is an unexpanded snapshot
        local block_start = actual_line_num

        -- Find the end of the snapshot block (next >>> or <<<)
        local block_end = #lines
        for j = i + 1, #lines do
          local j_line_num = j - 1 + line_offset
          if (lines[j]:match("^>>>") or lines[j]:match("^<<<")) then
            block_end = j_line_num
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

    expanded_something = true
  end

  -- Check for unexpanded YouTube blocks
  local youtube = require('nai.fileutils.youtube')
  if youtube.has_unexpanded_youtube_blocks(buffer_id) then

    -- Process lines in buffer to expand YouTube blocks
    local line_offset = 0

    -- Find and expand YouTube blocks
    for i, line in ipairs(lines) do
      local actual_line_num = i - 1 + line_offset

      if line == ">>> youtube" then
        -- This is an unexpanded YouTube block
        local block_start = actual_line_num

        -- Find the end of the YouTube block (next >>> or <<<)
        local block_end = #lines
        for j = i + 1, #lines do
          local j_line_num = j - 1 + line_offset
          if (lines[j]:match("^>>>") or lines[j]:match("^<<<")) then
            block_end = j_line_num
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

    expanded_something = true
  end

  -- Check for unexpanded tree blocks
  local tree = require('nai.fileutils.tree')
  if tree.has_unexpanded_tree_blocks(buffer_id) then

    -- Keep expanding tree blocks until none are left
    while tree.has_unexpanded_tree_blocks(buffer_id) do
      -- Get all lines in the buffer
      local lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)

      -- Find the first unexpanded tree block
      local block_start = nil
      local block_end = nil

      for i, line in ipairs(lines) do
        if line == ">>> tree" then
          block_start = i - 1

          -- Find the end of the block
          block_end = #lines - 1
          for j = i + 1, #lines do
            if lines[j]:match("^>>>") or lines[j]:match("^<<<") then
              block_end = j - 2
              break
            end
          end

          break -- Found the first block, stop searching
        end
      end

      if block_start ~= nil then
        -- Expand this tree block
        tree.expand_tree_in_buffer(buffer_id, block_start, block_end + 1)
      else
        -- No more tree blocks found, break the loop
        break
      end
    end

    expanded_something = true
  end

  -- Check for unexpanded crawl blocks
  local crawl = require('nai.fileutils.crawl')
  if crawl.has_unexpanded_crawl_blocks(buffer_id) then

    -- Process lines in buffer to expand crawl blocks
    local line_offset = 0

    -- Find and expand crawl blocks
    for i, line in ipairs(lines) do
      local actual_line_num = i - 1 + line_offset

      if line == ">>> crawl" then
        -- This is an unexpanded crawl block
        local block_start = actual_line_num

        -- Find the end of the crawl block (next >>> or <<<)
        local block_end = #lines
        for j = i + 1, #lines do
          local j_line_num = j - 1 + line_offset
          if (lines[j]:match("^>>>") or lines[j]:match("^<<<")) then
            block_end = j_line_num
            break
          end
        end

        -- Expand the crawl block directly in the buffer
        local new_line_count = crawl.expand_crawl_block(buffer_id, block_start, block_end + 1)

        -- Adjust line offset for any additional lines added
        line_offset = line_offset + (new_line_count - (block_end - block_start + 1))

        -- Re-fetch buffer lines since they've changed
        lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)
      end
    end

    expanded_something = true
  end

  -- Check if there are any active crawl requests still in progress
  if crawl.has_active_requests() then
    vim.notify("Crawl requests are still in progress", vim.log.levels.INFO)
    return true -- Return true to indicate we're handling something, but not fully expanded yet
  end

  return expanded_something
end

function M.expand_blocks_command()
  local expanded = M.expand_blocks()

  if not expanded then
    vim.notify("No expandable blocks found", vim.log.levels.INFO)
  end
end

function M.run_tests()
  return require('nai.tests').run_all()
end

return M
