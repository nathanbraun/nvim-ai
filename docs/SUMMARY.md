# SUMMARY.md

## Project Overview

**nvim-ai** is a Neovim plugin that provides an AI chat interface directly within the editor. It allows users to:

- Have conversations with AI models (OpenAI, OpenRouter, Google, Ollama) in markdown files
- Include file references, web scrapes, YouTube transcripts, and directory trees as context
- Use custom aliases for predefined prompts/configurations
- Verify response integrity with cryptographic signatures

**Target users**: Neovim users who want AI assistance integrated into their editing workflow.

**Problem solved**: Eliminates context-switching between editor and AI tools by bringing the AI conversation into markdown files.

---

## Architecture

### Design Patterns
- **Module pattern**: Each file exports a table `M` with public functions
- **Registry pattern**: Parser processors and block expanders use registries for extensibility
- **Manager pattern**: State is divided into domain-specific managers (requests, buffers, indicators, UI)
- **Facade pattern**: `state.lua` provides unified access to all state managers

### Data Flow
```
User Input → Buffer Detection → Parser → API Request → Response → Buffer Update
                ↓
         Block Expansion (scrape/youtube/tree/etc.)
                ↓
         State Management (tracking requests, buffers, indicators)
```

### Key Architectural Decisions
1. **Markdown-based chat format**: Uses `>>> user` / `<<< assistant` markers instead of custom filetype
2. **Async-first**: All API calls and external operations are non-blocking
3. **Provider-agnostic**: Unified interface for multiple AI providers
4. **Modular state**: Separate managers with a unified facade for testability

---

## Directory Structure

```
lua/nai/
├── init.lua              # Main entry point, orchestrates all functionality
├── api.lua               # HTTP requests to AI providers (LOAD-BEARING)
├── parser.lua            # Parses chat buffers into API messages (LOAD-BEARING)
├── config.lua            # Configuration management and API keys (LOAD-BEARING)
├── state.lua             # Unified state facade (LOAD-BEARING)
├── buffer.lua            # Buffer activation and detection
├── constants.lua         # Marker definitions (>>> user, <<< assistant, etc.)
├── events.lua            # Simple pub/sub event system
├── folding.lua           # Custom fold expressions for chat blocks
├── mappings.lua          # Keybinding management
├── syntax.lua            # Syntax highlighting overlay
├── validate.lua          # Configuration validation
├── verification.lua      # Response signature verification
│
├── blocks/
│   └── expander.lua      # Registry for expandable block types
│
├── fileutils/
│   ├── init.lua          # File naming utilities
│   ├── block_processor.lua # Shared async/sync expansion logic (LOAD-BEARING)
│   ├── reference.lua     # File path expansion and reading
│   ├── snapshot.lua      # Point-in-time file captures
│   ├── scrape.lua        # Web scraping via Dumpling API
│   ├── youtube.lua       # YouTube transcript fetching
│   ├── tree.lua          # Directory tree generation
│   ├── crawl.lua         # Multi-page web crawling
│   └── web.lua           # Simple web fetching (legacy)
│
├── parser/
│   ├── registry.lua      # Message type processor registry
│   └── processors/       # Individual message type handlers
│       ├── user.lua, assistant.lua, system.lua
│       ├── alias.lua, reference.lua, snapshot.lua
│       ├── scrape.lua, youtube.lua, tree.lua, crawl.lua, web.lua
│
├── state/
│   ├── store.lua         # Core reactive store with subscriptions
│   ├── requests.lua      # Active API request tracking
│   ├── buffers.lua       # Activated buffer tracking
│   ├── indicators.lua    # UI indicator state
│   └── ui.lua            # Provider/model state
│
├── tools/
│   └── picker.lua        # Model/file picker (telescope/snacks/fzf-lua)
│
├── utils/
│   ├── init.lua          # Visual selection, text formatting
│   ├── indicators.lua    # Spinner/progress UI components
│   ├── error.lua         # Error logging utilities
│   ├── error_handler.lua # Standardized async error handling
│   └── path.lua          # Cross-platform path utilities
│
└── tests/                # Test framework and test files
```

---

## Core Components

### Load-Bearing Files (change with caution)

| File | Purpose | Key Exports | Dependents |
|------|---------|-------------|------------|
| `init.lua` | Main orchestrator | `setup()`, `chat()`, `cancel()`, `new_chat()`, `expand_blocks()` | Plugin entry, all commands |
| `api.lua` | AI provider communication | `chat_request()`, `cancel_request()` | `init.lua` |
| `parser.lua` | Buffer→messages conversion | `parse_chat_buffer()`, `format_*_message()`, `process_alias_messages()` | `init.lua`, `verification.lua` |
| `config.lua` | Configuration & credentials | `setup()`, `get_api_key()`, `get_provider_config()` | Nearly everything |
| `state.lua` | State management facade | All `register_*`, `clear_*`, `get_*` functions | `init.lua`, `api.lua`, `buffer.lua` |
| `block_processor.lua` | Async expansion framework | `expand_async_block()`, `expand_sync_block()` | All fileutils modules |

### Parser Processors

Each processor in `parser/processors/` handles one block type:
- **marker**: String or function to match the block start
- **role**: API role ("user", "system", "assistant")
- **process_content**: Optional content transformation
- **format**: How to render the block in the buffer

### State Managers

| Manager | Responsibility | Key Methods |
|---------|---------------|-------------|
| `requests` | Track active API calls | `register()`, `update()`, `clear()`, `has_active()` |
| `buffers` | Track activated buffers | `activate()`, `deactivate()`, `is_activated()` |
| `indicators` | Track UI spinners | `register()`, `update()`, `clear()` |
| `ui` | Provider/model selection | `set_provider()`, `set_model()`, `is_processing()` |

---

## Entry Points

### Plugin Entry
- `plugin/nvim-ai.lua` - Registers all user commands

### User Commands
| Command | Function | Description |
|---------|----------|-------------|
| `:NAIChat` | `init.chat()` | Continue conversation |
| `:NAINew` | `init.new_chat()` | Create new chat file |
| `:NAICancel` | `init.cancel()` | Cancel active request |
| `:NAIExpand` | `init.expand_blocks()` | Expand special blocks |
| `:NAIModel` | `picker.select_model()` | Model picker |
| `:NAIProvider` | `init.switch_provider()` | Provider picker |
| `:NAIBrowse` | `picker.browse_files()` | Chat file browser |
| `:NAISetKey` | (in plugin file) | Set API credentials |

### Keybindings (default)
- `<Leader>c` - Continue chat
- `<Leader>ai` - New chat
- `<Leader>ax` - Cancel
- `<Leader>ae` - Expand blocks
- `<Leader>am` - Select model
- `<Leader>ap` - Toggle provider

---

## Dependencies

### Required
- **curl** - HTTP requests to AI providers

### Optional (for enhanced features)
- **telescope.nvim** / **snacks.nvim** / **fzf-lua** - Model/file pickers
- **html2text** or **lynx** - Web content conversion (legacy web block)
- **tree** - Directory tree generation
- **sha256sum** - Response verification

### External Services
- **Dumpling AI** (`app.dumplingai.com`) - Web scraping, YouTube transcripts, crawling

---

## Configuration

### Config File
`~/.config/nvim-ai/credentials.json` - API keys for all providers

### Environment Variables
- `OPENAI_API_KEY`, `OPENROUTER_API_KEY`, `GOOGLE_API_KEY`, `OLLAMA_API_KEY`
- `DUMPLING_API_KEY` - For web scraping features

### Key Config Options
```lua
require('nai').setup({
  active_provider = "openrouter",  -- or "openai", "ollama", "google"
  active_model = "anthropic/claude-sonnet-4",
  chat_files = {
    directory = "~/nvim-ai-notes",
    auto_save = false,
    auto_title = true,
  },
  aliases = { ... },  -- Custom prompt shortcuts
  verification = { enabled = false },  -- Response signatures
})
```

---

## State & Data

### Runtime State (in memory)
- **Active requests**: Tracked in `state.requests`
- **Activated buffers**: Tracked in `state.buffers`
- **UI indicators**: Tracked in `state.indicators`
- **Provider/model**: Tracked in `state.ui`

### Persistent Data
- `~/.config/nvim-ai/credentials.json` - API keys
- `~/.local/share/nvim/nvim-ai/verification.key` - Signature pepper
- `~/nvim-ai-notes/` (configurable) - Chat files

### Buffer Format
Chat files are markdown with special markers:
```markdown
---
title: Chat Title
date: 2024-01-01
---

>>> user
User message here

<<< assistant
AI response here

>>> reference
/path/to/file.lua

>>> scrape
https://example.com
```

---

## Integration Points

### APIs Consumed
| Provider | Endpoint | Auth |
|----------|----------|------|
| OpenAI | `api.openai.com/v1/chat/completions` | Bearer token |
| OpenRouter | `openrouter.ai/api/v1/chat/completions` | Bearer token |
| Google | `generativelanguage.googleapis.com/v1beta/models/` | URL param |
| Ollama | `localhost:11434/api/chat` | None (local) |
| Dumpling | `app.dumplingai.com/api/v1/` | Bearer token |

### Events Emitted
- `request:start`, `request:complete`, `request:error`, `request:cancel`
- `buffer:activate`, `buffer:deactivate`
- `model:change`

---

## Known Quirks & Technical Debt

### Non-Obvious Decisions
1. **No streaming**: Responses come all at once, not streamed token-by-token
2. **Markdown files, not custom filetype**: Chose `.md` for compatibility with other tools
3. **Dumpling dependency**: Web scraping requires external service (no built-in alternative)
4. **Windows path handling**: Special cases throughout for Windows compatibility

### Workarounds
- `api.lua:L150-170`: Large payloads on Windows use temp files due to command line limits
- `reference.lua:L30-80`: Complex heuristics to distinguish glob patterns from literal brackets in paths
- `verification.lua`: Auto-title instruction stripped during hash generation to maintain verification

### Technical Debt
- **Circular dependency prevention**: `utils/indicators.lua` imports `config` directly, not through `nai`
- **Test coverage**: Integration tests use mock API, not real providers
- **Block processor duplication**: Some logic repeated between `block_processor.lua` and individual fileutils
- **Picker fallback chain**: Three different picker implementations (snacks/telescope/fzf-lua) with duplicated logic

### Files That Change Together
- `parser.lua` ↔ `parser/processors/*` ↔ `parser/registry.lua`
- `state.lua` ↔ `state/*.lua`
- `init.lua` ↔ `api.lua` (for request handling)
- `fileutils/*.lua` ↔ `blocks/expander.lua` (for new block types)
- `config.lua` ↔ `validate.lua` (for new config options)
