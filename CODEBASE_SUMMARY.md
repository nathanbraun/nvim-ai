# nvim-ai

## Overview

nvim-ai is a comprehensive Neovim plugin that enables AI-powered interactions
directly within the editor. It provides a rich, markdown-based interface for
chatting with various AI models, managing conversations, and leveraging AI
capabilities for coding assistance, content generation, and information
retrieval.

The plugin supports multiple AI providers (OpenAI, OpenRouter, Google, Ollama),
offers specialized content blocks for web scraping, file references, YouTube
transcripts, and more, all while maintaining a clean, document-based interface
that integrates naturally with Neovim's editing workflow.

## Core Architecture

The plugin follows a modular architecture with clear separation of concerns:

### Entry Point and API (nai/init.lua)

This module exposes the main plugin API and handles high-level operations like:
- Plugin setup and initialization
- Chat functionality (`chat`, `new_chat`, `cancel`)
- Special block expansion
- Command registration
- Platform compatibility checks

The main `chat` function is the heart of the plugin, handling the flow from
user input to API request to response rendering.

### Configuration Management (nai/config.lua)

The configuration system provides:
- Comprehensive default settings
- Deep merging with user configuration
- Provider-specific settings
- API key management (from environment variables or credential files)
- Backwards compatibility with older config formats

Configuration covers everything from UI preferences to provider endpoints to
key mappings, allowing extensive customization.

### API Interaction (nai/api.lua)

This module abstracts away the differences between AI providers:
- Formats requests according to each provider's API specifications
- Handles authentication
- Manages request/response cycles
- Provides error handling and reporting
- Uses curl for HTTP requests with platform-specific optimizations

The main `chat_request` function adapts to different providers (OpenAI,
OpenRouter, Google, Ollama) by formatting parameters appropriately for each
API.

### State Management (nai/state.lua)

The state module maintains the plugin's runtime state:
- Tracks active API requests
- Manages UI indicators
- Maintains a list of activated buffers
- Stores provider/model selections
- Provides methods to query and update state

This centralized state management helps coordinate asynchronous operations and
maintain consistency across the plugin.

### Buffer Management (nai/buffer.lua)

This module handles buffer-specific operations:
- Detects chat markers in buffers
- Activates/deactivates buffers for AI functionality
- Applies syntax highlighting and folding
- Sets up buffer-local commands and mappings
- Manages buffer-specific autocmds

The activation system allows the plugin to work with both dedicated chat files
and regular files that contain chat markers.

### Parser (nai/parser.lua)

The parser module is responsible for:
- Converting buffer content to structured messages for API requests
- Formatting responses for insertion into buffers
- Handling special blocks and their content
- Processing aliases and placeholders
- Generating YAML headers for new chats

It implements a marker-based parsing system that extracts user, assistant, and
system messages from the buffer content.

## User Interface Components

### Syntax Highlighting (nai/syntax.lua)

The syntax module provides:
- Custom highlight groups for different message types
- Real-time highlighting of chat markers and content
- Special highlighting for placeholders and verification signatures
- Buffer-specific highlighting that preserves existing syntax

This creates a visually distinct and readable chat interface within regular
text files.

### Folding (nai/folding.lua)

The folding system enables:
- Collapsible sections for user and assistant messages
- Nested folding for special blocks
- Markdown-style heading folding
- Preservation of original buffer folding settings

This helps manage longer conversations by allowing users to focus on specific
parts.

### Key Mappings (nai/mappings.lua)

The mappings module provides:
- Configurable key bindings for all plugin functions
- Buffer-local mappings that only apply to activated buffers
- Default mappings that follow intuitive patterns
- Ctrl+C interception for cancelling requests

Mappings are organized by category (chat, insert, settings, etc.) for easier
configuration.

### UI Indicators (nai/utils/indicators.lua)

This module creates visual feedback for asynchronous operations:
- Animated spinners for ongoing requests
- Progress information (elapsed time, tokens)
- Model information display
- Placeholder management for responses

These indicators provide essential feedback during potentially lengthy API
calls.

## Special Features

### Response Verification (nai/verification.lua)

The verification system provides cryptographic integrity checks:
- Generates hash signatures for AI responses
- Verifies responses haven't been tampered with
- Visually indicates verification status
- Detects and updates status when content changes

This feature is particularly useful for maintaining the integrity of
AI-generated content in shared or archived documents.

### Model Selection (nai/tools/picker.lua)

The picker module offers UI for:
- Selecting AI models across providers
- Browsing saved chat files
- Displaying model information
- Switching between providers

It supports multiple UI backends (Telescope, fzf-lua, Snacks) with graceful
fallbacks.

## Special Content Blocks

The plugin supports various special blocks that extend its functionality beyond
simple chat:

### Web Scraping (nai/fileutils/scrape.lua)

- Fetches content from web pages via the Dumpling API
- Formats content for readability
- Shows loading indicators during fetching
- Handles errors gracefully

Example usage:
```ignore
>>> scrape
https://example.com
```

### YouTube Transcripts (nai/fileutils/youtube.lua)

- Extracts transcripts from YouTube videos
- Supports timestamp inclusion/formatting
- Offers language selection
- Provides async loading with visual feedback

Example usage:
```ignore
>>> youtube
https://www.youtube.com/watch?v=example
```

### File References (nai/fileutils/reference.lua)

- Includes file contents in conversations
- Supports glob patterns and recursive searching
- Handles various file types with appropriate formatting
- Enforces safety limits for large files

Example usage:
```ignore
>>> reference
/path/to/file.lua
/another/path/*.md
```

### Directory Trees (nai/fileutils/tree.lua)

- Generates visual directory structure representations
- Supports customization via tree command options
- Shows async loading indicators
- Formats output for readability

Example usage:
```ignore
>>> tree
/path/to/directory
```

### Website Crawling (nai/fileutils/crawl.lua)

- Recursively crawls websites to a specified depth
- Extracts and formats content from multiple pages
- Controls crawl breadth and depth
- Provides progress indicators

Example usage:
```ignore
>>> crawl
https://example.com
-- depth: 2
-- limit: 5
```

### File Snapshots (nai/fileutils/snapshot.lua)

- Creates point-in-time snapshots of multiple files
- Supports glob patterns for file selection
- Formats content with syntax highlighting
- Timestamps snapshots for reference

Example usage:
```ignore
>>> snapshot
/path/to/project/*.js
```

## Utility Modules

### Path Handling (nai/utils/path.lua)

Provides cross-platform path operations:
- Path normalization and joining
- Directory creation
- Path expansion
- Temporary file management
- Windows/Unix compatibility

### Error Handling (nai/utils/error.lua)

Centralizes error management:
- Structured error logging
- User-friendly notifications
- Context-aware error messages
- API error parsing and formatting
- Dependency checking

### Constants (nai/constants.lua)

Defines shared constants:
- Message markers (`>>> user`, `<<< assistant`, etc.)
- Auto-title instruction text
- Block markers for special content

### Events (nai/events.lua)

Implements a simple event system:
- Event registration and emission
- Error-protected callback execution
- Listener cleanup

## Configuration Options

The plugin offers extensive configuration options:

### Provider Configuration

```lua
providers = {
  openai = {
    name = "OpenAI",
    endpoint = "https://api.openai.com/v1/chat/completions",
    models = {"gpt-4", "gpt-4o", "o3"},
    temperature = 0.7,
    max_tokens = 10000
  },
  openrouter = {
    name = "OpenRouter",
    endpoint = "https://openrouter.ai/api/v1/chat/completions",
    models = {"anthropic/claude-3.7-sonnet", "google/gemini-2.0-flash-001", ...},
    temperature = 0.7,
    max_tokens = 10000
  },
  google = {
    name = "Google",
    endpoint = "https://generativelanguage.googleapis.com/v1beta/models/",
    models = {"gemini-2.5-flash-preview-04-17", "gemini-2.0-flash", ...},
    temperature = 0.7,
    max_tokens = 8000
  },
  ollama = {
    name = "Ollama",
    endpoint = "http://localhost:11434/api/chat",
    models = {"llama3.2:latest"},
    temperature = 0.7,
    max_tokens = 4000
  }
}
```

### File Management

```lua
chat_files = {
  directory = "~/nvim-ai-notes",
  format = "{id}.md",
  auto_save = false,
  id_length = 4,
  use_timestamp = false,
  auto_title = true,
  header = {
    enabled = true,
    template = "---\ntitle: {title}\ndate: {date}\ntags: [ai]\n---"
  }
}
```

### UI Customization

```lua
highlights = {
  user = { fg = "#88AAFF", bold = true },
  assistant = { fg = "#AAFFAA", bold = true },
  system = { fg = "#FFAA88", bold = true },
  special_block = { fg = "#AAAAFF", bold = true },
  error_block = { fg = "#FF8888", bold = true },
  content_start = { fg = "#AAAAAA", italic = true },
  placeholder = { fg = "#FFCC66", bold = true },
  signature = { fg = "#777777", italic = true }
}
```

### Key Mappings

```lua
mappings = {
  enabled = true,
  intercept_ctrl_c = true,
  chat = {
    continue = "<Leader>c",
    verified_chat = "<Leader>av",
    new = "<Leader>ai",
    cancel = "<Leader>ax"
  },
  insert = {
    user_message = "<Leader>anu",
    scrape = "<Leader>and",
    web = "<Leader>anw",
    youtube = "<Leader>any",
    reference = "<Leader>anr",
    snapshot = "<Leader>ans",
    tree = "<Leader>ant",
    crawl = "<Leader>anc"
  },
  settings = {
    select_model = "<Leader>am",
    toggle_provider = "<Leader>ap"
  },
  files = {
    browse = "<Leader>ao"
  }
}
```

### Tool Integration

```lua
tools = {
  dumpling = {
    base_endpoint = "https://app.dumplingai.com/api/v1/",
    format = "markdown",
    cleaned = true,
    render_js = true,
    max_content_length = 100000,
    include_timestamps = true
  }
}
```

### Aliases

```lua
aliases = {
  translate = {
    system = "You are an interpreter. Translate any text to Spanish.",
    user_prefix = "",
    config = {
      model = "openai/gpt-4o-mini",
      temperature = 0.1
    }
  },
  refactor = {
    system = "You are a coding expert. Refactor the provided code.",
    user_prefix = "Refactor the following code:"
  }
}
```

## Command Structure

The plugin provides several Neovim commands:

- **:NAIChat**: Continue the conversation in the current buffer
- **:NAISignedChat**: Continue with verification signature
- **:NAINew**: Create a new chat buffer
- **:NAICancel**: Cancel ongoing requests
- **:NAIExpand**: Expand all special blocks in buffer
- **:NAIVerify**: Verify the integrity of responses
- **:NAIProvider**: Select AI provider
- **:NAIModel**: Select AI model
- **:NAIBrowse**: Browse saved chat files
- **:NAISetKey**: Set API key for a provider

Block insertion commands:
- **:NAIUser**: Insert a new user message
- **:NAIScrape**: Insert a web scraping block
- **:NAIWeb**: Insert a simple web content block
- **:NAIYoutube**: Insert a YouTube transcript block
- **:NAIReference**: Insert a file reference block
- **:NAISnapshot**: Insert a file snapshot block
- **:NAITree**: Insert a directory tree block
- **:NAICrawl**: Insert a website crawling block

## Workflow Integration

### Buffer Activation Logic

Buffers are activated for AI functionality based on:
1. File extension matching (.md, .markdown, .wiki)
2. Detection of chat markers in content
3. Manual activation via :NAIActivate

Activated buffers receive:
- Syntax highlighting for chat markers
- Folding capabilities
- Key mappings
- Special block expansion

### Chat Flow

A typical chat interaction follows this flow:
1. User writes a message after `>>> user` marker
2. User triggers :NAIChat (or mapped key)
3. Plugin parses buffer to extract conversation history
4. Request is sent to the selected AI provider
5. Loading indicator appears in buffer
6. Response is received and formatted in buffer
7. A new user message marker is added for continuation
8. (Optional) Verification signature is added

### Special Block Expansion

Special blocks are expanded when:
1. User adds a special block marker (e.g., `>>> scrape`)
2. User triggers :NAIExpand (or mapped key)
3. Plugin processes each unexpanded block
4. Visual indicators show progress
5. Expanded content replaces the original markers

## Testing and Development

The plugin includes a testing framework:
- Unit tests for core functionality
- Integration tests for end-to-end flows
- Mock API for testing without real providers
- Test runner with visual results display

Development helpers:
- Module reloading for quick iteration
- Debug logging system
- Configuration validation

## Security Considerations

The plugin implements several security measures:
- API keys stored in separate credentials file with restricted permissions
- Path expansion safety limits to prevent accidental resource exhaustion
- Content size limits for web scraping and file operations
- Verification system to detect tampering with AI responses
- Cross-platform path handling to avoid security issues

## Performance Optimizations

- Debounced syntax highlighting to prevent UI lag
- Efficient buffer parsing
- Asynchronous API requests
- Platform-specific optimizations for Windows
- Temporary file approach for large payloads

## Integration with External Tools

The plugin leverages several external tools:
- curl for API requests
- html2text/lynx for web content formatting
- tree command for directory visualization
- sha256sum for verification signatures
- Dumpling API for advanced web processing

UI integrations:
- Telescope for picker interfaces
- fzf-lua for alternative selection UI
- Snacks for modern UI components
- Graceful fallbacks to vim.ui.select

## Event System

The event system allows for plugin extensibility:
- `request:start`: When an API request begins
- `request:complete`: When a response is received
- `request:error`: When an API error occurs
- `request:cancel`: When a request is cancelled
- `buffer:activate`: When a buffer is activated for AI
- `buffer:deactivate`: When a buffer is deactivated
- `model:change`: When the active model changes

## Conclusion

nvim-ai provides a powerful, flexible system for AI interactions within Neovim.
Its modular design, extensive configuration options, and special block
functionality make it adaptable to a wide range of use cases, from simple chat
assistance to complex content generation and information retrieval workflows.

The plugin's document-based approach integrates naturally with Neovim's editing
model, allowing users to maintain a record of their AI interactions in standard
markdown files while leveraging the full power of modern AI models.
