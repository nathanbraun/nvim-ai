# SUMMARY-PARSER.md

## Module: Parser & File Utilities Module

### Purpose and Scope
The Parser & File Utilities module handles the transformation between buffer content and API messages, including:
- Parsing chat buffer content into API message format using a registry-based processor system
- Formatting API responses for buffer display
- Managing YAML frontmatter headers
- Replacing placeholders with dynamic content
- Processing special blocks (scrape, youtube, snapshot, tree, crawl, reference, alias)
- Expanding file patterns and reading file contents
- Generating chat filenames and managing file operations

### Architecture Overview

**Registry-Based Design** (as of 2025-12-03):
The parser uses a centralized registry system where each message/block type has its own processor module. This eliminates code duplication and makes adding new block types trivial.

```
parser.lua (main orchestrator)
    ↓
registry.lua (processor registry)
    ↓
processors/
    ├── user.lua
    ├── assistant.lua
    ├── system.lua
    ├── tree.lua
    ├── alias.lua
    ├── reference.lua (calls fileutils.reference)
    ├── snapshot.lua (calls fileutils.snapshot)
    ├── web.lua (calls fileutils.web)
    ├── youtube.lua (calls fileutils.youtube)
    ├── crawl.lua (calls fileutils.crawl)
    └── scrape.lua (calls fileutils.scrape)
```

### Key Components and Files

#### 1. `lua/nai/parser/registry.lua` - Processor Registry
**Primary Responsibilities:**
- Centralized registration of message/block processors
- Matching incoming lines against registered processors
- Providing processor lookup by name

**Processor Interface:**
```lua
{
  marker = ">>> user",           -- string or function(line) -> boolean
  role = "user",                 -- API role (user/assistant/system)
  process_content = nil,         -- optional: function(text_buffer) -> string
  format = function(content)     -- required: how to format for buffer
    return ">>> user\n\n" .. content
  end,
  parse_line = nil              -- optional: function(line) -> table (extra data)
}
```

**Key Functions:**
```lua
registry.register(name, processor)
-- Registers a new processor with validation

registry.get(name)
-- Returns processor by name

registry.match_line(line)
-- Returns: processor_name, processor or nil, nil
-- Checks if line matches any registered processor
```

#### 2. `lua/nai/parser/processors/*.lua` - Individual Processors
**Primary Responsibilities:**
- Define marker patterns for each block type
- Specify API role for message creation
- Provide formatting logic
- Delegate to fileutils for complex processing

**Simple Processors** (user, assistant, system, tree):
```lua
-- Example: processors/user.lua
return {
  marker = MARKERS.USER,
  role = "user",
  format = function(content)
    return ">>> user\n\n" .. content
  end
}
```

**Complex Processors** (reference, snapshot, web, youtube, crawl, scrape):
```lua
-- Example: processors/reference.lua
return {
  marker = MARKERS.REFERENCE,
  role = "user",
  process_content = function(text_buffer)
    local reference_fileutils = require('nai.fileutils.reference')
    return reference_fileutils.process_reference_block(text_buffer)
  end,
  format = function(content)
    return "\n >>> reference \n\n" .. content
  end
}
```

**Special Processors** (alias):
```lua
-- processors/alias.lua
return {
  marker = function(line)
    return line:match("^" .. vim.pesc(MARKERS.ALIAS)) ~= nil
  end,
  role = "user",
  parse_line = function(line)
    local alias_name = line:match("^" .. vim.pesc(MARKERS.ALIAS) .. "%s*(.+)$")
    return { _alias = alias_name }
  end,
  format = function(content, alias_name)
    if alias_name then
      return "\n>>> alias: " .. alias_name .. "\n\n" .. content
    else
      return "\n>>> alias:\n\n" .. content
    end
  end
}
```

#### 3. `lua/nai/parser.lua` - Core Parsing & Formatting
**Primary Responsibilities:**
- Orchestrates buffer parsing using registry
- Handles special cases (config, YAML headers, ignore blocks)
- Manages message assembly and default system prompts
- Provides public formatting API
- Processes aliases and chat configuration

**Key Functions:**

**Buffer Parsing:**
```lua
M.parse_chat_buffer(content, buffer_id)
-- Returns: messages[], chat_config{}

-- Process:
-- 1. Split content into lines
-- 2. Skip YAML header (between --- markers)
-- 3. Handle ignore blocks (>>> ignore / <<< ignore)
-- 4. Parse config blocks (>>> config) - special case
-- 5. Use registry to match and process message markers
-- 6. Handle special parsing (e.g., alias name extraction)
-- 7. Process content (use processor.process_content if available)
-- 8. Add default system message if none provided
-- 9. Process aliases (expand to system + user messages)
-- 10. Return messages + chat_config
```

**Registry Integration:**
```lua
-- Main parsing loop uses registry:
local processor_name, processor = registry.match_line(line)
if processor_name then
  -- Finish previous message
  if current_message then
    current_message.content = table.concat(text_buffer, "\n")
    table.insert(messages, current_message)
    text_buffer = {}
  end
  
  -- Create new message with processor's role
  current_message = { role = processor.role }
  
  -- Handle special parsing (e.g., alias name extraction)
  if processor.parse_line then
    local extra_data = processor.parse_line(line)
    for k, v in pairs(extra_data) do
      current_message[k] = v
    end
  end
  
  current_type = processor_name
end

-- Content processing at end uses registry:
if current_message then
  local processor = registry.get(current_type)
  if processor and processor.process_content then
    current_message.content = processor.process_content(text_buffer)
  else
    current_message.content = table.concat(text_buffer, "\n"):gsub("^%s*(.-)%s*$", "%1")
  end
  table.insert(messages, current_message)
end
```

**Message Structure:**
```lua
{
  role = "user"|"assistant"|"system",
  content = "message text",
  _alias = "alias_name"  -- Optional, for alias processing
}
```

**Chat Config Extraction:**
```lua
-- From >>> config block (special case, not in registry):
model: anthropic/claude-sonnet-4.5
temperature: 0.7
max_tokens: 2000
provider: openrouter
expand_placeholders: true

-- Parsed to:
{
  model = "anthropic/claude-sonnet-4.5",
  temperature = 0.7,
  max_tokens = 2000,
  provider = "openrouter",
  expand_placeholders = true
}
```

**Message Formatting (Public API):**
```lua
-- All formatting functions delegate to processors via helper:
local function format_via_processor(processor_name, content)
  local processor = registry.get(processor_name)
  if processor then
    return processor.format(content)
  else
    error("Unknown processor: " .. processor_name)
  end
end

M.format_assistant_message(content)
M.format_user_message(content)
M.format_system_message(content)
M.format_tree_block(content)
M.format_reference_block(content)
M.format_scrape_block(content)
M.format_youtube_block(url)
M.format_crawl_block(url)
M.format_snapshot(timestamp)
M.format_web_block(content)
```

**YAML Header Generation:**
```lua
M.generate_header(title)
-- Uses config.options.chat_files.header
-- Default template:
---
title: {title}
date: {date}
tags: [ai]
---

-- Can be disabled: header.enabled = false
-- Custom template: header.template = "..."
```

**System Prompt with Auto-Title:**
```lua
M.get_system_prompt_with_title_request(is_untitled)
-- If auto_title enabled and is_untitled:
--   Returns: base_prompt + AUTO_TITLE_INSTRUCTION
-- Else:
--   Returns: base_prompt

-- AUTO_TITLE_INSTRUCTION:
-- "For your first response, please begin with 'Proposed Title: '
--  followed by a concise 3-7 word title..."
```

**Placeholder Replacement:**
```lua
M.replace_placeholders(content, buffer_id)
-- Supported placeholders:
-- - %%FILE_CONTENTS%%
-- - ${FILE_CONTENTS}
-- - $FILE_CONTENTS

-- Process:
-- 1. Get buffer lines up to first chat marker
-- 2. Join lines
-- 3. Replace all placeholder occurrences with file content
```

**Alias Processing:**
```lua
M.process_alias_messages(messages)
-- Returns: processed_messages[], alias_chat_config{}

-- For each message with _alias:
-- 1. Look up alias in config.options.aliases
-- 2. Insert system message from alias.system
-- 3. Prefix user content with alias.user_prefix
-- 4. Merge alias.config into chat_config
-- 5. Remove _alias marker

-- Example alias:
aliases = {
  translate = {
    system = "You are an interpreter...",
    user_prefix = "Translate to Spanish:",
    config = {
      model = "openai/gpt-4o-mini",
      temperature = 0.1
    }
  }
}
```

#### 4. `lua/nai/fileutils/init.lua` - File Naming & Management
**Primary Responsibilities:**
- Generate unique chat filenames
- Create chat directory structure
- Handle cross-platform path operations

**Key Functions:**

**ID Generation:**
```lua
M.generate_id(length)
-- Returns: random alphanumeric string
-- Chars: "abcdefghijklmnopqrstuvwxyz0123456789"

M.generate_timestamp()
-- Returns: "YYYYMMDDHHMMSS"
```

**Filename Generation:**
```lua
M.generate_filename(title)
-- Process:
-- 1. Ensure directory exists
-- 2. Generate ID or timestamp
-- 3. Clean title for filename:
--    - Remove special chars
--    - Replace spaces with hyphens
--    - Lowercase
--    - Truncate to 40 chars
-- 4. Apply format template
-- 5. Replace .naichat with .md
-- 6. Join directory + filename

-- Format template (from config):
-- "{date}-{id}-{title}.md"
-- Example: "20240115-a3f2-my-chat-title.md"
```

**Path Handling:**
- Uses `path.separator` for cross-platform compatibility
- Expands `~` and environment variables
- Creates directory if doesn't exist
- Windows-specific filename restrictions

#### 5. `lua/nai/fileutils/reference.lua` - File Reference & Reading
**Primary Responsibilities:**
- Expand file patterns (wildcards, globs)
- Read file contents with safety checks
- Format file contents with headers
- Handle multiple file references

**Key Functions:**

**Path Expansion:**
```lua
M.expand_paths(path_pattern)
-- Returns: array of file paths

-- Supports:
-- - Simple paths: "file.txt"
-- - Wildcards: "*.lua", "test?.txt"
-- - Recursive: "**/*.lua"
-- - Character classes: "[abc].txt" (with smart detection)

-- Safety features:
-- - MAX_FILES limit (100 default)
-- - Prevents root/broad directory searches
-- - Platform-specific commands (find/PowerShell)
-- - Warns on excessive matches
```

**Character Class Detection:**
```lua
-- Distinguishes between:
-- [abc] - character class (wildcard)
-- [id] - directory name (literal)

-- Heuristics:
-- - Ranges (a-z, 0-9) → character class
-- - Negation (^, !) → character class
-- - Short patterns (2-4 chars) → character class
-- - Common dir names (id, slug, key) → literal
-- - Long patterns (5+ chars) → literal
```

**File Reading:**
```lua
M.read_file_with_header(filepath)
-- Returns: "==> filepath <==\nfile contents"

-- Safety checks:
-- - File exists and readable
-- - Size limit (500KB)
-- - Binary file detection
-- - Empty file handling

M.read_file(filepath)
-- Same as above but without header
```

**Reference Block Processing:**
```lua
M.process_reference_block(lines)
-- Input format:
-- path/to/file1.txt
-- path/to/file2.txt
--
-- Additional context text here

-- Process:
-- 1. Parse file paths (until empty line)
-- 2. Expand each path pattern
-- 3. Read each file with header
-- 4. Append additional text
-- 5. Join with double newlines
```

#### 6. `lua/nai/fileutils/scrape.lua` - Web Scraping
**Primary Responsibilities:**
- Fetch web content via Dumpling API
- Display loading indicators
- Format scraped content
- Handle async scraping operations

**Key Functions:**

**API Integration:**
```lua
M.fetch_url(url, callback, on_error)
-- Uses Dumpling API endpoint: /scrape
-- POST request with:
{
  url = "https://example.com",
  format = "markdown",
  cleaned = true,
  renderJs = true
}

-- Response:
{
  title = "Page Title",
  content = "Markdown content..."
}
```

**Buffer Expansion:**
```lua
M.expand_scrape_block(buffer_id, start_line, end_line)
-- Process:
-- 1. Parse URL from block
-- 2. Change marker to ">>> scraping"
-- 3. Insert spinner animation
-- 4. Start async fetch
-- 5. On success:
--    - Stop spinner
--    - Replace with ">>> scraped [timestamp]"
--    - Add title and content
-- 6. On error:
--    - Stop spinner
--    - Replace with ">>> scrape-error"
--    - Show error message

-- Spinner animation:
-- Frames: { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
-- Update: 120ms interval
-- Text: "⠋ Fetching content from https://..."
```

**Active Request Tracking:**
```lua
M.active_requests = {
  {
    buffer_id = 123,
    indicator = { ... },
    start_line = 10,
    end_line = 15,
    url = "https://example.com"
  }
}

M.has_active_requests()  -- Check if any scrapes in progress
```

#### 7. `lua/nai/fileutils/youtube.lua` - YouTube Transcripts
**Primary Responsibilities:**
- Fetch YouTube transcripts via Dumpling API
- Handle transcript options (timestamps, language)
- Display loading indicators
- Format transcript content

**Key Functions:**

**Transcript Fetching:**
```lua
M.fetch_transcript(video_url, options, callback, on_error)
-- Uses Dumpling API endpoint: /get-youtube-transcript
-- POST request with:
{
  videoUrl = "https://youtube.com/watch?v=...",
  includeTimestamps = true,
  timestampsToCombine = 5,
  preferredLanguage = "en"
}

-- Response:
{
  transcript = "Transcript text...",
  language = "en"
}
```

**Buffer Expansion:**
```lua
M.expand_youtube_block(buffer_id, start_line, end_line)
-- Input format:
-- >>> youtube
-- https://youtube.com/watch?v=...
-- -- timestamps: false
-- -- combine: 3
-- -- language: es

-- Process:
-- 1. Parse URL and options
-- 2. Change marker to ">>> transcribing"
-- 3. Insert spinner
-- 4. Fetch async
-- 5. Replace with ">>> transcript [timestamp]"
-- 6. Add formatted transcript
```

**Options Parsing:**
```lua
-- Default options:
{
  include_timestamps = true,
  timestamps_to_combine = 5,
  preferred_language = "en"
}

-- Parsed from comment lines:
-- -- timestamps: false
-- -- combine: 10
-- -- language: es
```

#### 8. `lua/nai/fileutils/snapshot.lua` - File Snapshots
**Primary Responsibilities:**
- Create timestamped file snapshots
- Expand file patterns
- Format with syntax highlighting
- Preserve file structure

**Key Functions:**

**Snapshot Expansion:**
```lua
M.expand_snapshot_in_buffer(buffer_id, start_line, end_line)
-- Input format:
-- >>> snapshot
-- path/to/file1.lua
-- path/to/file2.py
--
-- Additional context

-- Output format:
-- >>> snapshotted [2024-01-15 10:30:00]
-- path/to/file1.lua
-- path/to/file2.py
--
-- ==> path/to/file1.lua <==
-- ```lua
-- file contents
-- ```
--
-- ==> path/to/file2.py <==
-- ```python
-- file contents
-- ```
--
-- Additional context
```

**Syntax Detection:**
```lua
-- Maps file extensions to syntax types:
.lua → lua
.py → python
.js → javascript
.ts → typescript
.html → html
.css → css
.json → json
.md → markdown (no code blocks)
.rb → ruby
.go → go
.rs → rust
.c, .h → c
.cpp, .hpp → cpp
.sh → bash
```

**Markdown Handling:**
- Markdown files NOT wrapped in code blocks
- Preserves markdown formatting
- Other files wrapped in ```syntax blocks

#### 9. `lua/nai/fileutils/tree.lua` - Directory Trees
**Primary Responsibilities:**
- Generate directory tree visualizations
- Execute `tree` command
- Handle multiple directories
- Parse tree options

**Key Functions:**

**Tree Generation:**
```lua
M.expand_tree_in_buffer(buffer_id, start_line, end_line)
-- Input format:
-- >>> tree
-- ~/projects/myapp
-- ~/projects/lib
-- -- -L 2 -I node_modules

-- Process:
-- 1. Parse directory paths and options
-- 2. Check tree command availability
-- 3. Change marker to ">>> generating-tree"
-- 4. Execute tree command synchronously
-- 5. Replace with ">>> tree [timestamp]"
-- 6. Add tree output for each directory

-- Options passed directly to tree command:
-- -L 2 → max depth 2
-- -I node_modules → ignore node_modules
-- -a → show hidden files
-- etc.
```

**Command Execution:**
```lua
-- Command format:
tree "/expanded/path" -L 2 -I node_modules

-- Output format:
==> /expanded/path <==
.
├── src/
│   ├── main.lua
│   └── utils.lua
└── README.md
```

#### 10. `lua/nai/fileutils/crawl.lua` - Website Crawling
**Primary Responsibilities:**
- Crawl multiple pages from a website
- Use Dumpling API for crawling
- Display progress indicators
- Format multi-page results

**Key Functions:**

**Website Crawling:**
```lua
M.crawl_website(url, options, callback, on_error)
-- Uses Dumpling API endpoint: /crawl
-- POST request with:
{
  url = "https://example.com",
  limit = 5,
  depth = 2,
  format = "markdown"
}

-- Response:
{
  pages = 5,
  results = [
    { url = "https://example.com", content = "..." },
    { url = "https://example.com/page1", content = "..." },
    ...
  ]
}
```

**Buffer Expansion:**
```lua
M.expand_crawl_block(buffer_id, start_line, end_line)
-- Input format:
-- >>> crawl
-- https://example.com
-- -- limit: 10
-- -- depth: 3
-- -- format: markdown

-- Output format:
-- >>> crawled [timestamp]
-- https://example.com
-- -- limit: 10
-- -- depth: 3
-- -- format: markdown
--
-- ## Crawled 10 pages from https://example.com
--
-- ### Page 1: https://example.com
-- content...
-- ---
--
-- ### Page 2: https://example.com/page1
-- content...
-- ---
```

**Options:**
```lua
-- Default options:
{
  limit = 5,      -- Max pages to crawl
  depth = 2,      -- Max depth from starting URL
  format = "markdown"
}
```

#### 11. `lua/nai/fileutils/web.lua` - Simple Web Fetching
**Primary Responsibilities:**
- Fetch web pages without API
- Convert HTML to markdown
- Use curl + html2text/lynx
- Fallback for simple scraping

**Key Functions:**

**URL Fetching:**
```lua
M.fetch_url(url)
-- Process:
-- 1. Check for html2text or lynx
-- 2. Fetch with curl (10s timeout, 1MB limit)
-- 3. Convert HTML to markdown
-- 4. Truncate if too large (100KB)
-- Returns: "==> Web (Simple): url <==\n\nmarkdown content"

-- Tools used:
-- - curl: fetch HTML
-- - html2text: convert to markdown (preferred)
-- - lynx: fallback converter
```

**Block Processing:**
```lua
M.process_web_block(lines)
-- Input format:
-- url1
-- url2
--
-- Additional context

-- Process:
-- 1. Parse URLs (until empty line)
-- 2. Fetch each URL synchronously
-- 3. Add additional text
-- 4. Join with double newlines
```

### Important Patterns/Conventions

#### 1. Registry-Based Extension Pattern
```lua
-- Adding a new block type:

-- 1. Create processor file:
-- lua/nai/parser/processors/myblock.lua
return {
  marker = MARKERS.MYBLOCK,
  role = "user",
  process_content = function(text_buffer)
    -- Optional: special processing
    return processed_content
  end,
  format = function(content)
    return "\n>>> myblock\n\n" .. content
  end
}

-- 2. Register in parser.lua:
registry.register('myblock', require('nai.parser.processors.myblock'))

-- That's it! The parser will automatically:
-- - Match the marker during parsing
-- - Create messages with the specified role
-- - Call process_content if provided
-- - Use the format function for buffer output
```

#### 2. Block Marker Pattern
```
>>> type         -- Start marker (user input)
content here
<<< type         -- End marker (system output)

>>> type [timestamp]  -- Expanded/processed marker
expanded content
```

#### 3. Special Block Lifecycle
```
1. Unexpanded: >>> scrape
2. Processing: >>> scraping (with spinner)
3. Complete:   >>> scraped [timestamp]
4. Error:      >>> scrape-error
```

#### 4. Async Expansion Pattern
```lua
-- 1. Detect unexpanded block
if has_unexpanded_blocks() then
  -- 2. Change marker to "processing"
  -- 3. Insert spinner indicator
  -- 4. Start timer for animation
  -- 5. Make async request
  -- 6. On completion:
  --    - Stop timer
  --    - Replace block with results
  -- 7. On error:
  --    - Stop timer
  --    - Replace with error message
end
```

#### 5. Content Formatting Pattern
```lua
-- Header format:
==> filepath/url <==
content

-- Multiple items:
==> item1 <==
content1

==> item2 <==
content2
```

#### 6. Options Parsing Pattern
```lua
-- Comment-style options:
-- option_name: value
-- another_option: value

-- Parsed with:
local key, value = line:match("^%s*--%s*([%w_]+)%s*:%s*(.+)$")
```

### Dependencies on Other Modules

**Required by Parser Module:**
- `nai.config` - Default prompts, aliases, file settings, tool configs
- `nai.constants` - Marker definitions
- `nai.fileutils.*` - Special block processors (called by processor modules)
- `nai.utils.path` - Path operations

**Used by:**
- `nai.init` - Parses buffer content for API requests
- `nai.api` - Receives formatted messages
- `nai.buffer` - Uses markers for syntax highlighting
- `nai.blocks.expander` - Uses similar registry pattern for block expansion

### Entry Points and Main Interfaces

#### Parser API
```lua
-- Parsing
local messages, chat_config = parser.parse_chat_buffer(content, buffer_id)

-- Formatting (delegates to processors)
local text = parser.format_assistant_message(content)
local text = parser.format_user_message(content)
local text = parser.format_system_message(content)
local text = parser.format_config_block(config_options)
local text = parser.format_tree_block(content)
local text = parser.format_reference_block(content)
local text = parser.format_scrape_block(content)
local text = parser.format_youtube_block(url)
local text = parser.format_crawl_block(url)
local text = parser.format_snapshot(timestamp)
local text = parser.format_web_block(content)

-- Headers
local header = parser.generate_header(title)
local prompt = parser.get_system_prompt_with_title_request(is_untitled)

-- Placeholders
local content = parser.replace_placeholders(content, buffer_id)

-- Aliases
local messages, config = parser.process_alias_messages(messages)
```

#### Registry API
```lua
-- Registration (done at parser.lua startup)
registry.register(name, processor)

-- Lookup
local processor = registry.get(name)

-- Matching
local processor_name, processor = registry.match_line(line)
```

#### File Utilities API
```lua
-- File naming
local filename = fileutils.generate_filename(title)
local id = fileutils.generate_id(4)
local timestamp = fileutils.generate_timestamp()

-- File operations
local paths = reference.expand_paths("**/*.lua")
local content = reference.read_file(filepath)
local content = reference.read_file_with_header(filepath)
local content = reference.process_reference_block(lines)

-- Web/API operations
scrape.fetch_url(url, callback, on_error)
youtube.fetch_transcript(url, options, callback, on_error)
crawl.crawl_website(url, options, callback, on_error)
web.fetch_url(url)  -- Synchronous, simple

-- Buffer expansion
scrape.expand_scrape_block(buffer_id, start_line, end_line)
youtube.expand_youtube_block(buffer_id, start_line, end_line)
snapshot.expand_snapshot_in_buffer(buffer_id, start_line, end_line)
tree.expand_tree_in_buffer(buffer_id, start_line, end_line)
crawl.expand_crawl_block(buffer_id, start_line, end_line)

-- Detection
scrape.has_unexpanded_scrape_blocks(buffer_id)
youtube.has_unexpanded_youtube_blocks(buffer_id)
snapshot.has_unexpanded_snapshot_blocks(buffer_id)
tree.has_unexpanded_tree_blocks(buffer_id)
crawl.has_unexpanded_crawl_blocks(buffer_id)

-- Active request tracking
scrape.has_active_requests()
crawl.has_active_requests()
```

### Configuration Examples

#### Chat File Settings
```lua
chat_files = {
  directory = "~/nvim-ai-notes",
  format = "{date}-{id}-{title}.md",
  auto_save = true,
  id_length = 4,
  use_timestamp = false,
  auto_title = true,
  header = {
    enabled = true,
    template = [[---
title: {title}
date: {date}
tags: [ai, chat]
---]]
  }
}
```

#### Dumpling Tool Configuration
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

#### Alias Configuration
```lua
aliases = {
  translate = {
    system = "You are an interpreter. Translate to Spanish.",
    user_prefix = "",
    config = {
      model = "openai/gpt-4o-mini",
      temperature = 0.1
    }
  },
  refactor = {
    system = "You are a coding expert. Refactor code.",
    user_prefix = "Refactor the following code:",
  },
  ["check-todo"] = {
    system = "Evaluate a todo list...",
    config = {
      expand_placeholders = true
    },
    user_prefix = "The todo is here:\n$FILE_CONTENTS"
  }
}
```

### Parsing Flow Example

>>> ignore
```
Buffer Content:
---
title: My Chat
date: 2024-01-15
---

>>> config
model: gpt-4
temperature: 0.5

>>> user
What is 2+2?

<<< assistant
4

>>> user
Thanks!

↓ parse_chat_buffer() ↓

1. Skip YAML header (--- to ---)
2. Parse config block (special case)
3. Match ">>> user" → registry returns user processor
4. Create message: { role = "user" }
5. Collect content until next marker
6. Match "<<< assistant" → registry returns assistant processor
7. Create message: { role = "assistant" }
8. Match ">>> user" → registry returns user processor
9. Add default system message (none found)

Messages:
[
  { role = "system", content = "You are a general assistant." },
  { role = "user", content = "What is 2+2?" },
  { role = "assistant", content = "4" },
  { role = "user", content = "Thanks!" }
]

Chat Config:
{
  model = "gpt-4",
  temperature = 0.5
}
```
<<< ignore

### Design Benefits

**Achieved through Registry Refactoring:**
1. **60-70% code reduction** in parser.lua (~470 → ~360 lines)
2. **Eliminated duplication** - 11 identical marker handling blocks → 1 registry lookup
3. **Easy extensibility** - new block types require only a processor file + registration
4. **Better organization** - each block type's logic in one place
5. **Consistent interface** - all processors follow same pattern
6. **Maintainability** - changes to one block type don't affect others
7. **Testability** - processors can be tested independently
