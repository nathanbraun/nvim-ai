# SUMMARY.md

## Project: nvim-ai - Neovim AI Chat Plugin

### Overall Purpose
nvim-ai is a comprehensive Neovim plugin that provides an interactive, buffer-based chat interface with multiple LLM providers (OpenAI, OpenRouter, Google, Ollama). It transforms markdown-style buffers into AI chat sessions with advanced features including:
- Multi-provider LLM integration with provider-specific formatting
- Syntax highlighting and folding for chat blocks
- Content expansion from external sources (web scraping, YouTube transcripts, file snapshots, directory trees)
- Placeholder replacement for dynamic content
- Response verification and formatting
- Async operations with visual feedback
- Configurable aliases for common workflows

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         User Interface                          │
│  (Neovim Buffer with Chat Markers & Special Blocks)            │
└────────────────────┬───────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Core Orchestration Layer                     │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────┐   │
│  │ init.lua     │  │ state.lua    │  │ events.lua         │   │
│  │ - setup()    │  │ - requests   │  │ - pub/sub system   │   │
│  │ - chat()     │  │ - buffers    │  │ - event emission   │   │
│  │ - cancel()   │  │ - indicators │  │                    │   │
│  └──────────────┘  └──────────────┘  └────────────────────┘   │
└────────────────────┬───────────────────────────────────────────┘
                     │
        ┌────────────┼────────────┐
        │            │            │
        ▼            ▼            ▼
┌──────────────┐ ┌──────────┐ ┌─────────────────┐
│ Buffer Mgmt  │ │  Parser  │ │   API/Provider  │
│ - activation │ │ - parse  │ │ - chat_request  │
│ - syntax     │ │ - format │ │ - multi-provider│
│ - folding    │ │ - expand │ │ - streaming     │
│ - indicators │ │          │ │                 │
└──────────────┘ └──────────┘ └─────────────────┘
        │            │            │
        └────────────┼────────────┘
                     │
        ┌────────────┴────────────┐
        │                         │
        ▼                         ▼
┌──────────────────┐    ┌─────────────────────┐
│  File Utilities  │    │  Configuration      │
│  - scrape        │    │  - providers        │
│  - youtube       │    │  - credentials      │
│  - snapshot      │    │  - options          │
│  - tree          │    │  - validation       │
│  - crawl         │    │                     │
│  - reference     │    │                     │
└──────────────────┘    └─────────────────────┘
```

### Module Summaries

#### 1. API/Provider Module
**Location:** `lua/nai/api.lua`, `lua/nai/config.lua`, `lua/nai/state.lua`, `lua/nai/events.lua`

**Purpose:** Handles all LLM provider communication and state management.

**Key Capabilities:**
- Multi-provider support (OpenAI, OpenRouter, Google, Ollama)
- Provider-specific request/response formatting
- Credential management (environment variables, JSON file, legacy files)
- Request lifecycle tracking (pending, completed, error, cancelled)
- Event emission for request status changes
- Platform-specific handling (Windows temp files for large payloads)
- Async request management with cancellation support

**Key Interfaces:**
```lua
-- Make API request
api.chat_request(messages, on_complete, on_error, chat_config)

-- Configuration
config.setup(opts)
config.get_api_key(provider)
config.save_credential(provider, api_key)

-- State management
state.register_request(request_id, data)
state.activate_buffer(bufnr)
state.has_active_requests()

-- Events
events.on('request:complete', callback)
events.emit('request:start', request_id, provider, model)
```

**See:** [SUMMARY-API.md](SUMMARY-API.md) for detailed documentation.

#### 2. Buffer Management Module
**Location:** `lua/nai/buffer.lua`, `lua/nai/syntax.lua`, `lua/nai/folding.lua`, `lua/nai/utils/indicators.lua`

**Purpose:** Manages the interactive chat experience within Neovim buffers.

**Key Capabilities:**
- Automatic buffer activation (pattern matching or marker detection)
- Syntax highlighting overlay (preserves base filetype)
- Chat block folding (user/assistant/system messages)
- Animated loading indicators with progress stats
- Window-specific folding settings
- Debounced syntax updates
- Buffer lifecycle management

**Key Interfaces:**
```lua
-- Buffer lifecycle
buffer.activate_buffer(bufnr)
buffer.should_activate(bufnr)
buffer.apply_syntax_overlay(bufnr)

-- Syntax
syntax.apply_to_buffer(bufnr)  -- Returns namespace_id

-- Folding
folding.apply_to_buffer(bufnr)
folding.get_fold_level(lnum)

-- Indicators
indicators.create_assistant_placeholder(bufnr, row)
indicators.update_stats(indicator, {tokens = 150})
indicators.remove(indicator)
```

**See:** [SUMMARY-BUFFER.md](SUMMARY-BUFFER.md) for detailed documentation.

### 3. Parser & File Utilities (`lua/nai/parser.lua`, `lua/nai/parser/`, `lua/nai/fileutils/`)

**Architecture (as of 2025-12-03):** Uses a registry-based processor system where each message/block type has its own processor module. This eliminates code duplication and makes adding new block types trivial.

**Structure:**
```
parser.lua (main orchestrator, ~360 lines)
    ↓
parser/registry.lua (processor registry)
    ↓
parser/processors/ (12 processor modules)
    ├── user.lua, assistant.lua, system.lua (core messages)
    ├── tree.lua, alias.lua (simple blocks)
    └── reference.lua, snapshot.lua, web.lua, youtube.lua, 
        crawl.lua, scrape.lua (complex blocks with fileutils integration)
```

**Key Responsibilities:**
- Parse chat buffer content into API message arrays using registry
- Format messages for buffer display via processor delegation
- Handle special cases (config, YAML headers, ignore blocks)
- Process aliases and extract chat-specific configuration
- Coordinate with fileutils modules for special block processing

**Processor Interface:**
```lua
{
  marker = ">>> user" or function(line),  -- Pattern matching
  role = "user"|"assistant"|"system",     -- API role
  process_content = function(text_buffer), -- Optional special processing
  format = function(content),              -- Buffer formatting
  parse_line = function(line)              -- Optional extra data extraction
}
```

**Benefits:**
- Adding new block types requires only creating a processor file and registering it
- 60-70% reduction in repetitive code compared to previous implementation
- Each block type's parsing and formatting logic consolidated in one place
- Consistent interface across all message/block types

**Fileutils Integration:**
Complex processors (reference, snapshot, web, youtube, crawl, scrape) delegate to existing fileutils modules for content processing while handling their own marker matching and formatting.

**See:** SUMMARY-PARSER.md for detailed architecture, processor interface, and examples

#### 4. Block Expansion System
**Location:** `lua/nai/blocks/expander.lua`, `lua/nai/fileutils/*.lua`

**Purpose:** Centralized system for detecting and expanding special content blocks in chat buffers.

**Architecture:**
- **Registry Pattern**: Block processors register themselves when their modules load
- **Common Expansion Loop**: Handles finding boundaries, line offset tracking, error handling
- **Pluggable Interface**: Each block type implements a simple interface

**Block Processor Interface:**
```lua
{
  marker = function(line) or "string",  -- Detection pattern
  has_unexpanded = function(buffer_id), -- Check for unexpanded blocks
  expand = function(buffer_id, start_line, end_line), -- Expansion logic
  has_active_requests = function() or nil  -- Optional: async check
}
```

**Registered Block Types:**
- **snapshot**: Expands file paths to file contents with syntax highlighting
- **youtube**: Fetches video transcripts via Dumpling API
- **tree**: Generates directory structure using tree command
- **scrape**: Fetches web content via Dumpling API
- **crawl**: Multi-page website crawling via Dumpling API

**Key Interfaces:**
```lua
-- Register a new block type
expander.register_processor(name, processor)

-- Expand all registered block types in buffer
expander.expand_all(buffer_id)  -- Returns true if any blocks expanded

-- Individual block modules auto-register on load:
require('nai.fileutils.snapshot')  -- Registers 'snapshot' processor
require('nai.fileutils.youtube')   -- Registers 'youtube' processor
-- etc.
```

**Benefits:**
- **88% code reduction** in init.lua (200 lines → 25 lines)
- **Consistent behavior** across all block types
- **Easy extensibility**: New blocks require only ~10 lines of registration
- **Centralized error handling**: All blocks benefit from common error handling
- **Better testability**: Expander and processors can be tested independently

**Design Notes:**
- Block modules auto-register when loaded (lazy loading)
- `init.lua:expand_blocks()` explicitly requires all block modules to ensure registration
- Expander handles line offset tracking as blocks expand/contract
- Async blocks (scrape, crawl) report pending status separately
- Errors in one block don't prevent expansion of others

### Core Workflows

#### 1. Chat Interaction Flow
```
User types in buffer with >>> user marker
    ↓
User runs :NAIChat or mapping
    ↓
init.chat() called
    ↓
├─ Check if buffer activated → activate if needed
├─ Expand any unexpanded blocks (scrape, youtube, etc.)
├─ Parse buffer content → messages[]
├─ Replace placeholders if enabled
├─ Create assistant placeholder with indicator
├─ Register request in state
    ↓
api.chat_request(messages, on_complete, on_error, chat_config)
    ↓
├─ Format request for provider (OpenAI/Google/Ollama/OpenRouter)
├─ Make async curl request
├─ Emit 'request:start' event
    ↓
[Indicator animates while waiting]
    ↓
Response received
    ↓
├─ Parse provider-specific response format
├─ Sanitize content (escape sequences, YAML conflicts)
├─ Extract auto-title if present
├─ Format response with gq if enabled
├─ Remove indicator
├─ Insert formatted response into buffer
├─ Add verification signature if enabled
├─ Add new user message template
├─ Auto-save if enabled
├─ Emit 'request:complete' event
└─ Clear request from state
```

#### 2. Buffer Activation Flow
```
File opened (*.md, *.wiki, etc.)
    ↓
BufReadPost/FileType event
    ↓
buffer.should_activate(bufnr)
    ↓
├─ Check filename pattern match
└─ OR check for chat markers (if autodetect enabled)
    ↓
buffer.activate_buffer(bufnr)
    ↓
├─ Mark in state.activate_buffer(bufnr)
├─ Emit 'buffer:activate' event
├─ Apply buffer-local mappings
├─ Apply syntax overlay
│   └─ Define highlight groups
│   └─ Scan all lines for markers
│   └─ Apply highlights via extmarks
│   └─ Setup debounced TextChanged autocmd
├─ Apply folding
│   └─ Store original fold settings per-window
│   └─ Set foldmethod="expr"
│   └─ Set foldexpr to custom function
│   └─ Setup BufWinEnter/Leave autocmds
├─ Setup BufUnload cleanup
└─ Schedule deferred refresh (100ms)
```

#### 3. Special Block Expansion Flow
```
User includes special block in buffer:
>\>\> scrape-error
https://example.com

❌ Error fetching URL: https://example.com
Dumpling API Error: Unknown error

>\>\> config
model: gpt-4
temperature: 0.3
expand_placeholders: true

    ↓
Alias config (if using \>\>\> alias:)
    ↓
aliases = {
  translate = {
    system = "...",
    config = { model = "gpt-4o-mini", temperature = 0.1 }
  }
}

    ↓
Global config (lowest priority)
    ↓
require('nai').setup({
  active_provider = "openrouter",
  active_model = "anthropic/claude-sonnet-4.5",
  providers = { ... }
})
```

### Data Flow Patterns

#### Message Format
```lua
-- Buffer format:
 ---
title: My Chat
date: 2024-01-15
 ---

>\>\> user

What is Lua?

<<< assistant

Lua is a lightweight scripting language...

-- Parsed to API format:
{
  { role = "system", content = "You are a general assistant." },
  { role = "user", content = "What is Lua?" },
  { role = "assistant", content = "Lua is a lightweight scripting language..." }
}
```

#### Provider-Specific Formats
```lua
-- OpenAI/OpenRouter:
{
  model = "gpt-4",
  messages = [...],
  temperature = 0.7,
  max_tokens = 10000
}

-- Google:
{
  contents = [
    { role = "user", parts = [{ text = "..." }] },
    { role = "model", parts = [{ text = "..." }] }
  ],
  generationConfig = { temperature = 0.7, maxOutputTokens = 8000 }
}

-- Ollama:
{
  model = "llama3.2",
  messages = [...],
  options = { temperature = 0.7, num_predict = 4000 },
  stream = false
}
```

#### State Structure
```lua
state = {
  active_requests = {
    ["1234567_5678"] = {
      id = "1234567_5678",
      type = "chat",
      status = "pending"|"completed"|"error"|"cancelled",
      start_time = 1234567890,
      end_time = 1234567900,
      provider = "openrouter",
      model = "anthropic/claude-sonnet-4.5",
      messages = [...],
      response = "...",
      error = "..."
    }
  },
  
  active_indicators = {
    ["indicator_123_10"] = {
      buffer_id = 123,
      start_row = 10,
      spinner_row = 13,
      end_row = 15,
      timer = uv_timer,
      stats = { tokens = 150, elapsed_time = 3, model = "..." }
    }
  },
  
  activated_buffers = {
    [123] = true,
    [456] = true
  },
  
  ui_state = {
    is_processing = true,
    current_provider = "openrouter",
    current_model = "anthropic/claude-sonnet-4.5"
  }
}
```

### Configuration Structure

#### Complete Setup Example
```lua
require('nai').setup({
  -- Provider settings
  active_provider = "openrouter",
  active_model = "anthropic/claude-sonnet-4.5",
  
  -- Credentials
  credentials = {
    file_path = "~/.config/nvim-ai/credentials.json"
  },
  
  -- Buffer activation
  active_filetypes = {
    patterns = { "*.md", "*.markdown", "*.wiki" },
    autodetect = true,
    enable_overlay = true,
    enable_folding = true
  },
  
  -- Provider configurations
  providers = {
    openai = {
      temperature = 0.7,
      max_tokens = 10000,
      endpoint = "https://api.openai.com/v1/chat/completions",
      models = { "gpt-4", "o3" }
    },
    openrouter = {
      temperature = 0.7,
      max_tokens = 10000,
      endpoint = "https://openrouter.ai/api/v1/chat/completions",
      models = { "anthropic/claude-sonnet-4.5", ... }
    },
    google = {
      temperature = 0.7,
      max_tokens = 8000,
      endpoint = "https://generativelanguage.googleapis.com/v1beta/models/",
      models = { "gemini-2.0-flash", ... }
    },
    ollama = {
      temperature = 0.7,
      max_tokens = 4000,
      endpoint = "http://localhost:11434/api/chat",
      models = { "llama3.2:latest" }
    }
  },
  
  -- Chat file settings
  chat_files = {
    directory = "~/nvim-ai-notes",
    format = "{id}.md",
    auto_save = false,
    auto_title = true,
    header = {
      enabled = true,
      template = "---
title: {title}
date: {date}
tags: [ai]
---"
    }
  },
  
  -- External tools
  tools = {
    dumpling = {
      base_endpoint = "https://app.dumplingai.com/api/v1/",
      format = "markdown",
      cleaned = true,
      render_js = true,
      max_content_length = 100000
    }
  },
  
  -- Aliases for common workflows
  aliases = {
    translate = {
      system = "You are an interpreter. Translate to Spanish.",
      user_prefix = "",
      config = { model = "openai/gpt-4o-mini", temperature = 0.1 }
    },
    refactor = {
      system = "You are a coding expert. Refactor code...",
      user_prefix = "Refactor the following code:"
    }
  },
  
  -- Response formatting (continued)
  format_response = {
    enabled = false,
    wrap_width = 80,
    exclude_code_blocks = true
  },
  
  -- Placeholder expansion
  expand_placeholders = false,
  
  -- Verification
  verification = {
    enabled = false,
    highlight_verified = true
  },
  
  -- Syntax highlighting colors
  highlights = {
    user = { fg = "#88AAFF", bold = true },
    assistant = { fg = "#AAFFAA", bold = true },
    system = { fg = "#FFAA88", bold = true },
    special_block = { fg = "#AAAAFF", bold = true },
    error_block = { fg = "#FF8888", bold = true },
    content_start = { fg = "#AAAAAA", italic = true },
    placeholder = { fg = "#FFCC66", bold = true },
    signature = { fg = "#777777", italic = true }
  },
  
  -- Key mappings
  mappings = {
    enabled = true,
    intercept_ctrl_c = true
  },
  
  -- Debug options
  debug = {
    enabled = false,
    verbose = false,
    auto_title = false
  }
})
```

### Key Design Patterns

#### 1. Overlay Architecture
The plugin uses a layered approach that preserves the base functionality:
- **Base Layer**: Native Neovim filetype (markdown, vimwiki)
- **Syntax Overlay**: Custom highlights in separate namespace
- **Extmarks**: Indicators and decorations
- **Result**: Users get AI features + full markdown/vimwiki functionality

#### 2. Async with Visual Feedback
All potentially slow operations provide immediate feedback:
```lua
-- Pattern:
1. Create animated indicator
2. Register in state
3. Start async operation
4. Update indicator stats during operation
5. Remove indicator on completion
6. Replace placeholder with actual content
7. Clear from state
```

#### 3. Event-Driven Architecture
Decouples modules using pub/sub:
```lua
-- Modules emit events:
events.emit('request:start', request_id, provider, model)
events.emit('buffer:activate', bufnr, filename)

-- Other modules can listen:
events.on('request:complete', function(request_id, content)
  -- Update UI, log, etc.
end)
```

#### 4. State Centralization
All mutable state lives in `state.lua`:
- Active requests (with full lifecycle data)
- Active indicators (for cleanup)
- Activated buffers (for feature enabling)
- UI state (processing flag, current provider/model)

**Benefits:**
- Single source of truth
- Easy debugging (`state.debug()`)
- Clean module boundaries
- Safe concurrent operations

#### 5. Configuration Hierarchy
Settings can be specified at multiple levels:
```
Chat-specific config (\>\>\> config block)
    ↓ (overrides)
Alias config (>>> alias: name)
    ↓ (overrides)
Global config (setup() call)
    ↓ (overrides)
Default config (in config.lua)
```

#### 6. Platform Abstraction
Platform-specific code isolated in `utils/path.lua`:
```lua
-- Detection
path.is_windows  -- boolean

-- Operations
path.separator  -- "/" or "\"
path.expand(path)  -- Handles ~, env vars
path.join(...)  -- Platform-appropriate joining
path.mkdir(dir)  -- Recursive directory creation
```

**Special handling:**
- Windows: Temp files for large curl payloads
- Windows: Path normalization for separators
- Unix: Direct command piping

#### 7. Safe Buffer Operations
All buffer operations wrapped in safety checks:
```lua
-- Pattern:
if not vim.api.nvim_buf_is_valid(bufnr) then
  return
end

-- Use pcall for operations that might fail:
pcall(vim.api.nvim_buf_clear_namespace, bufnr, ns_id, 0, -1)

-- Check current buffer before cursor operations:
local current_buf = vim.api.nvim_get_current_buf()
if current_buf == bufnr then
  vim.api.nvim_win_set_cursor(0, {row, col})
end
```

#### 8. Debouncing for Performance
Expensive operations (syntax highlighting, folding) are debounced:
```lua
local debounce_timer = nil

local function debounced_operation(delay)
  if debounce_timer then
    debounce_timer:stop()
    debounce_timer:close()
  end
  
  debounce_timer = vim.loop.new_timer()
  debounce_timer:start(delay or 100, 0, vim.schedule_wrap(function()
    -- Expensive operation here
  end))
end
```

### Extension Points

#### Adding a New Provider
1. Add provider config to `config.defaults.providers`:
```lua
myprovider = {
  name = "MyProvider",
  temperature = 0.7,
  max_tokens = 10000,
  endpoint = "https://api.myprovider.com/v1/chat",
  models = { "model-1", "model-2" }
}
```

2. Add provider-specific formatting in `api.chat_request()`:
```lua
if provider == "myprovider" then
  data = {
    model = model,
    messages = messages,
    -- provider-specific fields
  }
end
```

3. Add response parsing in `api.chat_request()` callback:
```lua
if provider == "myprovider" then
  content = parsed.response.text  -- provider-specific path
end
```

#### Adding a New Special Block Type

**With the new expander system, adding a block type is much simpler:**

1. Add marker to `constants.lua`:
```lua
M.MARKERS = {
  -- ... existing markers
  MYBLOCK = ">>> myblock"
}
```

2. Create processor in `fileutils/myblock.lua`:
```lua
local M = {}
local block_processor = require('nai.fileutils.block_processor')

function M.expand_myblock_in_buffer(bufnr, start_line, end_line)
  -- Use block_processor helpers for sync or async expansion
  return block_processor.expand_sync_block({
    buffer_id = bufnr,
    start_line = start_line,
    end_line = end_line,
    block_type = "myblock",
    progress_marker = ">>> myblocking",
    completed_marker = ">>> myblocked",
    error_marker = ">>> myblock-error",
    
    execute = function(lines, options)
      -- Your expansion logic here
      local result = process_content(lines)
      return result, nil  -- result, error
    end,
  })
end

function M.has_unexpanded_myblock_blocks(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for _, line in ipairs(lines) do
    if line == ">>> myblock" then
      return true
    end
  end
  return false
end

function M.process_myblock_block(lines)
  -- For API requests, return already-expanded content
  return table.concat(lines, "
")
end

-- Register with expander (auto-runs on module load)
local function register_with_expander()
  local expander = require('nai.blocks.expander')
  
  expander.register_processor('myblock', {
    marker = ">>> myblock",
    has_unexpanded = M.has_unexpanded_myblock_blocks,
    expand = M.expand_myblock_in_buffer,
  })
end

register_with_expander()

return M
```

3. Add to parser in `parser.lua` (for API request processing):
```lua
elseif line:match("^" .. vim.pesc(MARKERS.MYBLOCK)) then
  current_message = { role = "user" }
  current_type = "myblock"
  
-- In final processing:
elseif current_type == "myblock" then
  local myblock_module = require('nai.fileutils.myblock')
  current_message.content = myblock_module.process_myblock_block(text_buffer)
```

4. Add syntax highlighting in `syntax.lua`:
```lua
elseif line:match("^>>> myblock") then
  vim.api.nvim_buf_add_highlight(bufnr, ns_id, "naichatSpecialBlock", line_nr, 0, #line)
```

**That's it!** The expander system automatically:
- Detects your block type when `expand_blocks()` is called
- Handles block boundary detection
- Manages line offset tracking
- Provides error handling
- Reports expansion results

**No changes needed to `init.lua`** - it automatically picks up registered processors.

4. Add expansion check in `init.lua`:
```lua
function M.expand_blocks(buffer_id)
  -- ... existing checks
  
  local myblock = require('nai.fileutils.myblock')
  if myblock.has_unexpanded_myblock_blocks(buffer_id) then
    -- Expand blocks
    expanded_something = true
  end
  
  return expanded_something
end
```

5. Add syntax highlighting in `syntax.lua`:
```lua
elseif line:match("^>>> myblock") then
  vim.api.nvim_buf_add_highlight(bufnr, ns_id, "naichatSpecialBlock", line_nr, 0, #line)
```

#### Adding a New Alias
Simply add to config:
```lua
require('nai').setup({
  aliases = {
    myalias = {
      system = "You are a specialist in X. Do Y.",
      user_prefix = "Optional prefix for user message:",
      config = {
        model = "specific/model",
        temperature = 0.5,
        expand_placeholders = true
      }
    }
  }
})
```

Usage in buffer:
```
\>\>\> alias: myalias

User's actual question here
```

Expands to:
```
\>\>\> system

You are a specialist in X. Do Y.

\>\>\> user

Optional prefix for user message:

User's actual question here
```

### Common User Workflows

#### 1. Quick Question
```
:NAIChat What is Lua?
```
- Creates new buffer with question
- Auto-generates filename
- Sends to active provider/model
- Displays response

#### 2. Chat with Context from Files
```markdown
 ---
title: Code Review
 ---

\>\>\> snapshot

src/**/*.lua

\>\>\> user

Review these files for best practices
```
- Snapshot expands to file contents with syntax highlighting
- Sent as single user message with all context
- Response saved in chat file

#### 3. Web Research
```markdown
\>\>\> scrape

https://example.com/article

\>\>\> user

Summarize the key points from this article
```
- Scrape block fetches article via Dumpling API
- Converts to markdown
- Includes in context for AI
- AI summarizes based on fetched content

#### 4. YouTube Analysis
```markdown
\>\>\> youtube

https://youtube.com/watch?v=...
-- timestamps: true
-- language: en

\>\>\> user

What are the main topics discussed?
```
- Fetches transcript via Dumpling API
- Includes timestamps
- AI analyzes transcript content

#### 5. Multi-turn Conversation
```markdown
\>\>\> user

Explain async programming

<<< assistant

Async programming allows...

\>\>\> user

Show me an example in Lua
```
- Each turn preserved in buffer
- Full context sent to API
- Conversation continues naturally

#### 6. Using Aliases
```markdown
\>\>\> alias: translate

The weather is nice today
```
- Expands to system message + user message
- Uses alias-specific model/temperature
- Efficient for repeated workflows

#### 7. Custom Configuration
```markdown
\>\>\> config
model: openai/o3
temperature: 0.1
max_tokens: 5000

\>\>\> user

Solve this complex problem...
```
- Overrides global settings for this chat
- Settings persist for entire conversation
- Can switch providers/models mid-chat

### Error Handling Strategy

#### 1. Graceful Degradation
```lua
-- Pattern used throughout:
local success, result = pcall(risky_operation)
if not success then
  -- Log error
  -- Provide fallback
  -- Notify user
  return safe_default
end
```

#### 2. User-Facing Errors
All errors shown in buffer with clear formatting:
```markdown
\>\>\> scrape-error

https://example.com

❌ Error fetching URL: https://example.com
Dumpling API Error: Invalid API key
```

#### 3. State Cleanup
Errors don't leave orphaned state:
```lua
-- Always in finally-style blocks:
state.clear_request(request_id)
state.clear_indicator(indicator_id)
if timer then
  timer:stop()
  timer:close()
end
```

#### 4. Validation
Config validation on setup:
```lua
local validator = require('nai.validate')
local valid = validator.apply_validation(M.options)
if not valid then
  vim.notify("Using default configuration due to validation errors", 
    vim.log.levels.WARN)
end
```

### Performance Considerations

#### 1. Async Operations
- All network requests are async (vim.system)
- UI remains responsive during API calls
- Multiple requests can run concurrently

#### 2. Debouncing
- Syntax highlighting: 100ms debounce on text changes
- Prevents excessive re-highlighting during typing

#### 3. Content Limits
- Scrape: 100KB max content length
- File reading: 500KB max per file
- Truncation with clear indication

#### 4. Request Throttling
- File pattern expansion: 100 files max
- Safety checks for broad patterns (/, C:\)
- User warnings for large expansions

#### 5. Lazy Loading
- Modules loaded on demand
- File utilities only loaded when blocks used
- Minimal startup overhead

### Security Considerations

#### 1. Credential Storage
- JSON file with 600 permissions (Unix)
- Environment variables preferred
- No credentials in plugin code
- Clear documentation about security

#### 2. Command Injection Prevention
- All shell commands use vim.fn.shellescape()
- URL validation before fetching
- Path expansion with bounds checking

#### 3. Content Sanitization
- API responses sanitized for YAML conflicts
- Escape sequences properly handled
- Binary file detection and skipping

#### 4. Rate Limiting
- File expansion limits
- Content size limits
- User warnings for potentially expensive operations

### Testing Strategy

#### 1. Module Tests
Located in `lua/nai/tests.lua`:
```lua
function M.run_all()
  -- Test each module independently
  -- Mock external dependencies
  -- Verify state transitions
end
```

#### 2. Integration Tests
Test complete workflows:
- Buffer activation → syntax → folding
- Message parsing → API request → response formatting
- Special block expansion → content insertion

#### 3. Manual Testing Commands
```vim
:NAIReload  " Reload plugin for development
:NAIActivate  " Force activate current buffer
:NAIDebug  " Show state information
```

### Troubleshooting Guide

#### Common Issues

**1. Buffer not activating**
- Check filename matches patterns
- Verify autodetect is enabled
- Use `:NAIActivate` to force
- Check for conflicting plugins

**2. API requests failing**
- Verify API key is set
- Check provider endpoint is reachable
- Look for error messages in buffer
- Enable debug mode: `debug = { enabled = true }`

**3. Syntax highlighting not working**
- Check `enable_overlay = true` in config
- Verify no conflicting syntax plugins
- Try `:NAIActivate` to reapply
- Check highlight group definitions

**4. Special blocks not expanding**
- Verify required tools installed (curl, tree, html2text)
- Check API keys for Dumpling-based blocks
- Look for error blocks in buffer
- Check file permissions for snapshot/reference

**5. Folding not working**
- Verify `enable_folding = true`
- Check for conflicting fold plugins
- Try `:set foldmethod=expr`
- Verify fold level with `:set foldlevel?`

#### Debug Mode
Enable verbose debugging:
```lua
require('nai').setup({
  debug = {
    enabled = true,
    verbose = true,  -- Shows curl commands and responses
    auto_title = true  -- Shows title generation logic
  }
})
```

Outputs:
- Request URLs and payloads
- Equivalent curl commands for manual testing
- Response parsing details
- State transitions

#### State Inspection
```lua
:lua vim.print(require('nai.state').debug())
```
Shows:
- Active request count
- Active indicator count
- Activated buffer count
- Current provider/model
- Processing status

### Future Extension Ideas

#### Potential Features
1. **Streaming Responses**: Real-time token display as they arrive
2. **Multi-modal Support**: Image inputs/outputs
3. **RAG Integration**: Vector database for context retrieval
4. **Conversation Branching**: Fork conversations at any point
5. **Template System**: Reusable conversation templates
6. **Export Formats**: PDF, HTML, plain text
7. **Collaborative Editing**: Share chats with team
8. **Cost Tracking**: Monitor API usage and costs
9. **Model Comparison**: Run same prompt on multiple models
10. **Voice Input/Output**: TTS/STT integration

#### Plugin Integrations
- **Telescope**: Browse chat history
- **nvim-cmp**: Autocomplete for aliases, models
- **which-key**: Show available commands
- **lualine**: Show current provider/model in statusline
- **nvim-notify**: Better notification styling

### File Structure Reference

```
lua/nai/
├── init.lua                 # Main entry point, orchestration
├── api.lua                  # API request handling
├── buffer.lua               # Buffer lifecycle management
├── config.lua               # Configuration and credentials
├── constants.lua            # Marker definitions
├── events.lua               # Event system (pub/sub)
├── folding.lua              # Chat block folding
├── mappings.lua             # Keybinding setup
├── parser.lua               # Message parsing and formatting
├── state.lua                # Centralized state management
├── syntax.lua               # Syntax highlighting overlay
├── validation.lua           # Config validation (referenced but not provided)
├── verification.lua         # Response verification (referenced but not provided)
├── tests.lua                # Test suite
├── blocks/
│   └── expander.lua        # Centralized block expansion system
├── utils/
│   ├── init.lua            # General utilities
│   ├── error.lua           # Error handling utilities
│   ├── indicators.lua      # Loading indicators
│   └── path.lua            # Platform-specific path utilities
└── fileutils/
    ├── init.lua            # Filename generation
    ├── crawl.lua           # Website crawling (registers with expander)
    ├── reference.lua       # File pattern expansion
    ├── scrape.lua          # Web scraping (registers with expander)
    ├── snapshot.lua        # File snapshots (registers with expander)
    ├── tree.lua            # Directory trees (registers with expander)
    ├── web.lua             # Simple web fetching
    └── youtube.lua         # YouTube transcripts (registers with expander)
```

### Quick Start for Developers

#### 1. Setup Development Environment
```lua
-- In your nvim config:
vim.opt.runtimepath:append("~/path/to/nvim-ai")

require('nai').setup({
  debug = { enabled = true, verbose = true }
})

-- Reload command for development:
vim.keymap.set('n', '<leader>nr', function()
  require('nai').reload()
  vim.notify('nvim-ai reloaded')
end)
```

#### 2. Understanding the Flow
Start by reading in this order:
1. `init.lua` - See the main workflows
2. `config.lua` - Understand configuration structure
3. `state.lua` - See what state is tracked
4. `api.lua` - Understand API communication
5. `buffer.lua` - See buffer management
6. `parser.lua` - Understand message transformation

#### 3. Making Changes
Common modification points:
- **New provider**: `config.lua` + `api.lua`
- **New special block**: `fileutils/` + `parser.lua` + `init.lua`
- **New highlight**: `config.lua` + `syntax.lua`
- **New alias**: Just config, no code changes needed
- **New command**: `init.lua` or create new module

#### 4. Testing Changes
```vim
" Reload plugin
:lua require('nai').reload()

" Test specific module
:lua require('nai.tests').test_parser()

" Inspect state
:lua vim.print(require('nai.state').debug())

" Force reactivate buffer
:NAIActivate
```

### Module Dependencies Graph

```
init.lua
├── config
├── api
│   ├── config
│   ├── state
│   ├── events
│   └── utils.error
├── utils
│   ├── utils.indicators
│   └── utils.path
├── buffer
│   ├── config
│   ├── state
│   ├── events
│   ├── constants
│   ├── syntax
│   ├── folding
│   ├── mappings
│   └── utils.error
├── parser
│   ├── config
│   ├── constants
│   └── fileutils.*
├── state
└── events

fileutils/
├── reference
│   ├── utils.error
│   └── utils.path
├── scrape
│   ├── config
│   └── utils
├── youtube
│   └── config
├── snapshot
│   └── fileutils.reference
├── tree
│   └── utils.path
├── crawl
│   └── config
└── web
    └── config
```

### Key Takeaways

1. **Modular Design**: Each module has clear responsibilities and minimal dependencies
2. **Async-First**: All slow operations are async with visual feedback
3. **State Management**: Centralized state makes debugging and testing easier
4. **Extensibility**: Easy to add providers, blocks, aliases without core changes
5. **Safety**: Extensive validation, error handling, and cleanup
6. **User Experience**: Immediate feedback, clear errors, intuitive workflows
7. **Platform Support**: Works on Windows, macOS, Linux with platform-specific optimizations

### Getting Help

- **Module Summaries**: See SUMMARY-.md files for detailed documentation
- **Debug Mode**: Enable for detailed logging
- **State Inspection**: Use `state.debug()` to see current state
- **Test Suite**: Run tests to verify functionality
- **Code Comments**: Most functions have inline documentation

 ---

## Directory Structure

❯ tree -I 'timer-reports|images|docs|doc'
.
├── CHANGELOG.md
├── CODEBASE_SUMMARY.md
├── LICENSE
├── lua
│   └── nai
│       ├── api.lua
│       ├── buffer.lua
│       ├── config.lua
│       ├── constants.lua
│       ├── events.lua
│       ├── fileutils
│       │   ├── crawl.lua
│       │   ├── init.lua
│       │   ├── reference.lua
│       │   ├── scrape.lua
│       │   ├── snapshot.lua
│       │   ├── tree.lua
│       │   ├── web.lua
│       │   └── youtube.lua
│       ├── folding.lua
│       ├── init.lua
│       ├── mappings.lua
│       ├── parser.lua
│       ├── state.lua
│       ├── syntax.lua
│       ├── tests
│       │   ├── config_tests.lua
│       │   ├── fileutils_tests.lua
│       │   ├── framework.lua
│       │   ├── init.lua
│       │   ├── integration_tests.lua
│       │   ├── mock_api.lua
│       │   └── parser_tests.lua
│       ├── tools
│       │   └── picker.lua
│       ├── utils
│       │   ├── error.lua
│       │   ├── indicators.lua
│       │   ├── init.lua
│       │   └── path.lua
│       ├── validate.lua
│       └── verification.lua
├── plugin
│   └── nvim-ai.lua
├── README.md

This summary provides a complete overview of the nvim-ai plugin architecture,
design patterns, and extension points. For detailed information about specific
modules, refer to the individual SUMMARY-*.md files.

