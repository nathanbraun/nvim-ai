-- lua/nai/init.lua
-- Main module for nvim-ai plugin

local M = {}
local config = require('nai.config')
local api = require('nai.api')
local utils = require('nai.utils')
local error_utils = require('nai.utils.error')
local constants = require('nai.constants')

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

  if not has_curl then
    error_utils.log("nvim-ai may not function correctly without required dependencies", error_utils.LEVELS.WARNING)
  end
end

-- Track the proxy job so we can clean it up
M._claude_proxy_job = nil

-- Start the claude-proxy server if it isn't already running
function M.ensure_claude_proxy()
  local proxy_config = config.options.providers.claude_proxy or {}
  local endpoint = proxy_config.endpoint or "http://127.0.0.1:5757/v1/chat/completions"
  local health_url = endpoint:gsub("/v1/chat/completions$", "/health")

  -- Check if it's already running
  vim.system(
    { "curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "--connect-timeout", "1", health_url },
    { text = true },
    function(obj)
      if vim.trim(obj.stdout or "") == "200" then
        return -- already running
      end

      -- Find the proxy script
      local script_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")
      local script_path = script_dir .. "/scripts/claude-proxy.py"

      if vim.fn.filereadable(script_path) ~= 1 then
        vim.schedule(function()
          vim.notify("claude-proxy.py not found at: " .. script_path, vim.log.levels.WARN)
        end)
        return
      end

      -- Extract port from endpoint
      local port = endpoint:match(":(%d+)/") or "5757"

      vim.schedule(function()
        M._claude_proxy_job = vim.fn.jobstart(
          { "python3", script_path, port },
          {
            detach = true,
            on_stderr = function(_, data)
              if data and data[1] and data[1] ~= "" then
                -- Only log errors, not normal startup output
                for _, line in ipairs(data) do
                  if line:match("[Ee]rror") or line:match("[Tt]raceback") then
                    vim.schedule(function()
                      vim.notify("claude-proxy: " .. line, vim.log.levels.ERROR)
                    end)
                  end
                end
              end
            end,
            on_exit = function(_, code)
              if code ~= 0 then
                vim.schedule(function()
                  vim.notify("claude-proxy failed to start (exit code " .. code .. ")", vim.log.levels.ERROR)
                end)
              end
            end,
          }
        )

        -- Verify proxy started after a short delay
        vim.defer_fn(function()
          vim.system(
            { "curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "--connect-timeout", "2", health_url },
            { text = true },
            function(check)
              vim.schedule(function()
                if vim.trim(check.stdout or "") == "200" then
                  vim.notify("Claude proxy started on :" .. port, vim.log.levels.INFO)
                else
                  vim.notify(
                    "Claude proxy may not have started.\n" ..
                    "Try running manually: python3 " .. script_path,
                    vim.log.levels.WARN
                  )
                end
              end)
            end
          )
        end, 1500)
      end)
    end
  )
end

-- Setup function that should be called by the user
function M.setup(opts)
  config.setup(opts)
  require('nai.mappings').setup(opts)

  -- Check dependencies
  check_dependencies()

  -- Check platform compatibility
  check_platform_compatibility()

  -- Check if API key / dependencies are configured for the active provider
  local provider = config.options.active_provider
  local no_key_providers = { claude_proxy = true }

  if no_key_providers[provider] then
    -- Local providers: check that their dependencies are available
    if provider == "claude_proxy" then
      local missing = {}
      if vim.fn.executable("claude") ~= 1 then
        table.insert(missing, "claude CLI not found (install and run: claude login)")
      end
      if vim.fn.executable("python3") ~= 1 then
        table.insert(missing, "python3 not found (required to run the proxy server)")
      end

      if #missing > 0 then
        vim.defer_fn(function()
          vim.notify(
            "claude_proxy setup issues:\n- " .. table.concat(missing, "\n- "),
            vim.log.levels.WARN
          )
        end, 1000)
      else
        -- Auto-start proxy if configured
        local proxy_config = config.options.providers.claude_proxy or {}
        if proxy_config.auto_start ~= false then
          M.ensure_claude_proxy()
        end
      end
    end
  else
    local api_key = config.get_api_key(provider)
    if not api_key then
      vim.defer_fn(function()
        vim.notify(
          "No API key found for " .. provider .. ".\n" ..
          "Please set your API key with :NAISetKey " .. provider,
          vim.log.levels.WARN
        )
      end, 1000)
    end
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

  local state = require('nai.state')
  local current_buf = vim.api.nvim_get_current_buf()
  if state.is_buffer_activated(current_buf) then
    require('nai.buffer').apply_syntax_overlay(current_buf)
  end

  -- Reload the main module
  return require("nai")
end

-- Function to switch between providers
function M.switch_provider(provider)
  local config = require('nai.config')

  if not config.options.providers[provider] then
    local valid_providers = vim.tbl_keys(config.options.providers)
    table.sort(valid_providers)
    vim.notify("Invalid provider '" .. provider .. "'. Available: " .. table.concat(valid_providers, ", "), vim.log.levels.ERROR)
    return
  end
  config.options.active_provider = provider

  -- Update state
  require('nai.state').set_current_provider(provider)

  -- If switching to Ollama, ensure the model is valid
  if provider == "ollama" then
    config.ensure_valid_ollama_model(config.options.providers.ollama)
  end

  vim.notify("Switched to " .. provider .. " provider", vim.log.levels.INFO)
end

-- ============================================================================
-- Chat Function Components
-- ============================================================================

-- Validate buffer and handle activation
local function validate_and_prepare_buffer(buffer_id)
  local buffer_module = require('nai.buffer')
  local state = require('nai.state')

  -- Force activation for this buffer if it contains user prompts
  local contains_chat_markers = buffer_module.detect_chat_markers(buffer_id)
  if contains_chat_markers and not state.is_buffer_activated(buffer_id) then
    vim.notify("Found chat markers, activating buffer...", vim.log.levels.INFO)
    buffer_module.activate_buffer(buffer_id)
  end

  -- Check if buffer is activated after our attempt
  if not state.is_buffer_activated(buffer_id) then
    return false, "not_activated"
  end

  return true, nil
end

-- Try to expand any unexpanded blocks in the buffer
local function try_expand_blocks(buffer_id)
  local expanded = M.expand_blocks(buffer_id)
  return expanded
end

-- Parse buffer content into messages and config
local function parse_buffer_content(buffer_id)
  local parser = require('nai.parser')

  -- Get all buffer content
  local lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)
  local buffer_content = table.concat(lines, "\n")

  -- Parse buffer content into messages
  local messages, chat_config = parser.parse_chat_buffer(buffer_content, buffer_id)

  -- Handle placeholder expansion
  local should_expand_placeholders
  if chat_config and chat_config.expand_placeholders ~= nil then
    should_expand_placeholders = chat_config.expand_placeholders
  else
    should_expand_placeholders = config.options.expand_placeholders
  end

  if should_expand_placeholders and messages then
    for _, msg in ipairs(messages) do
      if msg.content and type(msg.content) == "string" then
        msg.content = parser.replace_placeholders(msg.content, buffer_id)
      end
    end
  end

  return messages, chat_config
end

-- Ensure there's a user message at the end, or prompt for one
local function ensure_user_message(buffer_id, messages)
  local parser = require('nai.parser')

  local last_message = messages[#messages]
  if not last_message or last_message.role ~= "user" then
    -- No user message, add template
    local user_template = parser.format_user_message("")
    local user_lines = vim.split(user_template, "\n")
    vim.api.nvim_buf_set_lines(buffer_id, -1, -1, false, user_lines)

    -- Position cursor on the 3rd line of new user message
    local line_count = vim.api.nvim_buf_line_count(buffer_id)
    vim.api.nvim_win_set_cursor(0, { line_count, 0 })

    return false, "Please add your message first, then run NAIChat again"
  end

  return true, nil
end

-- Check if auto-title is needed and modify system message if so
-- Returns true if auto-title was applied
local function detect_and_apply_auto_title(buffer_id, messages)
  if not config.options.chat_files.auto_title then
    return false
  end

  local lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)

  -- Don't auto-title if there's a user-provided system message
  for _, line in ipairs(lines) do
    if line == constants.MARKERS.SYSTEM then
      return false
    end
  end

  -- Check if the title is still "Untitled"
  local needs_auto_title = false
  for i, line in ipairs(lines) do
    if line:match("^title:%s*Untitled") then
      needs_auto_title = true
      break
    end
    if line == "---" and i > 1 then
      break
    end
  end

  if not needs_auto_title then
    return false
  end

  -- Modify the system message to request a title
  local parser = require('nai.parser')
  for _, msg in ipairs(messages) do
    if msg.role == "system" then
      msg.content = parser.get_system_prompt_with_title_request(true)
      break
    end
  end

  return true
end

-- Prepare the chat request (indicator, auto-title logic, etc)
local function prepare_chat_request(buffer_id, messages, chat_config)
  local utils = require('nai.utils')
  local state = require('nai.state')

  -- Position cursor at the end of the buffer
  local line_count = vim.api.nvim_buf_line_count(buffer_id)
  vim.api.nvim_win_set_cursor(0, { line_count, 0 })

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

  -- Check and apply auto-title if needed
  local needs_auto_title = detect_and_apply_auto_title(buffer_id, messages)

  return {
    indicator = indicator,
    indicator_id = indicator_id,
    needs_auto_title = needs_auto_title
  }
end

-- Handle successful chat response
local function handle_chat_response(buffer_id, request_data, response, messages, chat_config)
  local parser = require('nai.parser')
  local fileutils = require('nai.fileutils')
  local utils = require('nai.utils')
  local state = require('nai.state')

  local indicator = request_data.indicator
  local indicator_id = request_data.indicator_id

  -- Get the position where we need to replace the placeholder
  local insertion_row = utils.indicators.remove(indicator)

  -- Clear indicator from state
  state.clear_indicator(indicator_id)

  -- Extract title if present (strip leading whitespace before matching)
  local modified_response = response
  local trimmed = response:gsub("^%s+", "")
  local title_match = trimmed:match("^Proposed Title:%s*(.-)[\r\n]")
  if title_match then
    modified_response = trimmed:gsub("^Proposed Title:%s*.-%s*[\r\n]+", "")

    -- Update the YAML frontmatter if we found a title
    if title_match and title_match:len() > 0 then
      local buffer_lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)
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

  -- Add new user message template
  local new_user = parser.format_user_message("")
  vim.api.nvim_buf_set_lines(buffer_id, -1, -1, false, vim.split(new_user, "\n"))

  -- Auto-save if enabled
  if config.options.chat_files.auto_save then
    fileutils.save_chat_buffer(buffer_id)
  end

  -- Move cursor to end safely
  local final_line_count = vim.api.nvim_buf_line_count(buffer_id)
  local safe_pos = math.min(final_line_count, insertion_row + #lines_to_append)

  if vim.api.nvim_buf_is_valid(buffer_id) then
    local current_buf = vim.api.nvim_get_current_buf()
    if current_buf == buffer_id then
      vim.api.nvim_win_set_cursor(0, { safe_pos, 0 })
    end
  end

  vim.notify("AI response complete", vim.log.levels.INFO)
end

-- Handle chat error
local function handle_chat_error(buffer_id, request_data, error_msg)
  local utils = require('nai.utils')
  local state = require('nai.state')

  local indicator = request_data.indicator
  local indicator_id = request_data.indicator_id

  -- Get the position where we need to replace the placeholder
  local insertion_row = utils.indicators.remove(indicator)

  -- Clear indicator from state
  state.clear_indicator(indicator_id)

  -- Create error message
  local error_lines = {
    "",
    constants.MARKERS.ASSISTANT,
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
end

function M.chat(opts)
  local buffer_id = vim.api.nvim_get_current_buf()
  local state = require('nai.state')

  -- Step 1: Validate and prepare buffer
  local valid, err = validate_and_prepare_buffer(buffer_id)
  if not valid then
    if err == "not_activated" then
      vim.notify("Buffer not activated, creating new chat...", vim.log.levels.INFO)

      -- Handle non-activated buffer (create new chat)
      local text = ""
      if opts.range > 0 then
        text = require('nai.utils').get_visual_selection()
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
    return
  end

  -- Step 2: Try to expand blocks
  local expanded = try_expand_blocks(buffer_id)
  if expanded then
    return -- Blocks were expanded, exit early
  end

  -- Step 3: Parse buffer content
  local messages, chat_config = parse_buffer_content(buffer_id)

  -- Step 4: Ensure user message exists
  local has_user_msg, msg = ensure_user_message(buffer_id, messages)
  if not has_user_msg then
    vim.notify(msg, vim.log.levels.INFO)
    return
  end

  -- Step 5: Prepare chat request
  local request_data = prepare_chat_request(buffer_id, messages, chat_config)

  -- Step 6: Cancel any ongoing requests
  if state.has_active_requests() then
    M.cancel()
  end

  -- Step 7: Make API request (all providers now go through api.lua)
  local request_handle = api.chat_request(
    messages,
    function(response)
      handle_chat_response(buffer_id, request_data, response, messages, chat_config)
    end,
    function(error_msg)
      handle_chat_error(buffer_id, request_data, error_msg)
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

  -- Handle indicators - use the manager's get_all method
  local active_indicators = state.indicators:get_all()

  for indicator_id, indicator in pairs(active_indicators) do
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
  local header = parser.generate_header("Untitled", nil) -- Let it auto-generate

  -- Split header and add exactly what we want
  local header_lines = vim.split(header, "\n")

  -- Add user message right after header with exactly one blank line
  table.insert(header_lines, "")         -- One blank line after YAML header
  table.insert(header_lines, constants.MARKERS.USER) -- User prompt
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
  local state = require('nai.state')

  -- Create a title from user input
  local title_text = user_input:sub(1, 40) .. (user_input:len() > 40 and "..." or "")
  local filename = fileutils.generate_filename(title_text)

  -- Create new buffer with filename
  vim.cmd("enew")
  local buffer_id = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_name(buffer_id, filename)
  vim.bo[buffer_id].filetype = "naichat"

  -- Generate header
  local header = parser.generate_header(title_text, nil) -- Let it auto-generate
  local header_lines = vim.split(header, "\n")

  -- Add user message right after header with exactly one blank line
  table.insert(header_lines, "")         -- One blank line after YAML header
  table.insert(header_lines, constants.MARKERS.USER) -- User prompt
  table.insert(header_lines, "")         -- One blank line after user prompt
  table.insert(header_lines, user_input) -- User input

  -- Add all lines to the buffer
  vim.api.nvim_buf_set_lines(buffer_id, 0, 0, false, header_lines)

  -- Position cursor at the end
  local line_count = vim.api.nvim_buf_line_count(buffer_id)
  vim.api.nvim_win_set_cursor(0, { line_count, 0 })

  -- Create indicator with nice placeholder
  local indicator = utils.indicators.create_assistant_placeholder(buffer_id, line_count)

  -- Register the indicator in state
  local indicator_id = "indicator_" .. buffer_id .. "_" .. line_count
  state.register_indicator(indicator_id, indicator)

  -- Build request_data matching what prepare_chat_request returns
  local request_data = {
    indicator = indicator,
    indicator_id = indicator_id,
    needs_auto_title = false,
  }

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
  if state.has_active_requests() then
    M.cancel()
  end

  -- Call API using shared handlers
  api.chat_request(
    messages,
    function(response)
      handle_chat_response(buffer_id, request_data, response, messages, nil)

      -- Post-save: write the file after response is handled
      if vim.api.nvim_buf_is_valid(buffer_id) then
        vim.api.nvim_buf_call(buffer_id, function()
          vim.cmd("write")
        end)
        vim.notify("AI chat saved to " .. filename, vim.log.levels.INFO)
      end
    end,
    function(error_msg)
      handle_chat_error(buffer_id, request_data, error_msg)
      vim.notify(error_msg, vim.log.levels.ERROR)
    end
  )
end

function M.expand_blocks(buffer_id)
  buffer_id = buffer_id or vim.api.nvim_get_current_buf()

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

  -- Ensure all block processors are loaded and registered
  -- This is necessary because they register themselves on load
  require('nai.fileutils.snapshot')
  require('nai.fileutils.tree')

  -- Use the expander system to handle all block types
  local expander = require('nai.blocks.expander')
  return expander.expand_all(buffer_id)
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
