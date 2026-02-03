--- OpenClaw Gateway integration via HTTP
--- Replaces the WebSocket-based gateway.lua with simpler HTTP/SSE approach

local M = {}

-- Track active jobs for cancellation
M.active_jobs = {}

--- Generate a unique request ID
--- @return string
local function generate_request_id()
  return string.format("nvim_%d_%d_%04d",
    vim.fn.getpid(),
    os.time(),
    math.random(0, 9999)
  )
end

--- Get or create session key for a buffer
--- @param buffer_id number Buffer number
--- @return string Session key
function M.get_session_key(buffer_id)
  buffer_id = buffer_id or vim.api.nvim_get_current_buf()

  -- Check buffer variable first
  local existing = vim.b[buffer_id] and vim.b[buffer_id].openclaw_session_key
  if existing and existing ~= '' then
    return existing
  end

  -- Try to extract from frontmatter
  local lines = vim.api.nvim_buf_get_lines(buffer_id, 0, 30, false)
  local in_frontmatter = false
  for i, line in ipairs(lines) do
    if line:match('^%-%-%-') then
      if i == 1 then
        in_frontmatter = true
      else
        break -- End of frontmatter
      end
    elseif in_frontmatter then
      local key = line:match('^session_key:%s*(.+)$')
      if key then
        local trimmed = key:gsub('^%s*', ''):gsub('%s*$', '')
        vim.b[buffer_id] = vim.b[buffer_id] or {}
        vim.b[buffer_id].openclaw_session_key = trimmed
        return trimmed
      end
    end
  end

  -- Generate new session key based on filename
  local filename = vim.fn.expand('#' .. buffer_id .. ':t:r')
  if not filename or filename == '' then
    filename = 'chat'
  end
  -- Sanitize filename for session key
  filename = filename:gsub('[^%w%-_]', '_'):sub(1, 50)

  local session_key = string.format("nvim:%s", filename)
  vim.b[buffer_id] = vim.b[buffer_id] or {}
  vim.b[buffer_id].openclaw_session_key = session_key
  return session_key
end

--- Parse SSE event line
--- @param line string Raw line from curl output
--- @return string|nil event_type
--- @return any|nil data
local function parse_sse_line(line)
  if not line or line == '' then
    return nil, nil
  end

  -- Handle "event: <type>" lines
  local event_type = line:match('^event:%s*(.+)$')
  if event_type then
    return 'event', event_type:gsub('%s*$', '')
  end

  -- Handle "data: <json>" lines
  local data_str = line:match('^data:%s*(.+)$')
  if data_str then
    local ok, data = pcall(vim.json.decode, data_str)
    if ok then
      return 'data', data
    else
      return 'data_raw', data_str
    end
  end

  return nil, nil
end

--- Send a chat message to OpenClaw Gateway
--- @param session_key string Session identifier
--- @param message string Message text (can include slash commands)
--- @param gateway_config table Gateway configuration {gateway_url, thinking_level, timeout_ms}
--- @param on_stream function Callback: function(chunk: string, is_final: boolean)
--- @param on_complete function Callback: function(final_text: string)
--- @param on_error function Callback: function(error_message: string)
--- @return string run_id The request ID for cancellation
function M.chat_send(session_key, message, gateway_config, on_stream, on_complete, on_error)
  local gateway_url = gateway_config.gateway_url or 'http://localhost:18789'
  local thinking = gateway_config.thinking_level
  local timeout_ms = gateway_config.timeout_ms or 300000

  local run_id = generate_request_id()
  local accumulated_text = ''
  local current_event_type = nil
  local completed = false

  -- Build request body
  local request_body = vim.json.encode({
    sessionKey = session_key,
    message = message,
    thinking = thinking,
    idempotencyKey = run_id,
    senderId = 'nvim:' .. vim.fn.getpid(),
    timeoutMs = timeout_ms,
  })

  -- Start curl with SSE streaming
  local job_id = vim.fn.jobstart({
    'curl',
    '-s', -- Silent mode
    '-N', -- Disable buffering (important for SSE)
    '-X', 'POST',
    gateway_url .. '/nvim/chat',
    '-H', 'Content-Type: application/json',
    '-H', 'Accept: text/event-stream',
    '-d', request_body,
  }, {
    stdout_buffered = false, -- Process lines as they arrive
    on_stdout = function(_, data)
      if completed then return end

      for _, line in ipairs(data) do
        local kind, value = parse_sse_line(line)

        if kind == 'event' then
          current_event_type = value
        elseif kind == 'data' and value then
          -- Handle different event types
          if current_event_type == 'ack' then
            -- Acknowledged, request started
            local config = require('nai.config')
            if config.options.debug and config.options.debug.enabled then
              vim.schedule(function()
                vim.notify('OpenClaw: request started', vim.log.levels.DEBUG)
              end)
            end
          elseif current_event_type == 'delta' then
            -- Streaming delta
            local delta = value.delta or ''
            if delta ~= '' then
              accumulated_text = accumulated_text .. delta
              vim.schedule(function()
                on_stream(delta, false)
              end)
            end
          elseif current_event_type == 'final' then
            -- Final response
            completed = true
            local final_text = value.text or accumulated_text
            vim.schedule(function()
              on_stream('', true)
              on_complete(final_text)
            end)
          elseif current_event_type == 'error' then
            -- Error occurred
            completed = true
            local error_msg = value.error or 'Unknown error'
            vim.schedule(function()
              on_error(error_msg)
            end)
          elseif current_event_type == 'aborted' then
            -- Request was aborted
            completed = true
            vim.schedule(function()
              on_error('Request aborted')
            end)
          end

          current_event_type = nil
        end
      end
    end,
    on_stderr = function(_, data)
      local stderr = table.concat(data, '\n'):gsub('^%s*', ''):gsub('%s*$', '')
      if stderr ~= '' then
        local config = require('nai.config')
        if config.options.debug and config.options.debug.enabled then
          vim.schedule(function()
            vim.notify('OpenClaw stderr: ' .. stderr, vim.log.levels.DEBUG)
          end)
        end
      end
    end,
    on_exit = function(_, code)
      M.active_jobs[session_key] = nil

      if completed then
        return -- Already handled
      end

      vim.schedule(function()
        if code == 0 then
          -- Curl succeeded but no final event - use accumulated text
          if accumulated_text ~= '' then
            on_stream('', true)
            on_complete(accumulated_text)
          else
            on_error('No response received')
          end
        elseif code == 143 then
          -- SIGTERM - cancelled by user
          on_error('Request cancelled')
        else
          on_error('Request failed (exit code ' .. code .. ')')
        end
      end)
    end,
  })

  if job_id <= 0 then
    vim.schedule(function()
      on_error('Failed to start HTTP request')
    end)
    return run_id
  end

  -- Track active job
  M.active_jobs[session_key] = {
    job_id = job_id,
    run_id = run_id,
    started_at = os.time(),
  }

  return run_id
end

--- Cancel an active request
--- @param session_key string Session to cancel
--- @param gateway_url string Gateway URL for abort request
--- @return boolean cancelled Whether a request was cancelled
function M.cancel(session_key, gateway_url)
  local active = M.active_jobs[session_key]
  if not active then
    return false
  end

  -- Kill the curl process
  vim.fn.jobstop(active.job_id)
  M.active_jobs[session_key] = nil

  -- Notify gateway to abort (fire and forget)
  gateway_url = gateway_url or 'http://localhost:18789'

  vim.fn.jobstart({
    'curl', '-s',
    '-X', 'POST',
    gateway_url .. '/nvim/abort',
    '-H', 'Content-Type: application/json',
    '-d', vim.json.encode({
    sessionKey = session_key,
    runId = active.run_id,
  }),
  }, {
    detach = true, -- Don't wait for response
  })

  return true
end

--- Cancel all active requests
--- @param gateway_url string Gateway URL for abort requests
--- @return number count Number of requests cancelled
function M.cancel_all(gateway_url)
  local count = 0
  for session_key, _ in pairs(M.active_jobs) do
    if M.cancel(session_key, gateway_url) then
      count = count + 1
    end
  end
  return count
end

--- Check if gateway is reachable
--- @param gateway_url string Gateway URL to check
--- @param callback function Callback: function(ok: boolean, error: string|nil)
function M.health_check(gateway_url, callback)
  gateway_url = gateway_url or 'http://localhost:18789'

  vim.fn.jobstart({
    'curl', '-s', '-f', '--max-time', '5',
    '-X', 'GET',
    gateway_url .. '/nvim/health',
  }, {
    on_stdout = function(_, data)
      local response = table.concat(data, '')
      if response ~= '' then
        local ok, json = pcall(vim.json.decode, response)
        if ok and json.ok then
          vim.schedule(function()
            callback(true, nil)
          end)
          return
        end
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        if code == 0 then
          callback(true, nil)
        else
          callback(false, 'Gateway not reachable at ' .. gateway_url)
        end
      end)
    end,
  })
end

--- Check if there's an active request for a session
--- @param session_key string
--- @return boolean
function M.has_active_request(session_key)
  return M.active_jobs[session_key] ~= nil
end

return M
