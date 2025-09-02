local M = {}
local config = require('nai.config')
local api = require('nai.api')
local utils = require('nai.utils')
local error_utils = require('nai.utils.error')
local parser = require('nai.parser')
local fileutils = require('nai.fileutils')
local buffer_module = require('nai.buffer')
local state = require('nai.state')
local verification = require('nai.verification')

-- Platform compatibility and dependency checks
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

  local current_buf = vim.api.nvim_get_current_buf()
  if state.is_buffer_activated(current_buf) then
    buffer_module.apply_syntax_overlay(current_buf)
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

  config.options.active_provider = provider

  -- Update state
  state.set_current_provider(provider)

  -- If switching to Ollama, ensure the model is valid
  if provider == "ollama" then
    config.ensure_valid_ollama_model(config.options.providers.ollama)
  end

  vim.notify("Switched to " .. provider .. " provider", vim.log.levels.INFO)
end

-- REFACTORED CHAT FUNCTIONS

-- Helper function to create a chat buffer and set it up
local function initialize_chat_buffer(title, filename)
  -- Generate a filename for the chat if not provided
  if not filename then
    filename = fileutils.generate_filename(title or "Untitled")

    -- Make sure the extension is .md instead of .naichat
    if filename:match("%.naichat$") then
      filename = filename:gsub("%.naichat$", ".md")
    end
  end

  -- Create new buffer
  vim.cmd("enew")
  local buffer_id = vim.api.nvim_get_current_buf()

  -- Set buffer name
  vim.api.nvim_buf_set_name(buffer_id, filename)

  -- Generate and add header
  local header = parser.generate_header(title or "Untitled")
  local header_lines = vim.split(header, "\n")

  -- Add all lines to the buffer
  vim.api.nvim_buf_set_lines(buffer_id, 0, 0, false, header_lines)

  -- Set filetype explicitly to markdown
  vim.api.nvim_buf_set_option(buffer_id, "filetype", "markdown")

  -- Trigger filetype detection based on the filename
  -- Only do this after content is added
  vim.cmd("doautocmd BufRead " .. vim.fn.fnameescape(filename))

  -- Activate the buffer with chat functionality after content is added
  buffer_module.activate_buffer(buffer_id)

  return buffer_id, filename
end

-- Helper function to add a user message to a buffer
local function add_user_message_to_buffer(buffer_id, user_content)
  local lines = {}

  table.insert(lines, "")         -- One blank line
  table.insert(lines, ">>> user") -- User prompt
  table.insert(lines, "")         -- One blank line

  if user_content and user_content ~= "" then
    -- Add user content, handling multi-line content
    local content_lines = vim.split(user_content, "\n")
    for _, line in ipairs(content_lines) do
      table.insert(lines, line)
    end
  end

  -- Add lines to the end of the buffer
  vim.api.nvim_buf_set_lines(buffer_id, -1, -1, false, lines)

  -- Position cursor at the end
  local line_count = vim.api.nvim_buf_line_count(buffer_id)
  vim.api.nvim_win_set_cursor(0, { line_count, 0 })

  return #lines
end

-- Helper function to create an indicator and send a chat request
local function send_chat_request(buffer_id, messages, chat_config, force_signature)
  local line_count = vim.api.nvim_buf_line_count(buffer_id)

  -- Create indicator at the end of buffer
  local indicator = utils.indicators.create_assistant_placeholder(buffer_id, line_count)

  -- Register the indicator in state
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

  -- Create success callback
  local on_success = function(response)
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

    -- Add verification signature if enabled
    verification.add_signature_after_response(
      buffer_id,
      insertion_row + #lines_to_append,
      messages,
      modified_response,
      force_signature
    )

    -- Add a new user message template
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
  end

  -- Create error callback
  local on_error = function(error_msg)
    -- Get the position where we need to replace the placeholder
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
  end

  -- Call API
  local request_handle = api.chat_request(
    messages,
    on_success,
    on_error,
    chat_config
  )

  return request_handle, indicator
end

-- Helper function to detect if we need automatic title generation
local function needs_auto_title(lines)
  if not config.options.chat_files.auto_title then
    return false
  end

  -- Check if there's a user-provided system message (not the default one)
  local has_user_system_message = false
  for _, line in ipairs(lines) do
    if line:match("^>>> system$") then
      has_user_system_message = true
      break
    end
  end

  if has_user_system_message then
    return false
  end

  -- Look for "title: Untitled" in the YAML header
  for i, line in ipairs(lines) do
    if line:match("^title:%s*Untitled") then
      return true
    end
    -- Exit the loop if we're past the YAML header
    if line == "---" and i > 1 then
      break
    end
  end

  return false
end

-- Function to process special blocks (scrape, snapshot, etc)
function M.expand_blocks(buffer_id)
  buffer_id = buffer_id or vim.api.nvim_get_current_buf()

  -- Debug info
  if config.options.debug and config.options.debug.enabled then
    vim.notify("DEBUG: expand_blocks called for buffer: " .. buffer_id, vim.log.levels.DEBUG)
  end

  -- Check if buffer is activated
  if not state.is_buffer_activated(buffer_id) then
    vim.notify("Buffer not activated for nvim-ai", vim.log.levels.INFO)
    return false
  end

  -- Track if any blocks were expanded
  local expanded_something = false

  -- Get all buffer content
  local lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)

  -- Process different block types
  local block_processors = {
    {
      module = require('nai.fileutils.scrape'),
      has_unexpanded = 'has_unexpanded_scrape_blocks',
      expand = 'expand_scrape_block',
      marker = "^>>> scrape$",
      has_active = 'has_active_requests'
    },
    {
      module = require('nai.fileutils.snapshot'),
      has_unexpanded = 'has_unexpanded_snapshot_blocks',
      expand = 'expand_snapshot_in_buffer',
      marker = "^>>> snapshot$"
    },
    {
      module = require('nai.fileutils.youtube'),
      has_unexpanded = 'has_unexpanded_youtube_blocks',
      expand = 'expand_youtube_block',
      marker = "^>>> youtube$"
    },
    {
      module = require('nai.fileutils.tree'),
      has_unexpanded = 'has_unexpanded_tree_blocks',
      expand = 'expand_tree_in_buffer',
      marker = "^>>> tree$"
    },
    {
      module = require('nai.fileutils.crawl'),
      has_unexpanded = 'has_unexpanded_crawl_blocks',
      expand = 'expand_crawl_block',
      marker = "^>>> crawl$",
      has_active = 'has_active_requests'
    },
    {
      module = M, -- Using the main module since we added the functions there
      has_unexpanded = 'has_unexpanded_summary_blocks',
      expand = 'expand_summary_in_buffer',
      marker = "^>>> summar" -- This will match both "summary" and "summarize"
    },
    {
      module = M,
      has_unexpanded = 'has_unexpanded_file_summary_blocks',
      expand = 'expand_file_summary_block',
      marker = "^>>> file%-summary$"
    },
  }

  -- Process each block type
  for _, processor in ipairs(block_processors) do
    if processor.module and processor.module[processor.has_unexpanded] and
        processor.module[processor.has_unexpanded](buffer_id) then
      local line_offset = 0

      -- Find and expand blocks
      for i, line in ipairs(lines) do
        local actual_line_num = i - 1 + line_offset

        -- Special handling for summary blocks to match both "summary" and "summarize"
        local is_summary_block = processor.marker == "^>>> summar" and
            (line:match("^>>> summary") or line:match("^>>> summarize"))

        if is_summary_block or (not is_summary_block and line:match(processor.marker)) then
          -- This is an unexpanded block
          local block_start = actual_line_num

          -- Find the end of the block (next >>> or <<<)
          local block_end = #lines
          for j = i + 1, #lines do
            local j_line_num = j - 1 + line_offset
            if (lines[j]:match("^>>>") or lines[j]:match("^<<<")) then
              block_end = j_line_num
              break
            end
          end

          -- For summary blocks, use our specialized function
          if is_summary_block then
            -- Special handling for summary blocks
            M.summarize_conversation({
              buffer_id = buffer_id,
              insert_at_line = block_start,
              is_block_expansion = true
            })

            -- Since this is async, we'll just add a small offset and continue
            line_offset = line_offset + 5
          else
            -- Expand other block types normally
            local new_line_count = processor.module[processor.expand](buffer_id, block_start, block_end + 1)

            -- Adjust line offset for any additional lines added
            line_offset = line_offset + (new_line_count - (block_end - block_start + 1))
          end

          -- Re-fetch buffer lines since they've changed
          lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)
        end
      end

      expanded_something = true
    end

    -- Check if there are any active requests still in progress
    if processor.has_active and processor.module[processor.has_active]() then
      vim.notify(processor.marker:gsub("^>>> ", ""):gsub("$", "") .. " requests are still in progress",
        vim.log.levels.INFO)
      return true -- Return true to indicate we're handling something, but not fully expanded yet
    end
  end

  return expanded_something
end

-- Main chat function - handles both new and existing chats
function M.chat(opts, force_signature)
  local buffer_id = vim.api.nvim_get_current_buf()

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

  -- Handle placeholder expansion
  local should_expand_placeholders = (chat_config and chat_config.expand_placeholders ~= nil)
      and chat_config.expand_placeholders
      or config.options.expand_placeholders

  if should_expand_placeholders then
    if messages then
      for _, msg in ipairs(messages) do
        if msg.content and type(msg.content) == "string" then
          msg.content = parser.replace_placeholders(msg.content, buffer_id)
        end
      end
    end
  end

  -- Check if we need auto title
  local auto_title_needed = needs_auto_title(lines)

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

  -- If we need auto-title, modify the system message
  if auto_title_needed then
    -- Find the system message
    for i, msg in ipairs(messages) do
      if msg.role == "system" then
        -- Append the title request to the system message
        msg.content = parser.get_system_prompt_with_title_request(true)
        break
      end
    end
  end

  -- Send the chat request
  return send_chat_request(buffer_id, messages, chat_config, force_signature)
end

-- Create a new empty chat buffer
function M.new_chat()
  -- Initialize a new chat buffer
  local buffer_id = initialize_chat_buffer("Untitled")

  -- Add empty user message
  add_user_message_to_buffer(buffer_id, "")

  -- Position cursor where user should start typing
  local line_count = vim.api.nvim_buf_line_count(buffer_id)
  vim.api.nvim_win_set_cursor(0, { line_count, 0 })

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
  -- Create a title from user input
  local title_text = user_input:sub(1, 40) .. (user_input:len() > 40 and "..." or "")

  -- Initialize a new chat buffer with the title
  local buffer_id = initialize_chat_buffer(title_text)

  -- Add user message with content
  add_user_message_to_buffer(buffer_id, user_input)

  -- Position cursor at the end
  local line_count = vim.api.nvim_buf_line_count(buffer_id)
  vim.api.nvim_win_set_cursor(0, { line_count, 0 })

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

  -- Send the chat request
  return send_chat_request(buffer_id, messages)
end

function M.summarize_conversation(opts)
  opts = opts or {}
  local buffer_id = opts.buffer_id or vim.api.nvim_get_current_buf()
  local insert_at_line = opts.insert_at_line -- If nil, will be determined later
  local is_block_expansion = opts.is_block_expansion or false

  -- Ensure we're in an activated buffer
  if not state.is_buffer_activated(buffer_id) then
    vim.notify("Cannot summarize: Not in an AI conversation buffer", vim.log.levels.ERROR)
    return
  end

  -- Get all buffer content
  local lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)
  local buffer_content = table.concat(lines, "\n")

  -- If insert_at_line is not provided, check if we're expanding a block
  if not insert_at_line then
    -- Look for a ">>> summary" or ">>> summarize" marker
    for i, line in ipairs(lines) do
      if line:match("^>>> summary$") or line:match("^>>> summarize$") then
        insert_at_line = i - 1 -- Convert to 0-based index
        break
      end
    end

    -- If still not found, insert at the end
    if not insert_at_line then
      insert_at_line = #lines
    end
  end

  -- Parse buffer content into messages
  local messages, _ = parser.parse_chat_buffer(buffer_content, buffer_id)

  -- Check if we have enough messages to summarize
  if #messages < 3 then -- At least system + user + assistant
    vim.notify("Not enough conversation to summarize", vim.log.levels.WARN)
    return
  end

  -- Create summarization request
  local summary_config = {
    provider = config.options.summary.provider or config.options.active_provider,
    model = config.options.summary.model or config.options.active_model,
    temperature = config.options.summary.temperature,
    max_tokens = config.options.summary.max_tokens
  }

  -- Create a system message for the summary
  local system_message = {
    role = "system",
    content = config.options.summary.prompt
  }

  -- Create a user message containing the conversation to summarize
  local conversation_text = {}
  for i, msg in ipairs(messages) do
    if msg.role == "system" then
      table.insert(conversation_text, "SYSTEM: " .. msg.content)
    elseif msg.role == "user" then
      table.insert(conversation_text, "USER: " .. msg.content)
    elseif msg.role == "assistant" then
      table.insert(conversation_text, "ASSISTANT: " .. msg.content)
    end
  end

  local user_message = {
    role = "user",
    content = table.concat(conversation_text, "\n\n")
  }

  -- Create summary messages
  local summary_messages = { system_message, user_message }

  -- If we're expanding a block, replace it with the summary marker
  if is_block_expansion then
    -- Clear the existing block
    vim.api.nvim_buf_set_lines(buffer_id, insert_at_line, insert_at_line + 1, false, { ">>> summary" })
    insert_at_line = insert_at_line + 1
  else
    -- Add summary marker if not already there
    if not lines[insert_at_line + 1] or not lines[insert_at_line + 1]:match("^>>> summar") then
      vim.api.nvim_buf_set_lines(buffer_id, insert_at_line, insert_at_line, false, { "", ">>> summary", "" })
      insert_at_line = insert_at_line + 3
    else
      -- Skip past the marker and any blank line after it
      insert_at_line = insert_at_line + 1
      if insert_at_line < #lines and lines[insert_at_line + 1] == "" then
        insert_at_line = insert_at_line + 1
      end
    end
  end

  -- Create indicator
  local indicator = utils.indicators.create_assistant_placeholder(buffer_id, insert_at_line)

  -- Register the indicator in state
  local indicator_id = "summary_indicator_" .. buffer_id .. "_" .. insert_at_line
  state.register_indicator(indicator_id, indicator)

  -- Update the indicator with the model information
  utils.indicators.update_stats(indicator, {
    model = summary_config.model
  })

  -- Create success callback
  local on_success = function(response)
    -- Get the position where we need to replace the placeholder
    local insertion_row = utils.indicators.remove(indicator)

    -- Clear indicator from state
    state.clear_indicator(indicator_id)

    -- Prepare the summary content with a marker
    local content_marker = "<<< content [" .. os.date("%Y-%m-%d %H:%M:%S") .. "]"
    local summary_lines = vim.split(response, "\n")

    -- Insert the content marker followed by the summary
    local result_lines = { content_marker, "" }
    for _, line in ipairs(summary_lines) do
      table.insert(result_lines, line)
    end

    -- Replace the placeholder with the actual content
    local placeholder_height = indicator.end_row - indicator.start_row
    vim.api.nvim_buf_set_lines(
      buffer_id,
      insertion_row,
      insertion_row + placeholder_height,
      false,
      result_lines
    )

    -- Explicitly notify completion
    vim.api.nvim_out_write("Conversation summarization complete\n")
    vim.notify("Conversation summarization complete", vim.log.levels.INFO)
  end

  -- Create error callback
  local on_error = function(error_msg)
    -- Get the position where we need to replace the placeholder
    local insertion_row = utils.indicators.remove(indicator)

    -- Clear indicator from state
    state.clear_indicator(indicator_id)

    -- Create error message
    local error_lines = {
      "❌ Error generating summary: " .. error_msg
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
    vim.notify("Failed to generate summary: " .. error_msg, vim.log.levels.ERROR)
  end

  -- Call API with explicit debug output
  vim.api.nvim_out_write("Sending summary request...\n")
  api.chat_request(
    summary_messages,
    function(response)
      vim.api.nvim_out_write("Summary response received\n")
      on_success(response)
    end,
    function(error_msg)
      vim.api.nvim_out_write("Summary error: " .. error_msg .. "\n")
      on_error(error_msg)
    end,
    summary_config
  )

  vim.api.nvim_out_write("Summary request sent\n")
end

-- Cancel any ongoing requests
function M.cancel()
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

-- Command wrapper for expand_blocks
function M.expand_blocks_command()
  local expanded = M.expand_blocks()

  if not expanded then
    vim.notify("No expandable blocks found", vim.log.levels.INFO)
  end
end

function M.has_unexpanded_summary_blocks(buffer_id)
  buffer_id = buffer_id or vim.api.nvim_get_current_buf()

  -- Get all buffer content
  local lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)

  for i, line in ipairs(lines) do
    if line:match("^>>> summary$") or line:match("^>>> summarize$") then
      -- Check if we're at the end of the buffer
      if i == #lines then
        return true
      end

      -- Check if the next line is empty and it's the last line
      if i + 1 == #lines and lines[i + 1] == "" then
        return true
      end

      -- Look for any content after the summary marker
      local has_content = false
      for j = i + 1, #lines do
        -- If we find any non-empty line that's not a block marker, consider it has content
        if lines[j] ~= "" then
          has_content = true
          break
        end
      end

      -- If there's no content after the summary marker, it needs expansion
      if not has_content then
        return true
      end
    end
  end

  return false
end

-- Expand a summary block in the buffer
function M.expand_summary_in_buffer(buffer_id, block_start, block_end)
  buffer_id = buffer_id or vim.api.nvim_get_current_buf()

  -- Debug info
  if config.options.debug and config.options.debug.enabled then
    vim.notify("DEBUG: Expanding summary block", vim.log.levels.DEBUG)
  end

  -- Get the block content
  local block_lines = vim.api.nvim_buf_get_lines(buffer_id, block_start, block_end, false)

  -- Check if there's already content after the summary marker
  for i = 2, #block_lines do
    if block_lines[i] ~= "" then
      -- If there's already content, don't expand again
      return block_end - block_start
    end
  end

  -- Trigger the summarize function
  M.summarize_conversation({
    buffer_id = buffer_id,
    insert_at_line = block_start,
    is_block_expansion = true
  })

  -- Since summarize_conversation is asynchronous, we can't know the exact new line count
  -- We'll return a conservative estimate
  return (block_end - block_start) + 5 -- Assuming summary adds at least 5 lines
end

-- Function to open a file picker and insert a file summary block
function M.insert_file_summary_block()
  -- Get current buffer and cursor position
  local buffer_id = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1 -- Convert to 0-based index

  -- Insert the file-summary marker at cursor position
  local lines = {
    ">>> file-summary",
    ""
  }
  vim.api.nvim_buf_set_lines(buffer_id, row, row, false, lines)

  -- Move cursor to the empty line after the marker
  vim.api.nvim_win_set_cursor(0, { row + 2, 0 })

  -- Use the existing picker module to browse files
  local picker = require('nai.tools.picker')

  -- Override the file browser callbacks to insert file paths instead of opening files
  local original_telescope = picker.show_file_browser_telescope
  local original_snacks = picker.show_file_browser_snacks
  local original_fzf_lua = picker.show_file_browser_fzf_lua
  local original_simple = picker.show_file_browser_simple

  -- Override Snacks implementation with proper multi-select support
  picker.show_file_browser_snacks = function(items)
    local Snacks = require('snacks')
    local snacks_picker = require("snacks.picker")

    -- Format items for the snacks picker
    local formatted_items = {}
    for i, item in ipairs(items) do
      table.insert(formatted_items, {
        text = item.display,
        file = item.value,
        value = item,
        idx = i,
        -- Add preview data
        preview = {
          text = function()
            if item.value and vim.fn.filereadable(item.value) == 1 then
              local lines = {}
              local file = io.open(item.value, "r")
              if file then
                local count = 0
                for line in file:lines() do
                  table.insert(lines, line)
                  count = count + 1
                  if count >= 30 then break end
                end
                file:close()
                return table.concat(lines, "\n")
              else
                return "Could not open file: " .. item.value
              end
            else
              return item.value and ("File not readable: " .. item.value) or "No file path"
            end
          end,
          ft = "markdown"
        }
      })
    end

    -- Use the picker with proper multi-select options
    snacks_picker.pick("Select Files to Summarize (Tab to select multiple)", {
      items = formatted_items,
      format = "text",
      multi_select = true,
      sort = { fields = { "score:desc", "idx" } },
      confirm = function(picker, _)
        picker:close()
        local selected = picker:selected({ fallback = true })

        if selected and #selected > 0 then
          -- Get current cursor position
          local current_pos = vim.api.nvim_win_get_cursor(0)
          local insert_row = current_pos[1] - 1 -- Convert to 0-based

          -- Prepare file paths to insert
          local file_paths = {}
          for _, sel in ipairs(selected) do
            if sel and sel.file then
              table.insert(file_paths, sel.file)
            end
          end

          -- Insert all file paths
          vim.api.nvim_buf_set_lines(buffer_id, insert_row, insert_row, false, file_paths)

          -- Move cursor after the inserted lines
          vim.api.nvim_win_set_cursor(0, { insert_row + #file_paths + 1, 0 })

          -- Notify user
          vim.notify("Inserted " .. #file_paths .. " file paths", vim.log.levels.INFO)
        end
      end
    })

    return true
  end

  -- Call the browse_files function with our overridden callbacks
  picker.browse_files()

  -- Restore original implementations after picker is done
  vim.defer_fn(function()
    picker.show_file_browser_telescope = original_telescope
    picker.show_file_browser_snacks = original_snacks
    picker.show_file_browser_fzf_lua = original_fzf_lua
    picker.show_file_browser_simple = original_simple
  end, 1000) -- Restore after 1 second
end

-- Function to check if there are unexpanded file summary blocks
function M.has_unexpanded_file_summary_blocks(buffer_id)
  buffer_id = buffer_id or vim.api.nvim_get_current_buf()

  -- Get all buffer content
  local lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)

  for i, line in ipairs(lines) do
    if line:match("^>>> file%-summary$") then
      -- Check if this block has a file path but no expanded content
      if i < #lines and not (lines[i + 1]:match("^>>>") or lines[i + 1]:match("^<<<")) then
        -- Look for a file path in the next few lines
        for j = i + 1, math.min(i + 5, #lines) do
          if lines[j]:match("^%s*/.+") or lines[j]:match("^%s*[A-Za-z]:.+") then
            -- Found a file path, now check if it has been expanded
            for k = j + 1, math.min(j + 5, #lines) do
              if lines[k]:match("^<<< content") then
                -- Already expanded
                return false
              end
              if lines[k]:match("^>>>") or lines[k]:match("^<<<") then
                -- Reached another block without finding content
                return true
              end
            end
            return true
          end
        end
      end
    end
  end

  return false
end

-- Function to expand a file summary block in the buffer
function M.expand_file_summary_block(buffer_id, block_start, block_end)
  buffer_id = buffer_id or vim.api.nvim_get_current_buf()

  -- Get the block content
  local block_lines = vim.api.nvim_buf_get_lines(buffer_id, block_start, block_end, false)

  -- Extract all file paths (skipping the marker line and empty lines)
  local filepaths = {}
  for i, line in ipairs(block_lines) do
    if i > 1 and line ~= "" and not line:match("^>>>") and not line:match("^<<<") then
      local trimmed = vim.fn.trim(line)
      if trimmed ~= "" then
        table.insert(filepaths, trimmed)
      end
    end
  end

  if #filepaths == 0 then
    -- No file paths found
    vim.api.nvim_buf_set_lines(buffer_id, block_start, block_end, false, {
      ">>> file-summary",
      "",
      "❌ Error: No file paths specified",
      ""
    })
    return 4 -- Return the number of lines we inserted
  end

  -- Collect file contents and validate all files
  local file_contents = {}
  local invalid_files = {}

  for _, filepath in ipairs(filepaths) do
    -- Expand the path
    local expanded_path = vim.fn.expand(filepath)

    -- Check if file exists
    if vim.fn.filereadable(expanded_path) ~= 1 then
      table.insert(invalid_files, {
        path = filepath,
        error = "File not found or not readable"
      })
    else
      -- Read the file content
      local content = table.concat(vim.fn.readfile(expanded_path), "\n")
      table.insert(file_contents, {
        path = filepath,
        expanded_path = expanded_path,
        content = content
      })
    end
  end

  -- If all files are invalid, show error
  if #file_contents == 0 then
    local error_lines = {
      ">>> file-summary",
      "",
    }

    -- Add all filepaths with errors
    for _, file in ipairs(invalid_files) do
      table.insert(error_lines, file.path)
      table.insert(error_lines, "❌ Error: " .. file.error)
      table.insert(error_lines, "")
    end

    vim.api.nvim_buf_set_lines(buffer_id, block_start, block_end, false, error_lines)
    return #error_lines
  end

  -- Create summarization request
  local summary_config = {
    provider = config.options.summary.provider or config.options.active_provider,
    model = config.options.summary.model or config.options.active_model,
    temperature = config.options.summary.temperature,
    max_tokens = config.options.summary.max_tokens
  }

  -- Create a system message for the summary
  local system_message = {
    role = "system",
    content =
    "Summarize the following file(s) concisely but comprehensively. For each file, provide a separate summary section that captures key information and structure."
  }

  -- Create a user message containing all files to summarize
  local user_content = {}

  if #file_contents == 1 then
    -- Single file format
    local file = file_contents[1]
    table.insert(user_content, "File: " .. vim.fn.fnamemodify(file.expanded_path, ":t"))
    table.insert(user_content, "Path: " .. file.path)
    table.insert(user_content, "")
    table.insert(user_content, file.content)
  else
    -- Multiple files format
    table.insert(user_content, "Please summarize the following " .. #file_contents .. " files:")
    table.insert(user_content, "")

    for i, file in ipairs(file_contents) do
      table.insert(user_content, "--- FILE " .. i .. " ---")
      table.insert(user_content, "File: " .. vim.fn.fnamemodify(file.expanded_path, ":t"))
      table.insert(user_content, "Path: " .. file.path)
      table.insert(user_content, "")
      table.insert(user_content, file.content)
      table.insert(user_content, "")
    end
  end

  local user_message = {
    role = "user",
    content = table.concat(user_content, "\n")
  }

  -- Create summary messages
  local summary_messages = { system_message, user_message }

  -- Replace the block with a processing indicator
  local indicator_lines = {
    ">>> file-summary",
    "",
  }

  -- Add all file paths
  for _, filepath in ipairs(filepaths) do
    table.insert(indicator_lines, filepath)
  end

  -- Add processing indicator
  table.insert(indicator_lines, "")
  table.insert(indicator_lines, "⏳ Generating file summary...")
  table.insert(indicator_lines, "")

  vim.api.nvim_buf_set_lines(buffer_id, block_start, block_end, false, indicator_lines)

  -- Create indicator
  local indicator_row = block_start + #indicator_lines - 2 -- The "Generating file summary..." line

  -- Create indicator
  local indicator = {
    buffer_id = buffer_id,
    start_row = block_start,
    spinner_row = indicator_row,
    end_row = block_start + #indicator_lines,
    timer = nil,
    stats = {
      tokens = 0,
      elapsed_time = 0,
      start_time = vim.loop.now(),
      model = summary_config.model
    }
  }

  -- Register the indicator in state
  local indicator_id = "file_summary_indicator_" .. buffer_id .. "_" .. block_start
  state.register_indicator(indicator_id, indicator)

  -- Start the animation
  local animation_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
  local current_frame = 1

  indicator.timer = vim.loop.new_timer()
  indicator.timer:start(0, 120, vim.schedule_wrap(function()
    -- Check if buffer still exists
    if not vim.api.nvim_buf_is_valid(buffer_id) then
      if indicator.timer then
        indicator.timer:stop()
        indicator.timer:close()
      end
      return
    end

    -- Update elapsed time
    indicator.stats.elapsed_time = math.floor((vim.loop.now() - indicator.stats.start_time) / 1000)

    -- Update the status line with current info
    local status_text = animation_frames[current_frame] .. " Generating file summary"

    -- Add file count if multiple files
    if #file_contents > 1 then
      status_text = status_text .. " for " .. #file_contents .. " files"
    end

    -- Add elapsed time
    if indicator.stats.elapsed_time > 0 then
      status_text = status_text .. " | " .. indicator.stats.elapsed_time .. "s elapsed"
    end

    -- Update the text in the buffer
    vim.api.nvim_buf_set_lines(
      buffer_id,
      indicator_row,
      indicator_row + 1,
      false,
      { status_text }
    )

    -- Model info line if we have model information
    local model_info = ""
    if indicator.stats.model then
      -- Extract just the model name without provider prefix
      local model_name = indicator.stats.model:match("[^/]+$") or indicator.stats.model
      model_info = "Using model: " .. model_name
    end

    -- If we have model info, put it on the next line
    if model_info ~= "" then
      -- Check if we need to add a new line for model info
      local model_row = indicator_row + 1

      if model_row >= indicator.end_row then
        -- Need to add a new line
        vim.api.nvim_buf_set_lines(
          buffer_id,
          model_row,
          model_row,
          false,
          { model_info }
        )
        indicator.end_row = indicator.end_row + 1
      else
        -- Update existing line
        vim.api.nvim_buf_set_lines(
          buffer_id,
          model_row,
          model_row + 1,
          false,
          { model_info }
        )
      end
    end

    -- Move to the next animation frame
    current_frame = (current_frame % #animation_frames) + 1
  end))

  -- Create success callback
  local on_success = function(response)
    -- Check if indicator exists before removing it
    if indicator and indicator.timer then
      -- Stop the timer
      indicator.timer:stop()
      indicator.timer:close()
    end

    -- Format the result
    local result_lines = {
      ">>> file-summary",
      "",
    }

    -- Add all file paths
    for _, filepath in ipairs(filepaths) do
      table.insert(result_lines, filepath)
    end

    -- Add any invalid files with errors
    for _, file in ipairs(invalid_files) do
      table.insert(result_lines, file.path .. " ❌ " .. file.error)
    end

    -- Add content marker
    table.insert(result_lines, "")
    table.insert(result_lines, "<<< content [" .. os.date("%Y-%m-%d %H:%M:%S") .. "]")
    table.insert(result_lines, "")

    -- Add the summary content
    local content_lines = vim.split(response, "\n")
    for _, line in ipairs(content_lines) do
      table.insert(result_lines, line)
    end

    -- Add a final empty line
    table.insert(result_lines, "")

    -- Replace the block
    local line_count = indicator.end_row - indicator.start_row
    vim.api.nvim_buf_set_lines(buffer_id, block_start, block_start + line_count, false, result_lines)

    -- Clear indicator from state
    if state.active_indicators[indicator_id] then
      state.clear_indicator(indicator_id)
    end

    -- Return the number of lines we inserted
    return #result_lines
  end

  -- Create error callback
  local on_error = function(error_msg)
    -- Check if indicator exists before removing it
    if indicator and indicator.timer then
      -- Stop the timer
      indicator.timer:stop()
      indicator.timer:close()
    end

    -- Format the error
    local error_lines = {
      ">>> file-summary",
      "",
    }

    -- Add all file paths
    for _, filepath in ipairs(filepaths) do
      table.insert(error_lines, filepath)
    end

    -- Add the error message
    table.insert(error_lines, "")
    table.insert(error_lines, "❌ Error: " .. error_msg)
    table.insert(error_lines, "")

    -- Replace the block
    local line_count = indicator.end_row - indicator.start_row
    vim.api.nvim_buf_set_lines(buffer_id, block_start, block_start + line_count, false, error_lines)

    -- Clear indicator from state
    if state.active_indicators[indicator_id] then
      state.clear_indicator(indicator_id)
    end

    -- Return the number of lines we inserted
    return #error_lines
  end

  -- Call API
  local request_handle = api.chat_request(
    summary_messages,
    function(response)
      local result = on_success(response)
      return result
    end,
    function(error_msg)
      local result = on_error(error_msg)
      return result
    end,
    summary_config
  )

  -- Return the current number of lines (will be updated asynchronously)
  return #indicator_lines
end

-- Run tests
function M.run_tests()
  return require('nai.tests').run_all()
end

return M
