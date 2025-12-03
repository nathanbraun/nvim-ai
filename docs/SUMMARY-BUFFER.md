# SUMMARY-BUFFER.md

## Module: Buffer Management Module

### Purpose and Scope
The Buffer Management module handles the interactive chat experience within Neovim buffers by:
- Detecting and activating buffers containing chat content
- Applying custom syntax highlighting overlays
- Managing chat block folding
- Providing visual indicators for async operations
- Maintaining buffer-specific state and settings
- Preserving underlying file type functionality (markdown, vimwiki, etc.)

### Key Components and Files

#### 1. `lua/nai/buffer.lua` - Buffer Lifecycle Manager
**Primary Responsibilities:**
- Detects chat markers in buffers
- Activates/deactivates buffers for nvim-ai functionality
- Applies syntax highlighting and folding
- Sets up buffer-local autocmds and commands
- Manages buffer state transitions

**Key Functions:**

**Detection:**
```lua
M.detect_chat_markers(bufnr)
-- Returns true if buffer contains >>> user, <<< assistant, etc.
-- Scans all lines for MARKERS from constants module

M.should_activate_by_pattern(bufnr)
-- Checks filename against config.options.active_filetypes.patterns
-- Patterns: { "*.md", "*.markdown", "*.wiki" }

M.should_activate(bufnr)
-- Combined check: pattern match OR (autodetect AND has markers)
```

**Activation:**
```lua
M.activate_buffer(bufnr)
-- 1. Validates buffer
-- 2. Marks in state.activate_buffer()
-- 3. Emits 'buffer:activate' event
-- 4. Applies buffer-local mappings (if enabled)
-- 5. Applies syntax overlay (if enable_overlay = true)
-- 6. Applies folding (if enable_folding ≠ false)
-- 7. Sets up BufUnload cleanup autocmd
-- 8. Schedules deferred syntax/fold refresh (100ms)
```

**Deactivation:**
```lua
M.deactivate_buffer(bufnr)
-- 1. Removes from state
-- 2. Emits 'buffer:deactivate' event
-- 3. Clears syntax highlights
-- 4. Restores original folding
-- 5. Restores original mappings
```

**Syntax Application:**
```lua
M.apply_syntax_overlay(bufnr)
-- 1. Clears existing overlay namespace
-- 2. Calls syntax.apply_to_buffer()
-- 3. Stores namespace ID for future reference
```

**Autocmd Setup:**
```lua
M.setup_autocmds()
-- Creates global autocmds:
-- - BufReadPost, BufNewFile: Check if should activate
-- - FileType (markdown, text, wiki): Check if should activate
```

**Manual Activation:**
```lua
M.create_activation_command()
-- Creates :NAIActivate command
-- Forces activation regardless of pattern/marker checks
-- Sets up buffer-local :NAIChat command
```

**Activation Flow:**
```
File opened → BufReadPost event
    ↓
should_activate() check
    ↓
activate_buffer()
    ↓
├─ state.activate_buffer()
├─ mappings.apply_to_buffer()
├─ syntax.apply_to_buffer()
├─ folding.apply_to_buffer()
└─ Setup BufUnload cleanup
```

#### 2. `lua/nai/syntax.lua` - Syntax Highlighting Overlay
**Primary Responsibilities:**
- Defines custom highlight groups from config
- Applies syntax highlighting using extmarks/namespaces
- Preserves underlying filetype syntax (markdown, etc.)
- Updates highlights on text changes (debounced)
- Highlights chat markers, special blocks, and placeholders

**Highlight Groups:**
```lua
naichatUser           -- >>> user (blue, bold)
naichatAssistant      -- <<< assistant (green, bold)
naichatSystem         -- >>> system (orange, bold)
naichatSpecialBlock   -- >>> scrape, >>> youtube, etc. (purple, bold)
naichatErrorBlock     -- Error blocks (red, bold)
naichatContentStart   -- <<< content (gray, italic)
naichatSignature      -- <<< signature (gray, italic)
naichatPlaceholder    -- $FILE_CONTENTS, etc. (golden, bold)
```

**Key Functions:**

**Highlight Definition:**
```lua
M.define_highlight_groups()
-- Creates highlight commands from config.options.highlights
-- Uses default keyword to not override existing definitions
-- Supports: fg, bg, bold, italic, underline
-- Includes both GUI (guifg, gui) and terminal (ctermfg, cterm) colors
```

**Buffer Application:**
```lua
M.apply_to_buffer(bufnr)
-- 1. Creates unique namespace 'nai_syntax_overlay'
-- 2. Scans all buffer lines
-- 3. Applies highlights via vim.api.nvim_buf_add_highlight()
-- 4. Sets up debounced TextChanged/TextChangedI autocmds
-- Returns: namespace ID
```

**Line Highlighting Logic:**
```lua
-- Exact marker matching (must be entire line)
if line == ">>> user" then
  highlight as naichatUser
elseif line == "<<< assistant" then
  highlight as naichatAssistant
  
-- Pattern matching
elseif line:match("^>>> [a-z%-]+") then
  if line:match("error") then
    highlight as naichatErrorBlock
  else
    highlight as naichatSpecialBlock
    
-- Placeholder highlighting (within line)
for pattern in {"%%FILE_CONTENTS%%", "${FILE_CONTENTS}", "$FILE_CONTENTS"} do
  if line contains pattern then
    highlight matched portion as naichatPlaceholder
```

**Debouncing:**
- 100ms delay after text changes
- Prevents excessive re-highlighting during typing
- Clears and reapplies all highlights on trigger

**Overlay Strategy:**
- Uses separate namespace from base filetype syntax
- Highlights applied via `nvim_buf_add_highlight()` (extmarks)
- Doesn't interfere with markdown/vimwiki syntax
- Higher priority than base syntax

#### 3. `lua/nai/folding.lua` - Chat Block Folding
**Primary Responsibilities:**
- Provides expression-based folding for chat blocks
- Folds user/assistant/system messages
- Supports nested folding for special blocks
- Preserves original folding settings per-window
- Integrates with markdown/vimwiki heading folds

**Fold Levels:**
```lua
">1"  -- Start level 1 fold (user, assistant, system, YAML header, # heading)
">2"  -- Start level 2 fold (special blocks, ## heading, nested content)
">3"  -- Level 3 (### heading)
"<1"  -- End level 1 fold (closing YAML ---)
"="   -- Keep current level (default)
```

**Key Functions:**

**Fold Calculation:**
```lua
M.get_fold_level(lnum)
-- Called by Neovim's foldexpr evaluation
-- Returns fold level string (">1", "=", etc.)

-- Chat markers (exact match)
if line == ">>> user" then return ">1"
if line == "<<< assistant" then return ">1"
if line == ">>> system" then return ">1"

-- Special blocks (nested)
if line:match("^>>> %w+") then return ">2"

-- YAML header
if lnum == 1 and line == "---" then return ">1"
if line == "---" and prev_line ~= "" then return "<1"

-- Markdown headings
if line:match("^#%s") then return ">1"
if line:match("^##%s") then return ">2"
-- ... up to ######

-- VimWiki headings
if line:match("^=%s") then return ">1"
if line:match("^==%s") then return ">2"
-- ... up to ======
```

**Buffer Application:**
```lua
M.apply_to_buffer(bufnr)
-- 1. Creates buffer-specific augroup
-- 2. Sets up BufWinEnter autocmd:
--    - Stores original foldmethod/foldexpr per window
--    - Sets foldmethod = "expr"
--    - Sets foldexpr = "v:lua.require('nai.folding').get_fold_level(v:lnum)"
--    - Sets foldlevel = 99 (all folds open by default)
-- 3. Sets up BufWinLeave autocmd:
--    - Restores original settings
--    - Cleans up stored settings
-- 4. Applies settings immediately if buffer is in window
```

**Settings Storage:**
```lua
M.original_settings = {
  ["win_1001"] = {
    foldmethod = "manual",
    foldexpr = "0",
    original_foldexpr = "0"
  },
  -- ... per window
}
```

**Restoration:**
```lua
M.restore_original(bufnr)
-- 1. Clears autocmds
-- 2. Restores original settings if buffer is in window
-- 3. Cleans up all stored settings for buffer
```

**Window-Specific Approach:**
- Settings stored per-window (not per-buffer)
- Allows same buffer in multiple windows with different fold states
- Handles window splits/closes gracefully
- Preserves original fold settings when switching between buffers

**Fold Structure Example:**
```
--- (YAML header - fold level 1)
title: Chat
 ---

>>> user (fold level 1)
  >>> scrape (fold level 2, nested)
    https://example.com
  <<< content
    Scraped text...
  
  My question about the text

<<< assistant (fold level 1)
  Response text
```

#### 4. `lua/nai/utils/indicators.lua` - Visual Feedback
**Primary Responsibilities:**
- Creates animated loading indicators
- Shows progress during API requests
- Displays model, elapsed time, token count
- Provides placeholder formatting for responses
- Manages indicator lifecycle (create, update, remove)

**Indicator Structure:**
```lua
{
  buffer_id = 123,
  start_row = 10,
  spinner_row = 13,
  end_row = 15,
  timer = uv_timer,
  stats = {
    tokens = 0,
    elapsed_time = 0,
    start_time = 1234567890,
    model = "anthropic/claude-sonnet-4.5"
  }
}
```

**Key Functions:**

**Create Placeholder:**
```lua
M.create_assistant_placeholder(buffer_id, row)
-- Inserts formatted placeholder:
-- 
-- <<< assistant
-- 
-- ⏳ Generating response...
-- 

-- Creates timer for animation (120ms interval)
-- Returns indicator object
```

**Animation Loop:**
```lua
-- Animation frames (Braille spinner)
{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

-- Updates every 120ms:
"⠋ Generating response | 3s elapsed | 150 tokens"
"Using model: claude-sonnet-4.5"

-- Buffer safety checks on each frame
-- Stops if buffer becomes invalid
```

**Update Stats:**
```lua
M.update_stats(indicator, {
  tokens = 150,
  model = "gpt-4"
})
-- Updates indicator.stats
-- Next animation frame will use new values
```

**Remove Indicator:**
```lua
M.remove(indicator)
-- 1. Stops and closes timer
-- 2. Returns start_row for replacement
-- Does NOT delete placeholder lines (caller's responsibility)
```

**Legacy Indicator (Fallback):**
```lua
M.create_at_cursor(buffer_id, row, col)
-- Simple extmark with virtual text
-- Used as fallback for simpler indicators
-- "AI working..." at end of line

M.remove_legacy(indicator)
-- Deletes extmark
```

**Namespace:**
```lua
M.namespace_id = vim.api.nvim_create_namespace('nvim_ai_indicators')
-- Used for extmarks (legacy indicators)
```

**Usage Pattern:**
```lua
-- Create indicator
local indicator = indicators.create_assistant_placeholder(bufnr, row)

-- Register in state
state.register_indicator(indicator_id, indicator)

-- Update with model info
indicators.update_stats(indicator, { model = "gpt-4" })

-- On completion:
local insertion_row = indicators.remove(indicator)
-- Replace placeholder lines with actual response
vim.api.nvim_buf_set_lines(bufnr, insertion_row, insertion_row + 5, false, response_lines)

-- Clear from state
state.clear_indicator(indicator_id)
```

#### 5. `lua/nai/utils/init.lua` - General Utilities
**Primary Responsibilities:**
- Visual selection extraction
- Text formatting with gq
- Re-exports indicators module

**Key Functions:**

**Visual Selection:**
```lua
M.get_visual_selection()
-- 1. Gets '< and '> marks
-- 2. Extracts lines in range
-- 3. Adjusts first/last line for partial selection
-- 4. Joins with newlines
-- Returns: selected text as string
```

**Text Formatting:**
```lua
M.format_with_gq(text, wrap_width, buffer_id)
-- Formats text respecting code blocks and lists
-- wrap_width: default 80
-- buffer_id: for filetype context

-- Process:
-- 1. Split text into lines
-- 2. Track code block state (```)
-- 3. Identify paragraphs, lists, headers
-- 4. Format each paragraph in temp buffer using gq
-- 5. Preserve code blocks, headers, empty lines
-- 6. Join formatted paragraphs

-- List handling:
-- - Sets formatoptions = 'tcroqlwnj'
-- - Sets formatlistpat for various list formats
-- - Preserves indentation and nesting

-- Code block handling:
-- - Detects ``` markers
-- - Skips formatting inside code blocks
-- - Preserves exact content
```

**Re-exports:**
```lua
M.indicators = require('nai.utils.indicators')
-- Makes indicators available as utils.indicators
```

#### 6. `lua/nai/constants.lua` - Marker Definitions
**Primary Responsibilities:**
- Defines all chat block markers
- Provides auto-title instruction text
- Central source of truth for marker strings

**Markers:**
```lua
M.MARKERS = {
  USER = ">>> user",
  ASSISTANT = "<<< assistant",
  SYSTEM = ">>> system",
  CONFIG = ">>> config",
  WEB = ">>> web",
  SCRAPE = ">>> scrape",
  YOUTUBE = ">>> youtube",
  REFERENCE = ">>> reference",
  SNAPSHOT = ">>> snapshot",
  CRAWL = ">>> crawl",
  TREE = ">>> tree",
  ALIAS = ">>> alias:",
}

M.AUTO_TITLE_INSTRUCTION = 
  "
For your first response, please begin with 'Proposed Title: '..."
```

### Important Patterns/Conventions

#### 1. Overlay Architecture
```
Buffer Layers:
├─ Base filetype (markdown/vimwiki) - native Neovim syntax
├─ nvim-ai syntax overlay - custom highlights in separate namespace
└─ Extmarks/virtual text - indicators, decorations

Key: Overlays don't replace base syntax, they augment it
```

#### 2. Window-Specific Settings
```lua
-- Folding and some buffer settings are per-window, not per-buffer
-- Allows same buffer in multiple windows with different states

-- Storage pattern:
M.original_settings["win_" .. winid] = { ... }

-- Cleanup on BufWinLeave, not BufUnload
```

#### 3. Deferred Application
```lua
-- Pattern used throughout:
vim.defer_fn(function()
  if vim.api.nvim_buf_is_valid(bufnr) and state.is_buffer_activated(bufnr) then
    M.apply_syntax_overlay(bufnr)
  end
end, 100)

-- Reason: Race conditions with filetype detection
-- Ensures syntax/folding applied after filetype is set
```

#### 4. Safe Buffer Operations
```lua
-- Always check validity before operations:
if not vim.api.nvim_buf_is_valid(bufnr) then
  return
end

-- Use pcall for operations that might fail:
pcall(vim.api.nvim_buf_clear_namespace, bufnr, ns_id, 0, -1)
```

#### 5. Debouncing
```lua
-- Pattern for expensive operations:
local debounce_timer = nil

local function debounced_highlight(delay)
  if debounce_timer then
    debounce_timer:stop()
    debounce_timer:close()
  end
  
  debounce_timer = vim.loop.new_timer()
  debounce_timer:start(delay or 100, 0, vim.schedule_wrap(function()
    -- Expensive operation
  end))
end
```

### Dependencies on Other Modules

**Required by Buffer Module:**
- `nai.config` - Active filetypes, patterns, highlight colors, folding settings
- `nai.state` - Buffer activation tracking
- `nai.events` - Buffer activation/deactivation events
- `nai.constants` - Marker definitions
- `nai.mappings` - Buffer-local keybindings
- `nai.utils.error` - Buffer validation

**Used by:**
- `nai.init` - Activates buffers, applies syntax when needed
- `nai.parser` - Relies on marker constants
- `nai.api` - Uses indicators for progress feedback

### Entry Points and Main Interfaces

#### Buffer Lifecycle API
```lua
-- Activation
buffer.activate_buffer(bufnr)
buffer.deactivate_buffer(bufnr)

-- Detection
buffer.detect_chat_markers(bufnr)  -- Returns boolean
buffer.should_activate_by_pattern(bufnr)  -- Returns boolean
buffer.should_activate(bufnr)  -- Returns boolean

-- Syntax
buffer.apply_syntax_overlay(bufnr)

-- Setup
buffer.setup_autocmds()  -- Called during plugin initialization
buffer.create_activation_command()  -- Creates :NAIActivate
```

#### Syntax API
```lua
-- Highlight setup
syntax.define_highlight_groups()  -- Called automatically

-- Application
syntax.apply_to_buffer(bufnr)  -- Returns namespace_id
```

#### Folding API
```lua
-- Application
folding.apply_to_buffer(bufnr)
folding.restore_original(bufnr)

-- Fold calculation (called by Neovim)
folding.get_fold_level(lnum)  -- Returns fold level string

-- Setup
folding.setup_autocmds()  -- Global WinEnter handler
```

#### Indicators API
```lua
-- Creation
local indicator = indicators.create_assistant_placeholder(bufnr, row)
local indicator = indicators.create_at_cursor(bufnr, row, col)  -- Legacy

-- Updates
indicators.update_stats(indicator, { tokens = 150, model = "gpt-4" })

-- Removal
local start_row = indicators.remove(indicator)
indicators.remove_legacy(indicator)
```

#### Utils API
```lua
-- Selection
local text = utils.get_visual_selection()

-- Formatting
local formatted = utils.format_with_gq(text, 80, bufnr)

-- Indicators (re-export)
local indicator = utils.indicators.create_assistant_placeholder(bufnr, row)
```

### Configuration Examples

#### Activation Patterns
```lua
require('nai').setup({
  active_filetypes = {
    patterns = { "*.md", "*.wiki", "*.txt" },  -- File patterns
    autodetect = true,  -- Detect chat markers in any file
    enable_overlay = true,  -- Apply syntax highlighting
    enable_folding = true,  -- Apply chat folding
  }
})
```

#### Custom Highlights
```lua
require('nai').setup({
  highlights = {
    user = { fg = "#88AAFF", bold = true },
    assistant = { fg = "#AAFFAA", bold = true },
    system = { fg = "#FFAA88", bold = true },
    special_block = { fg = "#AAAAFF", bold = true },
    placeholder = { fg = "#FFCC66", bold = true },
    signature = { fg = "#777777", italic = true },
  }
})
```

#### Folding Behavior
```lua
-- Default: All folds open
-- User can close with zc, open with zo
-- Navigate with zj/zk (next/prev fold)

-- Fold structure:
--- (YAML)      -- Level 1
>>> user        -- Level 1
  >>> scrape    -- Level 2 (nested)
<<< assistant   -- Level 1
# Heading       -- Level 1 (markdown)
## Subheading  -- Level 2 (markdown)
```

### Buffer Activation Flow

```
┌─────────────────────────────────────────────────────────────┐
│ File Opened / Buffer Created                                │
└───────────────────┬─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────┐
│ BufReadPost / BufNewFile / FileType Event                   │
└───────────────────┬─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────┐
│ should_activate() Check                                      │
│  ├─ Pattern match? (*.md, *.wiki)                           │
│  └─ Has chat markers? (autodetect enabled)                  │
└───────────────────┬─────────────────────────────────────────┘
                    │ Yes
                    ▼
┌─────────────────────────────────────────────────────────────┐
│ activate_buffer()                                            │
│  ├─ state.activate_buffer(bufnr)                            │
│  ├─ events.emit('buffer:activate')                          │
│  ├─ mappings.apply_to_buffer()                              │
│  ├─ syntax.apply_to_buffer()                                │
│  ├─ folding.apply_to_buffer()                               │
│  └─ Setup BufUnload cleanup                                 │
└───────────────────┬─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────┐
│ Deferred Refresh (100ms)                                     │
│  ├─ Re-apply syntax overlay                                 │
│  └─ Refresh folding                                         │
└─────────────────────────────────────────────────────────────┘

