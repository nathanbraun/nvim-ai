# SUMMARY.md

## Project Overview
**nvim-ai** is a comprehensive Neovim plugin that provides AI-powered chat and content generation capabilities directly within the editor. It supports multiple AI providers (OpenAI, OpenRouter, Google, Ollama, OpenClaw), handles rich content blocks (web scraping, YouTube transcripts, file snapshots, directory trees), and includes verification features for response integrity.

**Target Users:** Neovim users who want to integrate AI assistance into their workflow, particularly for:
- Writing and editing with AI assistance
- Code generation and refactoring
- Content research (web scraping, YouTube transcripts)
- Document analysis and summarization

**Problem Solved:** Eliminates context-switching between editor and browser/AI tools by bringing AI chat, content gathering, and verification into Neovim.

---

## Architecture

### Design Patterns
- **State Management:** Centralized state with specialized managers (requests, buffers, indicators, UI)
- **Event System:** Pub/sub pattern for cross-component communication
- **Registry Pattern:** Extensible processor system for message types and block types
- **Module Pattern:** Clear separation of concerns with well-defined module boundaries

### Data Flow
1. **User Input** → Parser → Messages → API Module → Provider
2. **Provider Response** → State Update → Events → UI Update
3. **Block Expansion** → Processor Registry → Async/Sync Handlers → Buffer Update

### Key Architectural Decisions
- **Modular Provider System:** Each provider (OpenAI, Google, etc.) has standardized interface
- **Block Processor Registry:** Extensible system for handling different content types
- **State Isolation:** State managers are independent but coordinated through central facade
- **Async-First:** All network operations are asynchronous with proper cleanup

---

## Directory Structure

```
lua/nai/
├── init.lua                    # Main entry point, chat orchestration
├── api.lua                     # API request handling for all providers
├── config.lua                  # Configuration management, API key handling
├── constants.lua               # Marker definitions, shared constants
├── parser.lua                  # Message parsing, formatting
├── buffer.lua                  # Buffer activation, syntax application
├── syntax.lua                  # Syntax highlighting overlay
├── folding.lua                 # Custom folding for chat messages
├── mappings.lua               # Key mapping management
├── state.lua                  # Unified state facade
├── events.lua                 # Event system
├── verification.lua           # Response verification with signatures
├── validate.lua               # Configuration validation
├── openclaw.lua               # OpenClaw HTTP gateway integration
│
├── blocks/
│   └── expander.lua           # Block expansion orchestration
│
├── parser/
│   ├── registry.lua           # Message processor registry
│   └── processors/            # Message type handlers
│       ├── user.lua
│       ├── assistant.lua
│       ├── system.lua
│       ├── alias.lua
│       ├── reference.lua
│       ├── snapshot.lua
│       ├── tree.lua
│       ├── web.lua
│       ├── youtube.lua
│       ├── scrape.lua
│       └── crawl.lua
│
├── fileutils/                 # Content gathering utilities
│   ├── init.lua              # File management helpers
│   ├── block_processor.lua   # Shared block expansion logic
│   ├── reference.lua         # File reference expansion
│   ├── snapshot.lua          # File snapshot creation
│   ├── tree.lua              # Directory tree generation
│   ├── scrape.lua            # Web scraping via Dumpling
│   ├── crawl.lua             # Website crawling
│   ├── web.lua               # Simple web fetching
│   └── youtube.lua           # YouTube transcript fetching
│
├── state/                     # State management modules
│   ├── store.lua             # Core state store with validation
│   ├── requests.lua          # Active request tracking
│   ├── buffers.lua           # Buffer activation tracking
│   ├── indicators.lua        # UI indicator management
│   └── ui.lua                # UI state (provider, model)
│
├── utils/                     # Utility modules
│   ├── init.lua              # Text utilities, format_with_gq
│   ├── indicators.lua        # Spinner/progress indicators
│   ├── error.lua             # Error logging
│   ├── error_handler.lua     # Standardized error handling
│   └── path.lua              # Cross-platform path handling
│
├── tools/
│   └── picker.lua            # Model/file picker UI
│
└── tests/                     # Test suite
    ├── framework.lua         # Test framework
    ├── parser_tests.lua
    ├── config_tests.lua
    ├── integration_tests.lua
    └── fileutils_tests.lua

plugin/nvim-ai.lua             # Vim plugin entry point, commands
doc/nvim-ai.txt               # Vim help documentation
```

---

## Core Components

### 1. **init.lua** (Main Entry Point)
**Purpose:** Orchestrates chat flow, handles user commands  
**Key Functions:**
- `chat()` - Main chat function (validates buffer, expands blocks, sends API request)
- `cancel()` - Cancels active requests and cleans up indicators
- `new_chat()` - Creates new chat file with YAML header
- `expand_blocks()` - Expands special blocks without continuing chat

**Dependencies:** api, parser, buffer, state, events  
**Load-Bearing:** Yes - coordinates entire chat workflow

### 2. **api.lua** (API Request Handler)
**Purpose:** Unified interface for all AI providers  
**Key Functions:**
- `chat_request(messages, on_complete, on_error, chat_config)` - Sends request to provider
- `cancel_request(handle)` - Terminates active request

**Provider Support:**
- OpenAI (standard format)
- OpenRouter (standard format with provider/model naming)
- Google (custom format with `contents` array)
- Ollama (local with `options` structure)
- OpenClaw (HTTP gateway with SSE streaming)

**Dependencies:** config, state, events, openclaw  
**Load-Bearing:** Yes - all API communication flows through here

### 3. **parser.lua** (Message Parser)
**Purpose:** Converts buffer content to/from API message format  
**Key Functions:**
- `parse_chat_buffer(content, buffer_id)` - Extracts messages from buffer
- `process_alias_messages(messages)` - Applies alias configurations
- `replace_placeholders(content, buffer_id)` - Expands placeholders like `$FILE_CONTENTS`
- `format_*_message()` - Creates formatted message blocks

**Dependencies:** parser/registry, parser/processors/*  
**Load-Bearing:** Yes - critical for API communication

### 4. **state.lua** (State Management Facade)
**Purpose:** Unified interface to all state managers  
**Key Managers:**
- `requests` - Active API requests
- `buffers` - Activated buffers
- `indicators` - UI indicators (spinners)
- `ui` - Current provider/model

**Key Functions:**
- `register_request()`, `clear_request()` - Request lifecycle
- `activate_buffer()`, `deactivate_buffer()` - Buffer tracking
- `reset_processing_state()` - Cleanup all processing state
- `snapshot()`, `restore()` - State backup/restore

**Dependencies:** state/store, state/requests, state/buffers, state/indicators, state/ui  
**Load-Bearing:** Yes - all state coordination

### 5. **buffer.lua** (Buffer Management)
**Purpose:** Activates buffers, applies syntax/folding  
**Key Functions:**
- `activate_buffer(bufnr)` - Enables plugin features for buffer
- `deactivate_buffer(bufnr)` - Cleans up plugin features
- `detect_chat_markers(bufnr)` - Checks for chat content
- `should_activate_by_pattern(bufnr)` - Pattern-based activation

**Dependencies:** syntax, folding, mappings, state  
**Load-Bearing:** Yes - manages buffer lifecycle

### 6. **blocks/expander.lua** (Block Expansion Orchestrator)
**Purpose:** Coordinates expansion of all block types  
**Key Functions:**
- `register_processor(name, processor)` - Registers block handler
- `expand_all(buffer_id)` - Expands all unexpanded blocks
- `match_line(line)` - Finds processor for line

**Registered Processors:** snapshot, tree, scrape, crawl, youtube  
**Dependencies:** fileutils/* (auto-registers on load)  
**Load-Bearing:** Yes - extensibility point for content types

### 7. **fileutils/block_processor.lua** (Shared Block Logic)
**Purpose:** Common utilities for async/sync block expansion  
**Key Functions:**
- `expand_async_block(config)` - Handles async operations (scrape, crawl, youtube)
- `expand_sync_block(config)` - Handles sync operations (snapshot, tree)
- `create_indicator()`, `start_spinner()` - Progress indicators
- `parse_options()` - Extracts options from block comments

**Dependencies:** None (utility module)  
**Load-Bearing:** Yes - all block expansions use this

### 8. **verification.lua** (Response Verification)
**Purpose:** Cryptographic verification of AI responses  
**Key Functions:**
- `generate_hash(messages, response, context, algorithm_version)` - Creates SHA-256 hash
- `add_signature_after_response()` - Adds verification signature
- `verify_last_response()` - Checks response integrity
- `attach_change_detection()` - Monitors for modifications

**Dependencies:** config, parser, constants  
**Load-Bearing:** No - optional feature

### 9. **openclaw.lua** (OpenClaw Gateway)
**Purpose:** HTTP-based gateway for moltbot integration  
**Key Functions:**
- `chat_send(session_key, message, gateway_config, ...)` - Sends message via HTTP/SSE
- `cancel(session_key, gateway_url)` - Aborts active request
- `get_session_key(buffer_id)` - Manages session keys

**Dependencies:** config, state, events  
**Load-Bearing:** No - provider-specific

---

## Entry Points

### Commands (plugin/nvim-ai.lua)
- `:NAIChat` - Continue chat in current buffer
- `:NAINew` - Create new chat file
- `:NAICancel` - Cancel active request
- `:NAIExpand` - Expand blocks without continuing
- `:NAIModel` - Select model with picker
- `:NAIScrape <url>` - Insert scrape block
- `:NAITree [path]` - Insert tree block
- `:NAICrawl <url>` - Insert crawl block
- `:NAIYoutube <url>` - Insert YouTube block
- `:NAIReference [path]` - Insert reference block
- `:NAISnapshot` - Insert snapshot block
- `:NAIVerify` - Verify last response
- `:NAISignedChat` - Chat with forced verification
- `:NAISetKey <provider> [key]` - Set API key
- `:NAICheckKeys` - Show configured keys
- `:NAIBrowse` - Browse chat files

### Mappings (mappings.lua)
Default mappings (configurable):
- `<Leader>c` - Continue chat
- `<Leader>av` - Verified chat
- `<Leader>ai` - New chat
- `<Leader>ax` - Cancel
- `<Leader>ae` - Expand blocks
- `<Leader>am` - Select model
- `<Leader>ap` - Toggle provider
- `<Leader>ao` - Browse files

### Auto-Activation
- Patterns: `*.md`, `*.markdown`, `*.wiki`
- Marker detection: Activates on any file with `>>> user`, `<<< assistant`, etc.

---

## Dependencies

### Required
- **Neovim 0.9+** - For modern Lua API
- **curl** - API requests
- **sha256sum** - Response verification (Unix)

### Optional
- **html2text** or **lynx** - Web content formatting
- **ollama** - Local model support
- **tree** - Directory tree generation
- **telescope.nvim** - Model/file picker UI
- **snacks.nvim** - Alternative picker UI
- **fzf-lua** - Alternative picker UI

### Provider-Specific
- **OpenAI/OpenRouter/Google:** API key required
- **Ollama:** Local installation
- **OpenClaw:** Gateway URL configuration
- **Dumpling:** API key for scrape/crawl/youtube

---

## Configuration

### Config File
- Location: `~/.config/nvim-ai/credentials.json`
- Format: JSON with provider keys
- Permissions: 600 (Unix)

### Environment Variables
- `OPENAI_API_KEY`
- `GOOGLE_API_KEY`
- `OPENROUTER_API_KEY`
- `DUMPLING_API_KEY`
- `OLLAMA_API_KEY` (if remote)

### Key Options (config.lua)
```lua
{
  active_provider = "openrouter",
  active_model = "anthropic/claude-sonnet-4.5",
  providers = {
    openai = { endpoint, models, temperature, max_tokens },
    openrouter = { endpoint, models, temperature, max_tokens },
    google = { endpoint, models, temperature, max_tokens },
    ollama = { endpoint, models, temperature, max_tokens },
    openclaw = { gateways = { { name, gateway_url, thinking_level } } }
  },
  chat_files = {
    directory = "~/nvim-ai-notes",
    format = "{id}.md",
    auto_save = false,
    auto_title = true
  },
  verification = {
    enabled = false,
    highlight_verified = true
  },
  aliases = {
    translate = { system, user_prefix, config },
    refactor = { system, user_prefix },
    math = { system, config }
  }
}
```

---

## State & Data

### In-Memory State (state.lua)
- **Active Requests:** `{ request_id -> { status, provider, model, start_time } }`
- **Activated Buffers:** `{ bufnr -> true }`
- **Indicators:** `{ indicator_id -> { buffer_id, start_row, end_row, timer } }`
- **UI State:** `{ current_provider, current_model, is_processing }`

### Persistent Data
- **API Keys:** `~/.config/nvim-ai/credentials.json`
- **Verification Key:** `~/.local/share/nvim/nvim-ai/verification.key`
- **Chat Files:** `~/nvim-ai-notes/*.md` (configurable)

### Buffer-Local State
- `vim.b[bufnr].nai_verification_attached` - Change detection status
- `vim.b[bufnr].openclaw_session_key` - OpenClaw session key

---

## Integration Points

### APIs Consumed
- **OpenAI:** `https://api.openai.com/v1/chat/completions`
- **OpenRouter:** `https://openrouter.ai/api/v1/chat/completions`
- **Google:** `https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`
- **Ollama:** `http://localhost:11434/api/chat`
- **OpenClaw:** Custom HTTP gateway with SSE
- **Dumpling:** `https://app.dumplingai.com/api/v1/{scrape,crawl,get-youtube-transcript}`

### External Services
- **Dumpling AI:** Web scraping, crawling, YouTube transcripts
- **OpenClaw Gateway:** Moltbot integration via HTTP/SSE

### File System
- Reads: Configuration files, chat files, referenced files
- Writes: Chat files, API keys, verification key

---

## Known Quirks

### 1. **Platform-Specific Path Handling**
- Windows requires special handling for long paths and temp files
- Large payloads on Windows use temp file approach to avoid command line limits
- Path separators normalized across platforms (utils/path.lua)

### 2. **Provider Format Differences**
- Google uses `contents` array instead of `messages`
- Google role mapping: `assistant` → `model`
- OpenAI o3 model doesn't support temperature parameter
- Ollama uses `num_predict` instead of `max_tokens`

### 3. **State Management**
- Request cleanup happens in multiple places (api.lua, state.lua, error_handler.lua)
- Indicator cleanup requires both timer stop and namespace clear
- Buffer deactivation must handle invalid buffers gracefully

### 4. **Verification Limitations**
- Requires `sha256sum` on Unix (not available on all systems)
- Hash comparison is sensitive to whitespace/formatting changes
- Signature format changed from `v1` to `v1:<hash>` (backward compatible)

### 5. **Block Expansion**
- Async blocks (scrape, crawl, youtube) track active requests separately
- Sync blocks (snapshot, tree) execute immediately
- Ignore blocks (`>>> ignore` ... `<<< ignore`) skip processing

### 6. **Circular Dependencies**
- `utils/indicators.lua` must not require `nai` (uses `config` directly)
- `parser.lua` loads all processors on init (auto-registration)
- `blocks/expander.lua` requires processors to self-register

### 7. **Alias Processing**
- Aliases modify messages before API request
- System prompts from aliases override buffer system messages
- Config from aliases merges with buffer config (alias takes precedence)

### 8. **Auto-Title Feature**
- Appends instruction to system prompt for untitled chats
- Expects response to start with `Proposed Title: ...`
- Strips title instruction from verification hash

### 9. **Folding**
- Uses custom `foldexpr` that conflicts with markdown folding
- Stores original fold settings per window (not per buffer)
- Cleanup must check buffer validity before restoring

### 10. **OpenClaw Gateway**
- Uses HTTP/SSE instead of WebSocket (simpler but less efficient)
- Session keys stored in buffer frontmatter
- Combines consecutive user messages before sending

---

## Files That Change Together

### Provider Addition
- `config.lua` (defaults, validation)
- `api.lua` (request handling)
- `validate.lua` (validation rules)
- `tools/picker.lua` (model picker)

### Block Type Addition
1. Create processor in `fileutils/`
2. Register in `blocks/expander.lua` (auto-registers on load)
3. Add marker to `constants.lua`
4. Add processor to `parser/processors/`
5. Add syntax highlighting to `syntax.lua`
6. Add command to `plugin/nvim-ai.lua`

### State Manager Addition
1. Create manager in `state/`
2. Integrate in `state.lua` facade
3. Update `state.lua:debug()` and `snapshot()`

### UI Indicator Changes
- `utils/indicators.lua` (creation, animation)
- `syntax.lua` (highlight groups)
- `config.lua` (highlight configuration)

### Error Handling Changes
- `utils/error.lua` (logging)
- `utils/error_handler.lua` (standardized handling)
- `api.lua` (request errors)
- `fileutils/block_processor.lua` (block errors)

---

## Load-Bearing vs. Utility

### Load-Bearing (Critical Path)
- `init.lua` - Chat orchestration
- `api.lua` - API communication
- `parser.lua` - Message format conversion
- `state.lua` - State coordination
- `buffer.lua` - Buffer lifecycle
- `blocks/expander.lua` - Block expansion
- `fileutils/block_processor.lua` - Block utilities

### Utility (Helper)
- `utils/indicators.lua` - UI feedback
- `utils/path.lua` - Path handling
- `utils/error.lua` - Logging
- `tools/picker.lua` - Model selection
- `syntax.lua` - Highlighting
- `folding.lua` - Folding
- `verification.lua` - Optional feature

### Provider-Specific
- `openclaw.lua` - OpenClaw only
- `fileutils/scrape.lua` - Dumpling only
- `fileutils/crawl.lua` - Dumpling only
- `fileutils/youtube.lua` - Dumpling only

---

## Testing

### Test Framework (tests/framework.lua)
- Custom assertion library
- Test result tracking
- Floating window display

### Test Files
- `parser_tests.lua` - Message parsing, formatting
- `config_tests.lua` - Configuration loading, API keys
- `integration_tests.lua` - End-to-end chat flow
- `fileutils_tests.lua` - Path expansion, snapshots
- `test_state_*.lua` - State manager unit tests

### Running Tests
- `:NAITest` - All tests
- `:NAITest parser` - Specific group
- `require('nai.tests').run_all()` - Programmatic
