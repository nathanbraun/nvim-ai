# **nvim-ai ↔ moltbot Integration Summary**

## **What We Built**

A WebSocket bridge that allows nvim-ai (a Neovim plugin for AI chat) to connect to moltbot's Gateway instead of calling AI APIs directly. This enables:

- **Unified conversation history** - Sessions persist in moltbot, accessible from any channel
- **Full moltbot features** - Access to tools, thinking modes, multi-agent routing
- **Real-time streaming** - Responses stream character-by-character from moltbot
- **Flexible deployment** - nvim can connect to local or remote moltbot instances

---

## **Architecture**

```
┌─────────────┐
│   Neovim    │
│  (nvim-ai)  │
└──────┬──────┘
       │ Lua jobstart()
       ↓
┌─────────────────────┐
│  Python Process     │
│  (ws_client.py)     │
│  • WebSocket client │
│  • stdin → gateway  │
│  • gateway → stdout │
└──────┬──────────────┘
       │ WebSocket (wss://)
       ↓
┌─────────────────────┐
│  Moltbot Gateway    │
│  • Agent execution  │
│  • Session mgmt     │
│  • Tool access      │
└─────────────────────┘
```

**Data flow:**
1. User runs `:NAIChat` in nvim
2. `gateway.lua` sends JSON request to Python via stdin
3. Python forwards to moltbot Gateway over WebSocket
4. Gateway streams `agent` events back
5. Python prints events to stdout
6. Neovim reads stdout, accumulates response, writes to buffer

---

## **Key Files Created**

### **1. `~/.config/nvim/lua/nai/ws_client.py`**
**Purpose:** Python WebSocket bridge between nvim and moltbot

**Key features:**
- Connects to Gateway with SSL support
- Handles challenge-response authentication
- Bidirectional communication (stdin ↔ WebSocket ↔ stdout)
- Forwards `agent` events for streaming responses

**Critical sections:**
```python
async def connect(self):
    # Handles SSL, challenge-response auth
    # Sends connect request with client metadata
    
async def listen_gateway(self):
    # Reads WebSocket frames, forwards to stdout
    # IMPORTANT: Only print each frame ONCE!
    
async def listen_stdin(self):
    # Reads JSON requests from nvim, sends to gateway
```

**Dependencies:** `pip3 install websockets`

---

### **2. `lua/nai/gateway.lua`**
**Purpose:** Lua interface to Python WebSocket client

**Key features:**
- Manages Python subprocess lifecycle
- Translates nvim-ai requests → Gateway protocol
- Handles streaming responses via callbacks
- Session key management

**Critical functions:**
```lua
M.connect()
  -- Starts Python subprocess with jobstart()
  -- Handles stdout/stderr streams

M.chat_send(session_key, messages, on_stream, on_complete, on_error)
  -- Sends chat.send request to gateway
  -- Registers callbacks for streaming responses

M.handle_agent_event(payload)
  -- Processes agent events (stream: "assistant")
  -- Accumulates delta text, calls on_stream callback

M.get_session_key(buffer_id)
  -- Extracts session_key from frontmatter
  -- Generates new key if not found
```

**State management:**
- `pending_callbacks` - Maps request_id → {on_stream, on_complete, on_error}
- `gateway_connected` - Connection status flag
- `gateway_job` - Python subprocess handle

---

### **3. Modified `lua/nai/init.lua`** (lines ~410-450)
**Purpose:** Integrate moltbot path into main chat flow

**Key change:**
```lua
function M.chat(opts, force_signature)
  -- ... existing validation/parsing ...
  
  -- NEW: Check if moltbot mode is enabled
  local moltbot_config = config.options.moltbot or {}
  if moltbot_config.enabled then
    local gateway = require('nai.gateway')
    local session_key = gateway.get_session_key(buffer_id)
    
    local accumulated_response = ""
    local function on_stream(chunk, is_final)
      accumulated_response = accumulated_response .. chunk
      if is_final then
        handle_chat_response(buffer_id, request_data, accumulated_response, ...)
      end
    end
    
    return gateway.chat_send(session_key, messages, on_stream, ...)
  end
  
  -- Existing API path (OpenAI/OpenRouter/etc)
  api.chat_request(...)
end
```

**Behavior:**
- If `moltbot.enabled = true`, routes through gateway
- Otherwise, uses existing direct API calls
- Accumulates streaming response, shows spinner, writes final result

---

### **4. Config Changes in `lua/nai/config.lua`**
**Purpose:** Add moltbot configuration options

```lua
M.defaults = {
  -- ... existing config ...
  
  moltbot = {
    enabled = false,  -- Toggle moltbot vs direct API
    gateway_url = "ws://localhost:18789",  -- Gateway endpoint
    auth_token = nil,  -- Bearer token (if gateway requires auth)
    session_prefix = "nvim",  -- Session key prefix
    auto_connect = true,  -- Connect on first chat request
  },
}
```

**Usage:**
```lua
require('nai').setup({
  moltbot = {
    enabled = true,
    gateway_url = "wss://your-gateway.com",
    auth_token = "your-token-here"
  }
})
```

---

### **5. User Command (in `plugin/nvim-ai.lua`)**
**Purpose:** Toggle moltbot mode without restarting nvim

```lua
vim.api.nvim_create_user_command('NAIMoltbot', function(opts)
  local gateway = require('nai.gateway')
  local config = require('nai.config')
  
  if opts.args == "on" then
    config.options.moltbot.enabled = true
    gateway.connect()
  elseif opts.args == "off" then
    config.options.moltbot.enabled = false
    gateway.disconnect()
  elseif opts.args == "status" then
    local status = config.options.moltbot.enabled and "enabled" or "disabled"
    vim.notify("Moltbot mode: " .. status)
  end
end, { nargs = 1, complete = function() return {"on", "off", "status"} end })
```

**Commands:**
- `:NAIMoltbot on` - Enable moltbot mode
- `:NAIMoltbot off` - Use direct API
- `:NAIMoltbot status` - Check current mode

---

## **Protocol Details**

### **Gateway WebSocket Protocol**

**1. Connection handshake:**
```json
// Gateway sends challenge
{"type": "event", "event": "connect.challenge", "payload": {"nonce": "..."}}

// Client responds with connect request
{
  "type": "req",
  "id": "unique-request-id",
  "method": "connect",
  "params": {
    "minProtocol": 3,
    "maxProtocol": 3,
    "client": {"id": "cli", "version": "1.0.0", "platform": "darwin", "mode": "cli"},
    "auth": {"token": "your-token"}
  }
}

// Gateway responds with hello-ok
{"type": "res", "id": "...", "ok": true, "payload": {"type": "hello-ok", ...}}
```

**2. Chat request:**
```json
{
  "type": "req",
  "id": "nvim_123456_78910",
  "method": "chat.send",
  "params": {
    "sessionKey": "nvim:filename:1234567890",
    "message": "User's message text",
    "idempotencyKey": "nvim_123456_78910",
    "deliver": false,
    "timeoutMs": 300000
  }
}
```

**3. Streaming response:**
```json
// Initial response (contains runId)
{"type": "res", "id": "nvim_123456_78910", "ok": true, "payload": {"runId": "..."}}

// Stream events (multiple)
{
  "type": "event",
  "event": "agent",
  "payload": {
    "runId": "...",
    "sessionKey": "nvim:filename:1234567890",
    "stream": "assistant",
    "data": {"delta": "Hey"}  // Incremental text
  }
}

// Final event (signals completion)
{
  "type": "event",
  "event": "agent",
  "payload": {
    "runId": "...",
    "stream": "lifecycle",
    "data": {"phase": "end"}
  }
}
```

---

## **Session Management**

### **Session Key Format**
```
{prefix}:{filename}:{timestamp}
```

Example: `nvim:test-chat:1736895234`

### **Session Key Extraction (Future Enhancement)**

Currently generates new session key each time. **To persist sessions:**

Add to frontmatter:
```yaml
---
title: My Chat
date: 2024-01-15
session_key: nvim:my-chat:1234567890
---
```

Then `gateway.lua:get_session_key()` will extract and reuse it.

---

## **Important Implementation Details**

### **1. Duplicate Event Bug (FIXED)**

**Problem:** Text was duplicated (e.g., "HeyHey!! I I just...")

**Cause:** Python was printing events twice:
```python
elif frame_type == "event":
    await self.handle_event(frame)  # Prints once
    print(json.dumps(frame), flush=True)  # Prints again! ❌
```

**Fix:** Remove the second print - `handle_event()` already prints.

---

### **2. Streaming Accumulation Strategy**

**Why accumulate instead of real-time display?**
- Simpler implementation (no partial buffer updates)
- Avoids race conditions with syntax highlighting
- Spinner provides feedback during generation
- Can easily switch to real-time later

**To enable real-time streaming:**
```lua
-- In init.lua, modify on_stream callback:
local function on_stream(chunk, is_final)
  if not is_final then
    -- Update buffer in real-time (append chunk)
    append_to_indicator_position(chunk)
  else
    -- Final cleanup
  end
end
```

---

### **3. Authentication Flow**

**Challenge-response prevents replay attacks:**
1. Gateway sends random nonce
2. Client includes nonce + token in connect request
3. Gateway validates token + nonce freshness

**Token storage:**
- Store in config: `moltbot.auth_token`
- Or use environment variable: `MOLTBOT_TOKEN`

---

### **4. Error Handling**

**Connection failures:**
- Python exits → `on_exit` callback fires
- Lua detects `gateway_connected = false`
- User sees error: "Failed to connect to gateway"

**Request timeouts:**
- Gateway sends `state: "error"` event
- Lua calls `on_error` callback
- Buffer shows error message

**Cancellation:**
- User runs `:NAICancel`
- Lua sends `chat.abort` request
- Gateway stops agent execution

---

## **Configuration Examples**

### **Local moltbot (no auth):**
```lua
require('nai').setup({
  moltbot = {
    enabled = true,
    gateway_url = "ws://localhost:18789",
  }
})
```

### **Remote moltbot (with auth):**
```lua
require('nai').setup({
  moltbot = {
    enabled = true,
    gateway_url = "wss://your-gateway.com",
    auth_token = "your-bearer-token",
    session_prefix = "myname"
  }
})
```

### **Toggle modes dynamically:**
```lua
-- Use moltbot for this session
:NAIMoltbot on

-- Switch back to direct API
:NAIMoltbot off
```

---

## **Debugging**

### **Enable debug logging:**
```lua
require('nai').setup({
  debug = { enabled = true },
  moltbot = { enabled = true }
})
```

### **Check connection:**
```vim
:messages  " See connection status
:NAIMoltbot status  " Check if enabled
```

### **Python subprocess issues:**
```bash
# Test Python script directly
echo '{"type":"req","id":"test","method":"chat.send","params":{"sessionKey":"test","message":"hi","idempotencyKey":"test"}}' | \
  python3 ~/.config/nvim/lua/nai/ws_client.py wss://your-gateway.com your-token
```

### **Common issues:**

| Issue | Cause | Fix |
|-------|-------|-----|
| "WebSocket client not found" | Python script missing | Check `~/.config/nvim/lua/nai/ws_client.py` exists |
| "Python executable not found" | Wrong python path | Set `vim.g.python3_host_prog = "/path/to/python3"` |
| "Failed to connect" | Gateway unreachable | Check URL, firewall, SSL cert |
| Duplicate text | Double-printing events | Remove duplicate `print()` in Python |
| No response | Wrong event handling | Check `handle_agent_event()` logic |

---

## **Future Enhancements**

### **1. Session Persistence**
Save `session_key` to frontmatter after first request:
```lua
-- In gateway.lua after successful chat.send:
local frontmatter = get_frontmatter(buffer_id)
if not frontmatter.session_key then
  frontmatter.session_key = session_key
  update_frontmatter(buffer_id, frontmatter)
end
```

### **2. Real-Time Streaming**
Update buffer incrementally instead of accumulating:
```lua
local function on_stream(chunk, is_final)
  if not is_final then
    local current_text = get_indicator_text()
    update_indicator_text(current_text .. chunk)
  end
end
```

### **3. Tool Support**
Handle `agent` events with `stream: "tool"`:
```lua
if stream == "tool" then
  local tool_name = payload.data.name
  local tool_args = payload.data.args
  show_tool_notification(tool_name, tool_args)
end
```

### **4. Thinking Level Control**
Add to chat config:
```yaml
>>> config
thinking: high
```

Then pass to gateway:
```lua
request.params.thinking = chat_config.thinking
```

### **5. Multi-Agent Routing**
Specify agent ID in session key:
```lua
session_key = "agent:coding:nvim:filename:123"
```

---

## **Files to Include When Asking for Help**

**Minimal set (for quick context):**
1. `ws_client.py` - Python WebSocket bridge
2. `gateway.lua` - Lua interface
3. `init.lua` (lines 400-460) - Moltbot integration section
4. Config snippet showing `moltbot` settings

**Full set (for debugging):**
- All of the above
- `config.lua` - Full config with moltbot section
- `buffer.lua` - Buffer activation logic (if issues with detection)
- `utils/indicators.lua` - Spinner/placeholder logic (if display issues)

---

## **Quick Reference Commands**

```vim
" Enable moltbot mode
:NAIMoltbot on

" Start a chat (routes through moltbot if enabled)
:NAIChat

" Cancel ongoing request
:NAICancel

" Check status
:NAIMoltbot status

" Disable moltbot (use direct API)
:NAIMoltbot off
```

---

## **Key Takeaways**

1. **Python subprocess handles WebSocket** - Lua can't do native WebSocket, so we use jobstart() + Python
2. **stdin/stdout bridge** - JSON requests go to stdin, responses come from stdout
3. **Accumulate-then-display** - Simpler than real-time streaming, works reliably
4. **Session keys enable persistence** - Same conversation across nvim restarts
5. **Gateway protocol is request/response + events** - Responses are immediate, events are streaming

---

