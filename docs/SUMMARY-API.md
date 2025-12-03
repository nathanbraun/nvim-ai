# SUMMARY-API.md

## Module: API/Provider Module

### Purpose and Scope
The API/Provider module is the core communication layer of nvim-ai, responsible for:
- Managing API requests to multiple LLM providers (OpenAI, OpenRouter, Google, Ollama)
- Handling provider-specific request/response formats
- Managing credentials and API keys
- Tracking request lifecycle and state
- Emitting events for request status changes

### Key Components and Files

#### 1. `lua/nai/api.lua` - API Request Handler
**Primary Responsibilities:**
- Orchestrates API requests to different providers
- Formats requests according to provider-specific schemas
- Handles streaming and non-streaming responses
- Manages request cancellation
- Sanitizes response content (escape sequences, YAML conflicts)
- Emits lifecycle events (start, complete, error, cancel)

**Key Functions:**
- `M.chat_request(messages, on_complete, on_error, chat_config)` - Main request function
  - Generates unique request IDs
  - Selects provider/model (chat-specific or global)
  - Formats data for provider (OpenAI, Google, Ollama, OpenRouter)
  - Registers request in state
  - Uses `vim.system()` with curl for HTTP requests
  - Handles Windows-specific issues (long command lines via temp files)
  - Processes responses asynchronously via callbacks
  
- `M.cancel_request(handle)` - Cancels active requests
  - Updates state to 'cancelled'
  - Terminates underlying curl process
  - Emits cancel event

**Provider-Specific Handling:**

```lua
-- OpenAI/OpenRouter (standard format)
{
  model = "...",
  messages = [...],
  temperature = 0.7,
  max_tokens = 10000
}

-- Google (different structure)
{
  contents = [
    { role = "user", parts = [{ text = "..." }] },
    { role = "model", parts = [{ text = "..." }] }
  ],
  generationConfig = { temperature = 0.7, maxOutputTokens = 8000 }
}

-- Ollama (local format)
{
  model = "...",
  messages = [...],
  options = { temperature = 0.7, num_predict = 4000 },
  stream = false
}

-- OpenAI o3 (special case - no temperature)
{
  model = "o3",
  messages = [...],
  max_completion_tokens = 10000
}
```

**Response Parsing:**
- OpenAI/OpenRouter: `parsed.choices[1].message.content`
- Google: `parsed.candidates[1].content.parts[1].text`
- Ollama: `parsed.message.content`

**Content Sanitization:**
- Converts `
` to actual newlines
- Handles other escape sequences (`	`, ``)
- Prefixes standalone `---` lines to prevent YAML parsing conflicts

#### 2. `lua/nai/config.lua` - Configuration Management
**Primary Responsibilities:**
- Stores default and user configuration
- Manages provider configurations
- Handles credential storage and retrieval
- Validates configuration
- Supports backward compatibility with old config formats

**Key Data Structures:**

```lua
M.defaults = {
  credentials = {
    file_path = "~/.config/nvim-ai/credentials.json"
  },
  active_provider = "openrouter",
  active_model = "anthropic/claude-sonnet-4.5",
  providers = {
    openai = { name, temperature, max_tokens, endpoint, models[] },
    openrouter = { ... },
    google = { ... },
    ollama = { ... }
  },
  chat_files = { directory, format, auto_save, auto_title, ... },
  tools = { dumpling = { ... } },
  highlights = { ... },
  aliases = { ... },
  verification = { ... },
  format_response = { ... }
}
```

**Key Functions:**
- `M.setup(opts)` - Merges user config with defaults, validates, initializes state
- `M.get_api_key(provider)` - Retrieves API key with fallback chain:
  1. Environment variable (`{PROVIDER}_API_KEY`)
  2. Credentials JSON file
  3. Legacy token files (backward compatibility)
- `M.save_credential(provider, api_key)` - Saves API key to JSON file with secure permissions
- `M.get_provider_config()` - Returns active provider's configuration
- `M.ensure_valid_ollama_model(provider_config)` - Validates Ollama model availability

**Credential Storage:**
- Single JSON file: `~/.config/nvim-ai/credentials.json`
- Format: `{ "openai": "sk-...", "openrouter": "sk-...", ... }`
- Permissions: 600 (owner read/write only)
- Environment variables take precedence

**Special Cases:**
- Ollama: Returns dummy key "local" for localhost endpoints
- Google: Supports `GOOGLE_API_KEY` environment variable
- Backward compatibility: Reads old `~/.config/{provider}.token` files

#### 3. `lua/nai/state.lua` - State Management
**Primary Responsibilities:**
- Tracks active API requests
- Manages UI indicators (loading animations)
- Records buffer activation state
- Maintains current provider/model
- Provides state query and debug functions

**State Structure:**
```lua
M = {
  active_requests = {},      -- { request_id = { id, type, status, start_time, provider, model, ... } }
  active_indicators = {},    -- { indicator_id = { buffer_id, start_row, end_row, timer, ... } }
  activated_buffers = {},    -- { bufnr = true }
  ui_state = {
    is_processing = false,
    current_provider = "openrouter",
    current_model = "anthropic/claude-sonnet-4.5"
  },
  chat_history = {}
}
```

**Key Functions:**
- `M.register_request(request_id, data)` - Adds request, sets processing flag
- `M.update_request(request_id, updates)` - Updates request fields
- `M.clear_request(request_id)` - Removes request, updates processing flag
- `M.activate_buffer(bufnr)` / `M.is_buffer_activated(bufnr)` - Buffer activation tracking
- `M.register_indicator(indicator_id, data)` / `M.clear_indicator(indicator_id)` - UI indicator tracking
- `M.reset_processing_state()` - Emergency reset (clears requests/indicators, keeps activated buffers)

**Request Lifecycle:**
1. Register: `status = 'pending'`
2. Update: `status = 'completed'|'error'|'cancelled'`
3. Clear: Remove from state

#### 4. `lua/nai/events.lua` - Event System
**Primary Responsibilities:**
- Provides pub/sub event system
- Decouples API module from UI/state updates
- Allows multiple listeners per event

**Key Functions:**
- `M.on(event_name, callback)` - Register listener, returns unsubscribe function
- `M.emit(event_name, ...)` - Notify all listeners (uses pcall for error isolation)

**Event Types:**
```lua
'request:start'    -- (request_id, provider, model)
'request:complete' -- (request_id, content)
'request:error'    -- (request_id, error_msg)
'request:cancel'   -- (request_id)
```

### Important Patterns/Conventions

#### 1. Async Request Pattern
```lua
-- Generate unique request ID
local request_id = tostring(os.time()) .. "_" .. tostring(math.random(10000))

-- Register in state
state.register_request(request_id, { ... })

-- Emit start event
events.emit('request:start', request_id, provider, model)

-- Make async request
vim.system(curl_args, { text = true }, function(obj)
  -- Process response
  
  -- Update state
  state.update_request(request_id, { status = 'completed', ... })
  
  -- Emit complete event
  events.emit('request:complete', request_id, content)
  
  -- Schedule callback
  vim.schedule(function()
    on_complete(content)
    state.clear_request(request_id)
  end)
end)
```

#### 2. Provider Selection Hierarchy
```lua
-- 1. Chat-specific config (highest priority)
local provider = chat_config and chat_config.provider

-- 2. Global active provider
provider = provider or config.options.active_provider

-- 3. Model selection
local model = chat_config and chat_config.model 
           or config.options.active_model
```

#### 3. Error Handling
- All errors go through `vim.schedule()` to safely update UI
- State updated before callbacks to ensure consistency
- Events emitted even on errors
- Requests cleared from state after callback completion

#### 4. Platform Compatibility
- Detects Windows vs Unix
- Windows: Uses temp files for large payloads (>8000 chars) to avoid command-line length limits
- Unix: Direct curl with data argument

### Dependencies on Other Modules

**Required by API Module:**
- `nai.config` - Provider configuration, API keys
- `nai.state` - Request tracking
- `nai.events` - Event emission
- `nai.utils.error` - Error handling utilities
- `nai.utils.path` - Path utilities, platform detection

**Used by:**
- `nai.init` - Main chat function calls `api.chat_request()`
- Any module needing to make LLM requests

### Entry Points and Main Interfaces

#### Public API
```lua
-- Make a chat request
api.chat_request(messages, on_complete, on_error, chat_config)
  -- Returns: { handle = request_id, terminate = function() }

-- Cancel a request
api.cancel_request(handle)
```

#### Configuration API
```lua
-- Setup (called once during plugin initialization)
config.setup(user_opts)

-- Get API key
config.get_api_key(provider)

-- Save credential
config.save_credential(provider, api_key)

-- Get active configuration
config.get_provider_config()
config.get_active_model()
```

#### State API
```lua
-- Request management
state.register_request(request_id, data)
state.update_request(request_id, updates)
state.clear_request(request_id)
state.get_active_requests()
state.has_active_requests()

-- Buffer management
state.activate_buffer(bufnr)
state.is_buffer_activated(bufnr)

-- Current settings
state.get_current_provider()
state.get_current_model()

-- Emergency reset
state.reset_processing_state()
```

#### Events API
```lua
-- Subscribe to events
local unsubscribe = events.on('request:complete', function(request_id, content)
  -- Handle completion
end)

-- Emit events (internal use)
events.emit('request:start', request_id, provider, model)
```

### Configuration Examples

#### Basic Setup
```lua
require('nai').setup({
  active_provider = "openrouter",
  active_model = "anthropic/claude-sonnet-4.5",
  credentials = {
    file_path = "~/.config/nvim-ai/credentials.json"
  }
})
```

#### Custom Provider Configuration
```lua
require('nai').setup({
  providers = {
    ollama = {
      endpoint = "http://my-server:11434/api/chat",
      temperature = 0.5,
      max_tokens = 8000,
      models = { "custom-model:latest" }
    }
  }
})
```

#### Chat-Specific Configuration (in YAML frontmatter)
```yaml
 ---
model: openai/gpt-4o
temperature: 0.3
max_tokens: 2000
provider: openrouter
 ---
```

### Debug Support
- `config.options.debug.enabled` - Enable debug notifications
- `config.options.debug.verbose` - Add curl `-v` flag for detailed HTTP logs
- Debug notifications show:
  - Request URLs
  - Request payloads
  - Curl commands (for manual testing)
  - Response details

