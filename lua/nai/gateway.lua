-- lua/nai/gateway.lua
-- WebSocket gateway interface for moltbot integration

local M = {}
local config = require('nai.config')
local state = require('nai.state')
local events = require('nai.events')

-- Gateway connection state
local gateway_job = nil
local gateway_connected = false
local pending_callbacks = {}

-- Get the path to the Python WebSocket client
local function get_ws_client_path()
  -- Try multiple locations in order of preference
  local possible_paths = {
    -- 1. User config directory (where you put it)
    vim.fn.stdpath('config') .. '/lua/nai/ws_client.py',

    -- 2. Plugin installation directory (if installed via package manager)
    vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. '/ws_client.py',

    -- 3. Relative to this file
    vim.fn.expand('<sfile>:p:h') .. '/ws_client.py',
  }

  for _, path in ipairs(possible_paths) do
    if vim.fn.filereadable(path) == 1 then
      return path
    end
  end

  -- If none found, return the preferred location (config dir)
  return possible_paths[1]
end

-- Start the gateway connection
function M.connect(model_name)
  if gateway_job then
    vim.notify("Gateway already connected", vim.log.levels.INFO)
    return true
  end

  local moltbot_config = config.options.moltbot or {}

  -- Get gateway config for the specified model
  local gateway_config
  if model_name and moltbot_config.gateways and moltbot_config.gateways[model_name] then
    -- Use model-specific gateway config
    gateway_config = moltbot_config.gateways[model_name]
  else
    -- Use default gateway config
    gateway_config = moltbot_config
  end

  local gateway_url = gateway_config.gateway_url or "ws://localhost:18789"
  local auth_token = gateway_config.auth_token

  local ws_client = get_ws_client_path()

  -- Check if Python script exists
  if vim.fn.filereadable(ws_client) ~= 1 then
    vim.notify("WebSocket client not found: " .. ws_client, vim.log.levels.ERROR)
    return false
  end

  -- Get Python executable
  local python_exe = vim.g.python3_host_prog or "python3"

  -- Expand tilde if present
  if python_exe:match("^~") then
    python_exe = vim.fn.expand(python_exe)
  end

  -- Verify Python executable exists
  if vim.fn.executable(python_exe) ~= 1 then
    vim.notify("Python executable not found: " .. python_exe, vim.log.levels.ERROR)
    vim.notify("Check vim.g.python3_host_prog setting", vim.log.levels.WARN)
    return false
  end

  -- Build command
  local cmd = { python_exe, ws_client, gateway_url }
  if auth_token then
    table.insert(cmd, auth_token)
  end

  if config.options.debug and config.options.debug.enabled then
    vim.notify("DEBUG: Starting gateway with: " .. vim.inspect(cmd), vim.log.levels.DEBUG)
  end

  -- Start the job with explicit stdout/stderr separation
  gateway_job = vim.fn.jobstart(cmd, {
    on_stdout = function(_, data)
      M.handle_gateway_message(data)
    end,
    on_stderr = function(_, data)
      -- ONLY log actual errors, not JSON frames
      for _, line in ipairs(data) do
        if line ~= "" and not line:match('^%s*{') then -- Skip JSON lines
          vim.notify("Gateway stderr: " .. line, vim.log.levels.WARN)
        end
      end
    end,
    on_exit = function(_, exit_code)
      gateway_job = nil
      gateway_connected = false

      if exit_code ~= 0 then
        vim.notify("Gateway disconnected with code: " .. exit_code, vim.log.levels.WARN)
      end
    end,
    stdout_buffered = false, -- Don't buffer stdout
    stderr_buffered = false, -- Don't buffer stderr
  })

  if gateway_job <= 0 then
    vim.notify("Failed to start gateway connection", vim.log.levels.ERROR)
    gateway_job = nil
    return false
  end

  return true
end

-- Disconnect from gateway
function M.disconnect()
  if gateway_job then
    vim.fn.jobstop(gateway_job)
    gateway_job = nil
    gateway_connected = false
    vim.notify("Gateway disconnected", vim.log.levels.INFO)
  end
end

-- Handle agent events (streaming responses)
function M.handle_agent_event(payload)
  local run_id = payload.runId
  local session_key = payload.sessionKey
  local stream = payload.stream

  -- Handle lifecycle events (start/end)
  if stream == "lifecycle" then
    local phase = payload.data and payload.data.phase

    if phase == "end" then
      -- Agent run completed - trigger final callback
      local callback_data = nil
      local callback_request_id = nil
      for request_id, data in pairs(pending_callbacks) do
        if data.run_id == run_id or data.session_key == session_key then
          callback_data = data
          callback_request_id = request_id
          break
        end
      end

      if callback_data and callback_data.on_stream then
        vim.schedule(function()
          callback_data.on_stream("", true)
        end)

        -- Clean up
        pending_callbacks[callback_request_id] = nil
        state.clear_request(callback_request_id)
      end
    end

    return
  end

  -- Only handle assistant stream
  if stream ~= "assistant" then
    return
  end

  -- Find the callback for this run or session
  local callback_data = nil
  local callback_request_id = nil
  for request_id, data in pairs(pending_callbacks) do
    if data.run_id == run_id or data.session_key == session_key then
      callback_data = data
      callback_request_id = request_id
      if not data.run_id then
        data.run_id = run_id
      end
      break
    end
  end

  if not callback_data or not callback_data.on_stream then
    return
  end

  -- Extract the delta text
  local delta = payload.data and payload.data.delta or ""

  vim.schedule(function()
    callback_data.on_stream(delta, false)
  end)
end

-- Handle chat events (streaming responses)
function M.handle_chat_event(payload)
  local run_id = payload.runId
  local session_key = payload.sessionKey
  local state_type = payload.state

  -- Find the callback for this run
  local callback_data = nil
  for request_id, data in pairs(pending_callbacks) do
    if data.run_id == run_id or data.session_key == session_key then
      callback_data = data
      break
    end
  end

  if not callback_data or not callback_data.on_stream then
    return
  end

  vim.schedule(function()
    if state_type == "delta" then
      -- Extract text from message content
      local message = payload.message
      local text = ""

      if message and message.content then
        if type(message.content) == "string" then
          text = message.content
        elseif type(message.content) == "table" then
          -- Content is an array of content blocks
          for _, block in ipairs(message.content) do
            if block.type == "text" then
              text = text .. (block.text or "")
            end
          end
        end
      end

      -- Streaming chunk
      callback_data.on_stream(text, false)
    elseif state_type == "final" then
      -- Extract text from final message
      local message = payload.message
      local text = ""

      if message and message.content then
        if type(message.content) == "string" then
          text = message.content
        elseif type(message.content) == "table" then
          for _, block in ipairs(message.content) do
            if block.type == "text" then
              text = text .. (block.text or "")
            end
          end
        end
      end

      -- Final response
      callback_data.on_stream(text, true)

      -- Clean up
      for request_id, data in pairs(pending_callbacks) do
        if data.run_id == run_id then
          pending_callbacks[request_id] = nil
          state.clear_request(request_id)
          break
        end
      end
    elseif state_type == "error" or state_type == "aborted" then
      -- Error or cancellation
      local error_msg = payload.errorMessage or "Request " .. state_type
      if callback_data.on_error then
        callback_data.on_error(error_msg)
      end

      -- Clean up
      for request_id, data in pairs(pending_callbacks) do
        if data.run_id == run_id then
          pending_callbacks[request_id] = nil
          state.clear_request(request_id)
          break
        end
      end
    end
  end)
end

-- Handle event frames (streaming chat responses)
function M.handle_event(frame)
  local event_name = frame.event

  if event_name == "agent" then
    -- Agent events contain streaming responses (preferred)
    M.handle_agent_event(frame.payload)
  elseif event_name == "chat" then
    -- Skip chat events if we're using agent events
    -- (agent events provide cleaner streaming)
    -- M.handle_chat_event(frame.payload)
  end
end

-- Handle response frames
function M.handle_response(frame)
  local request_id = frame.id
  local callback_data = pending_callbacks[request_id]

  if not callback_data then
    return
  end

  if frame.ok then
    -- Extract runId from payload if present
    local payload = frame.payload
    if payload and payload.runId then
      -- Store the runId so agent events can find this callback
      callback_data.run_id = payload.runId
    end

    -- Success - but don't call on_complete yet (we're streaming)
    -- The final response will come via agent events
  else
    -- Error
    local error_msg = frame.error and frame.error.message or "Unknown error"
    if callback_data.on_error then
      vim.schedule(function()
        callback_data.on_error(error_msg)
      end)
    end

    -- Clean up on error
    pending_callbacks[request_id] = nil
    state.clear_request(request_id)
  end
end

-- Handle messages from the gateway
function M.handle_gateway_message(data)
  for _, line in ipairs(data) do
    if line ~= "" then
      local success, frame = pcall(vim.json.decode, line)

      if not success then
        vim.notify("Failed to parse gateway message: " .. line, vim.log.levels.ERROR)
        return
      end

      local frame_type = frame.type

      if frame_type == "connected" then
        gateway_connected = true
        vim.notify("Connected to moltbot gateway", vim.log.levels.INFO)
      elseif frame_type == "res" then
        M.handle_response(frame)
      elseif frame_type == "event" then
        M.handle_event(frame)
      elseif frame_type == "disconnected" then
        gateway_connected = false
        vim.notify("Gateway connection lost", vim.log.levels.WARN)
      elseif frame_type == "error" then
        vim.notify("Gateway error: " .. (frame.error or "unknown"), vim.log.levels.ERROR)
      end
    end
  end
end

-- Send a chat request to the gateway
function M.chat_send(session_key, messages, on_stream, on_complete, on_error, chat_config, model_name)
  -- Ensure we're connected
  if not gateway_connected then
    local connected = M.connect(model_name)
    if not connected then
      vim.schedule(function()
        on_error("Failed to connect to gateway")
      end)
      return nil
    end

    -- Wait a bit for connection
    vim.defer_fn(function()
      M.chat_send(session_key, messages, on_stream, on_complete, on_error, chat_config, model_name)
    end, 500)
    return nil
  end

  -- Generate request ID
  local request_id = "nvim_" .. tostring(os.time()) .. "_" .. tostring(math.random(100000))

  -- Combine all consecutive user messages at the end (since last assistant response)
  local combined_user_content = {}
  local i = #messages

  -- Walk backwards from the end, collecting user messages
  while i > 0 and messages[i].role == "user" do
    table.insert(combined_user_content, 1, messages[i].content)
    i = i - 1
  end

  if #combined_user_content == 0 then
    vim.schedule(function()
      on_error("No user message found")
    end)
    return nil
  end

  -- Join all user messages with double newlines for clear separation
  local final_message = table.concat(combined_user_content, "\n\n")

  -- Build request frame
  local request = {
    type = "req",
    id = request_id,
    method = "chat.send",
    params = {
      sessionKey = session_key,
      message = final_message, -- Combined message content
      idempotencyKey = request_id,
      deliver = false,
      timeoutMs = 300000
    }
  }

  -- Add thinking level if configured
  if chat_config and chat_config.thinking then
    request.params.thinking = chat_config.thinking
  end

  -- Register callback
  pending_callbacks[request_id] = {
    session_key = session_key,
    run_id = nil, -- Will be set when we get the first agent event
    on_stream = on_stream,
    on_complete = on_complete,
    on_error = on_error
  }

  -- Register in state
  state.register_request(request_id, {
    id = request_id,
    type = 'chat',
    status = 'pending',
    start_time = os.time(),
    provider = "moltbot",
    session_key = session_key
  })

  -- Send request
  local json_request = vim.json.encode(request) .. "\n"
  vim.fn.chansend(gateway_job, json_request)

  events.emit('request:start', request_id, "moltbot", session_key)

  return {
    request_id = request_id,
    terminate = function()
      M.cancel_request(request_id)
    end
  }
end

-- Cancel a request
function M.cancel_request(request_id)
  local callback_data = pending_callbacks[request_id]

  if callback_data and callback_data.session_key then
    -- Send abort request
    local abort_request = {
      type = "req",
      id = "abort_" .. request_id,
      method = "chat.abort",
      params = {
        sessionKey = callback_data.session_key
      }
    }

    local json_request = vim.json.encode(abort_request) .. "\n"
    vim.fn.chansend(gateway_job, json_request)
  end

  -- Clean up
  pending_callbacks[request_id] = nil
  state.clear_request(request_id)

  events.emit('request:cancel', request_id)
end

-- Write moltbot session key to buffer frontmatter (insert if not present)
local function write_moltbot_session_to_buffer(buffer_id, session_key)
  local lines = vim.api.nvim_buf_get_lines(buffer_id, 0, 20, false)
  local in_frontmatter = false
  local session_key_line = nil
  local frontmatter_start = nil
  local frontmatter_end = nil

  for i, line in ipairs(lines) do
    if line == "---" then
      if in_frontmatter then
        -- This is the CLOSING --- (1-indexed)
        -- We want to insert BEFORE this line
        frontmatter_end = i - 1 -- Convert to 0-indexed for the line BEFORE ---
        break
      else
        in_frontmatter = true
        frontmatter_start = i
      end
    elseif in_frontmatter then
      -- Check if this line is the moltbot_session line (even if empty)
      if line:match("^moltbot_session:%s*$") or line:match("^moltbot_session:%s*.+$") then
        session_key_line = i - 1 -- Convert to 0-indexed
      end
    end
  end

  -- If we found an existing moltbot_session line, update it
  if session_key_line then
    vim.api.nvim_buf_set_lines(
      buffer_id,
      session_key_line,
      session_key_line + 1,
      false,
      { "moltbot_session: " .. session_key }
    )
    return true
  end

  -- If we found frontmatter but no moltbot_session line, insert it
  if frontmatter_end then
    -- frontmatter_end is 0-indexed and points to the closing ---
    -- We want to insert BEFORE the closing ---
    vim.api.nvim_buf_set_lines(
      buffer_id,
      frontmatter_end, -- Insert at the position of the closing ---
      frontmatter_end, -- Don't replace anything
      false,
      { "moltbot_session: " .. session_key }
    )
    return true
  end

  -- No frontmatter found
  if config.options.debug and config.options.debug.enabled then
    vim.notify("DEBUG: No YAML frontmatter found to insert moltbot_session", vim.log.levels.DEBUG)
  end

  return false
end

-- Get or create moltbot session key from buffer
function M.get_session_key(buffer_id)
  local moltbot_config = config.options.moltbot or {}
  local session_prefix = moltbot_config.session_prefix or "nvim"

  -- Try to extract from frontmatter
  local lines = vim.api.nvim_buf_get_lines(buffer_id, 0, 20, false)
  local in_frontmatter = false
  local has_empty_session = false

  for _, line in ipairs(lines) do
    if line == "---" then
      if in_frontmatter then
        break
      else
        in_frontmatter = true
      end
    elseif in_frontmatter then
      -- Check for moltbot_session field
      local value = line:match("^moltbot_session:%s*(.+)$")
      if value then
        -- Trim whitespace
        value = value:gsub("^%s*(.-)%s*$", "%1")
        if value ~= "" then
          return value
        else
          has_empty_session = true
        end
      elseif line:match("^moltbot_session:%s*$") then
        has_empty_session = true
      end
    end
  end

  -- Generate new session key
  local buffer_name = vim.api.nvim_buf_get_name(buffer_id)
  local basename = vim.fn.fnamemodify(buffer_name, ":t:r")
  local new_session_key = session_prefix .. ":" .. basename .. ":" .. tostring(os.time())

  -- Write it back to the buffer (will insert if doesn't exist)
  write_moltbot_session_to_buffer(buffer_id, new_session_key)

  return new_session_key
end

return M
