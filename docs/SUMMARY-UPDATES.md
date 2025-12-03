# Summary Updates

Changes made since the main summaries were last generated. When updates in a module become substantial, consider regenerating the affected SUMMARY-.md file.

> **Last Full Regeneration:** 2025-12-03
> - SUMMARY.md

## 2025
### State Management Refactoring - Complete Rewrite with Validation and Snapshots - (2024-12-03)
**Affects:** Core State Management, All Modules

**Files Created:**
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/state/store.lua` - Core immutable state container
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/state/requests.lua` - Request lifecycle manager
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/state/buffers.lua` - Buffer activation manager
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/state/indicators.lua` - UI indicator manager
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/state/ui.lua` - UI state manager (provider, model, processing)
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/tests/test_state_store.lua` - Core store tests (13 tests)
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/tests/test_state_requests.lua` - Request manager tests (15 tests)
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/tests/test_state_managers.lua` - Buffer/indicator/UI tests (14 tests)
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/tests/test_state_integration.lua` - Integration tests (9 tests)

**Files Modified:**
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/state.lua` - Completely rewritten as facade over managers
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/init.lua` - Fixed `M.cancel()` to use manager API instead of direct table access

**Purpose:**
Previous state management used direct mutable table access with no validation, making it prone to bugs and difficult to debug async operations. This refactoring introduces structured state management with validation, error recovery, and change notifications.

**Key Implementation Details:**

**Layer 1 - Core Store (`state/store.lua`):**
- Immutable state container using deep copying
- Nested path access with dot notation (e.g., `"ui.current_provider"`)
- Validation on all `set()` operations with custom validator functions
- Snapshot/restore capabilities for error recovery
- Change notification system with path-specific and wildcard subscriptions
- Atomic multi-path updates with automatic rollback on validation failure

**Layer 2 - Domain Managers:**
Each manager wraps the core store with domain-specific logic:
- **Requests Manager**: Validates request IDs (non-empty strings), adds timestamps automatically, tracks processing state
- **Buffers Manager**: Validates buffer numbers (positive integers), simple activation/deactivation
- **Indicators Manager**: Validates indicator IDs and data structures, manages UI indicator lifecycle
- **UI Manager**: Validates provider names against allowed list, validates model names, tracks processing state

All managers provide:
- Validation on input
- `get()`, `get_all()`, `update()`, `clear()` methods
- `snapshot()` and `restore()` for error recovery
- `subscribe()` for change notifications
- `debug()` for inspection

**Layer 3 - Unified State Module (`state.lua`):**
- Thin facade that delegates to appropriate manager
- Maintains clean API: `state.register_request()`, `state.activate_buffer()`, etc.
- Provides cross-manager operations: `snapshot()` captures all managers, `restore()` restores all
- `reset_processing_state()` clears requests and indicators but preserves buffer activations
- Subscription helpers for common patterns

**Integration Points:**
- `init.lua`: Uses state API for request/indicator management, fixed to use `state.indicators:get_all()` instead of direct access
- `api.lua`: Registers requests, updates status, clears on completion
- `buffer.lua`: Activates/deactivates buffers
- `utils/indicators.lua`: Registers and manages UI indicators
- `error_handler.lua`: Can use snapshots for state rollback on errors (future integration point)

**Design Decisions:**
1. **Three-layer architecture**: Separates concerns (storage, domain logic, unified API) for maintainability
2. **Immutability via deep copying**: Prevents external mutations, trades performance for safety (acceptable for state size)
3. **Validation at manager level**: Each domain knows its own rules, store remains generic
4. **Manager instances created on init**: Allows clean initialization with config values
5. **Kept chat_history simple**: Didn't create a manager for it yet, can be added later if needed
6. **Subscriptions use callbacks**: Simple event system, could be extended to more sophisticated pub/sub if needed
7. **Snapshots are full copies**: Simple but memory-intensive approach, sufficient for current usage patterns

**Breaking Changes:**
- **API Changed**: Direct table access like `state.active_requests[id]` no longer works
- **Must use methods**: `state.register_request(id, data)` instead of `state.active_requests[id] = data`
- **Indicators access**: `state.active_indicators` is now `state.indicators:get_all()`
- **Backward compatibility not maintained**: All code updated to new API

**Testing:**
Comprehensive test coverage with 51 passing tests across:
- Core store functionality (immutability, validation, snapshots, subscriptions)
- Each manager's domain logic
- Integration between managers
- Real-world workflows (register → update → clear)

**Performance Considerations:**
- Deep copying on every `get()` adds overhead but prevents mutation bugs
- Snapshot operations copy entire state tree - acceptable for current state size
- Subscriptions use simple iteration - fine for expected subscriber counts
- No optimization needed yet, but could add lazy copying or structural sharing if needed

**TODO/Follow-up:**
- Consider adding state persistence for session restoration
- Could integrate snapshots into error_handler.lua for automatic rollback on API failures
- Chat history could become a manager if it needs validation or complex operations
- Consider adding state migration system if schema changes become common
- Could add metrics/telemetry around state operations for debugging

**Note:** This is a foundational change affecting all state access. Consider this when debugging any state-related issues. All state modifications now go through validated manager methods.
### Parser Module Refactoring - Registry-Based Message Processing - (2025-12-03)
**Affects:** Parser Module

**Files Created:**
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/parser/registry.lua` - Core registry system
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/parser/processors/user.lua`
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/parser/processors/assistant.lua`
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/parser/processors/system.lua`
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/parser/processors/tree.lua`
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/parser/processors/alias.lua`
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/parser/processors/reference.lua`
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/parser/processors/snapshot.lua`
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/parser/processors/web.lua`
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/parser/processors/youtube.lua`
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/parser/processors/crawl.lua`
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/parser/processors/scrape.lua`

**Files Modified:**
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/parser.lua` - Reduced from ~470 to ~360 lines (~23% reduction)

**Purpose:**
Eliminate massive code duplication in `parser.lua` where 11 different message/block types each had nearly identical parsing and formatting logic. Pattern inspired by successful `blocks/expander.lua` refactoring.

**Key Implementation Details:**
1. **Registry System** (`parser/registry.lua`):
   - Central registration for message processors with standardized interface
   - Each processor defines: `marker` (string or function), `role` (API role), optional `process_content` function, `format` function
   - `match_line()` function checks incoming lines against all registered processors

2. **Individual Processors** (`parser/processors/*.lua`):
   - Each block type (user, assistant, system, reference, snapshot, web, youtube, crawl, tree, scrape, alias) has its own processor file
   - Consolidates both parsing logic AND formatting in one place per block type
   - Complex processors (reference, snapshot, web, etc.) delegate to existing fileutils modules via `process_content`
   - Scrape processor includes special logic for extracting content sections

3. **Parser Refactoring**:
   - Replaced ~100 lines of repetitive `elseif` blocks (lines 88-178) with single registry lookup
   - Replaced long if-else chain for content processing (lines 219-251) with registry-based dispatch
   - All formatting functions now delegate to processors via `format_via_processor()` helper
   - Removed unused `reference_fileutils` require

**Design Decisions:**
- **Special cases remain explicit**: Config blocks, YAML headers, and ignore blocks kept as special cases in main parser since they don't create messages and have different lifecycle
- **Public API preserved**: Formatting functions (`M.format_user_message()`, etc.) maintained for backwards compatibility but delegate to processors internally
- **Processor interface**: Minimal required fields (marker, role, format) with optional extensions (process_content, parse_line) for flexibility

**Integration Points:**
- Processors call existing fileutils modules (`nai.fileutils.reference`, `nai.fileutils.snapshot`, etc.) for special content processing
- Uses `nai.constants.MARKERS` for marker definitions
- All existing code using parser formatting functions continues to work unchanged

**Benefits:**
- **Maintainability**: Adding new block types now requires only creating a processor file and registering it - no changes to main parser logic
- **Testability**: Each processor can be tested independently
- **Consistency**: All block types follow identical pattern
- **Code reduction**: 60-70% reduction in repetitive parsing/formatting code

**Breaking Changes:** None - all public APIs maintained

**TODO/Follow-up:**
- Consider adding processor validation tests
- Potential future: make config block a processor if it becomes more complex
- Consider regenerating SUMMARY.md to reflect new parser architecture
### Added Ignore Block Feature for Documentation - (2025-12-03)
**Affects:** Parser, Block Expander, Syntax Highlighting, Folding, Constants

**Files Modified:**
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/constants.lua`
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/blocks/expander.lua`
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/parser.lua`
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/syntax.lua`
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/folding.lua`

**Purpose:**
Solves the problem of including example prompts and markers in documentation without them being processed as actual chat messages or triggering block expansion. Previously, writing documentation about the plugin's features (e.g., showing examples of `>>> snapshot` or `>>> user` markers) would cause those markers to be parsed and expanded, making it impossible to reference them safely.

**Key Implementation Details:**

1. **New Markers** (constants.lua):
   - Added `IGNORE = ">>> ignore"` and `IGNORE_END = "<<< ignore"` to MARKERS table
   - Content between these markers is treated as plain text documentation

2. **Block Expander** (blocks/expander.lua):
   - Added `in_ignore_block` state tracking in `expand_block_type()`
   - Skips all block expansion (snapshot, scrape, web, etc.) when inside ignore blocks
   - Prevents documentation examples from triggering async requests or file operations

3. **Parser** (parser.lua):
   - Added `in_ignore_block` state tracking in `parse_chat_buffer()`
   - Content inside ignore blocks is added to `text_buffer` as plain text (visible to LLM)
   - Markers inside ignore blocks are NOT parsed (e.g., `>>> user` stays as literal text)
   - This allows the LLM to see examples while preventing them from being interpreted as instructions

4. **Syntax Highlighting** (syntax.lua):
   - Both `>>> ignore` and `<<< ignore` markers highlighted using `Comment` highlight group
   - Makes ignored sections visually distinct (typically grayed out)

5. **Folding** (folding.lua):
   - Ignore blocks fold at level 2 (nested within message blocks)
   - `>>> ignore` starts fold with `">2"`, `<<< ignore` ends with `"<2"`

**Integration Points:**
- Block expander checks ignore state BEFORE calling any processor's `expand()` function
- Parser checks ignore state BEFORE processing any markers (user, assistant, system, etc.)
- Both systems use the same markers from constants.lua for consistency
- Ignore blocks work within any message type (user, assistant, system)

**Design Decisions:**
- **No nesting support**: First `<<< ignore` encountered ends the ignore block, even if there's a `>>> ignore` inside. Keeps implementation simple and predictable.
- **Content visible to LLM**: Ignored content is included in the message sent to the API, just not parsed. This allows documentation to be part of the conversation context.
- **Level 2 folding**: Ignore blocks fold as nested sections (like other special blocks) rather than top-level, since they typically appear within messages.
- **Comment highlighting**: Using built-in `Comment` group ensures compatibility with all color schemes without requiring custom configuration.

**Breaking Changes:**
None. This is purely additive functionality. Existing chats and workflows are unaffected.

**TODO/Follow-up:**
- Consider adding a command or keybinding to quickly wrap selected text in ignore markers
- May want to add ignore block examples to plugin documentation/README
- Could add a visual indicator (virtual text?) showing when cursor is inside an ignore block

### Block Expansion System Refactoring - (2025-12-03)
**Affects:** Core Module (init.lua), Block Processing System, All Block Types (snapshot, youtube, tree, scrape, crawl)

**Files Created:**
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/blocks/expander.lua` - New centralized block expansion orchestrator

**Files Modified:**
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/init.lua` - Simplified `expand_blocks()` from ~200 lines to ~25 lines
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/fileutils/snapshot.lua` - Added expander registration
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/fileutils/youtube.lua` - Added expander registration
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/fileutils/tree.lua` - Added expander registration
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/fileutils/scrape.lua` - Added expander registration
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/fileutils/crawl.lua` - Added expander registration

**Purpose:**
Eliminated massive code duplication in block expansion logic. Previously, `init.lua:expand_blocks()` contained nearly identical ~40-line code blocks for each block type (scrape, snapshot, youtube, tree, crawl). This made the codebase hard to maintain, test, and extend.

**Key Implementation Details:**
- **Block Processor Interface**: Each block type now implements a simple interface:
  ```lua
  {
    marker = function(line) or "string",  -- Detection pattern
    has_unexpanded = function(buffer_id), -- Check for unexpanded blocks
    expand = function(buffer_id, start_line, end_line), -- Expansion logic
    has_active_requests = function() or nil  -- Optional async check
  }
  ```
- **Registry Pattern**: Block processors register themselves when their modules are loaded via `expander.register_processor(name, processor)`
- **Common Expansion Loop**: The expander handles:
  - Finding block boundaries (with improved trailing whitespace handling)
  - Line offset tracking as blocks expand
  - Error handling per block type (uses pcall, continues on error)
  - Notification aggregation (reports all expanded blocks in one message)
  - Async request tracking (for scrape/crawl operations)

**Integration Points:**
- `init.lua:expand_blocks()` now just ensures block modules are loaded (to trigger registration) then calls `expander.expand_all(buffer_id)`
- Each block module (snapshot, youtube, tree, scrape, crawl) auto-registers on load via a `register_with_expander()` function at module end
- The expander uses existing block-specific functions (`has_unexpanded_*`, `expand_*_block`) without modification
- Works with existing `block_processor` module for async operations

**Design Decisions:**
- **Auto-registration on load**: Block modules register themselves rather than requiring manual registration. This keeps the pattern simple but requires explicit `require()` calls in `expand_blocks()` to handle lazy loading.
- **Lazy loading fix**: Added explicit `require()` statements for all block types at the start of `expand_blocks()` to ensure processors are registered before expansion attempts. Without this, first expansion attempt would fail silently.
- **Keep existing block modules**: Rather than consolidating all block logic, kept existing modules (snapshot.lua, scrape.lua, etc.) and just had them implement the interface. This preserves other functions in those modules (e.g., `process_*_block()` for API requests).
- **Expander handles errors**: Individual block processor errors are caught and logged, but don't stop processing of other blocks.
- **Improved boundary detection**: Enhanced `find_block_boundaries()` to trim trailing empty lines when no next marker is found, fixing issues with blocks at end of file.

**Benefits:**
- **88% code reduction** in `expand_blocks()` (200 lines → 25 lines)
- **Consistent behavior** across all block types
- **Easy extensibility**: New block types require only ~10 lines of registration code
- **Better testability**: Expander and individual processors can be tested independently
- **Centralized improvements**: Bug fixes and enhancements to expansion logic now benefit all block types

**Breaking Changes:**
None - the refactoring is internal. Block expansion behavior is identical from user perspective.

**TODO/Follow-up:**
- Consider similar pattern for block parsing in `parser.lua:parse_chat_buffer()` (identified as next refactoring target)
- Could add metrics/telemetry to track which block types are most used
- Potential optimization: Cache registered processors rather than re-requiring modules each time

**Note:** Consider regenerating SUMMARY.md to reflect the new `lua/nai/blocks/` directory structure.
### Block Processor Refactoring - (2025-12-02)
**Affects:** fileutils module (scrape, youtube, crawl, snapshot, tree)

**Files Created:**
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/fileutils/block_processor.lua`

**Files Modified:**
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/fileutils/scrape.lua`
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/fileutils/youtube.lua`
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/fileutils/crawl.lua`
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/fileutils/snapshot.lua`
- `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/fileutils/tree.lua`

**Purpose:**
Eliminated ~300 lines of duplicated code across block expansion modules (scrape, youtube, crawl). Each module had nearly identical indicator management, spinner animation, request tracking, and error handling logic.

**Key Implementation Details:**

Created `block_processor.lua` as a shared framework providing:
- **`expand_async_block(config)`** - Generic async block expansion for API-based operations (scrape/youtube/crawl)
- **`expand_sync_block(config)`** - Generic sync block expansion for local operations (snapshot/tree)
- **Indicator Management** - `create_indicator()`, `start_spinner()`, `stop_spinner()` with configurable animation
- **Request Tracking** - Centralized `active_requests` table replacing per-module tracking
- **Parsing Utilities** - `parse_options()`, `extract_target()` for consistent block parsing
- **Formatting Utilities** - `format_completed_header()`, `format_error_block()` for consistent output

Block modules now use declarative configuration:
```lua
block_processor.expand_async_block({
  buffer_id = buffer_id,
  start_line = start_line,
  end_line = end_line,
  block_type = "scrape",
  progress_marker = ">>> scraping",
  completed_marker = ">>> scraped",
  error_marker = ">>> scrape-error",
  spinner_message = function(url, opts) return "Fetching " .. url end,
  execute = function(url, opts, callback, on_error) ... end,
  format_result = function(result, url, opts) ... end,
})
```

**Integration Points:**
- **State Management**: Block processor maintains its own `active_requests` table; individual modules check this via `has_active_requests()`
- **Parser Module**: Unchanged - still calls module-specific `process_*_block()` functions for API request preparation
- **Init Module**: Unchanged - still calls module-specific `expand_*_block()` functions, now thin wrappers around block_processor
- **Buffer Module**: No changes required - block expansion interface remains identical

**Design Decisions:**
1. **Kept module files as thin wrappers** - Rather than consolidating everything into block_processor, each module (scrape.lua, youtube.lua, etc.) retains its API-specific logic and provides a familiar interface
2. **Two expansion patterns** - `expand_async_block()` for API operations with full spinner/request tracking, `expand_sync_block()` for local operations with optional spinner
3. **Centralized request tracking** - Single source of truth for active requests across all block types, simplifying state management
4. **Configuration over code** - Block behavior defined declaratively, making new block types trivial to add

**Breaking Changes:**
None - All public APIs remain unchanged. Internal implementation details shifted to block_processor but external interfaces (function signatures, return values) are identical.

**Benefits:**
- Reduced code duplication by ~300 lines
- Consistent behavior across all block types
- Easier to add new block types (just provide config)
- Centralized spinner/indicator logic for easier debugging
- Added spinner support to snapshot/tree blocks for better UX on large operations

**TODO/Follow-up:**
- Consider adding block processor to handle reference/web blocks for complete consistency
- Add configuration option to customize spinner animation frames/speed
- Consider adding progress callbacks for long-running operations (e.g., "Crawled 3/10 pages...")
- Add unit tests for block_processor module

**Note:** Consider regenerating SUMMARY-FILEUTILS.md to reflect the new block_processor architecture.
### Standardized Error Handling & Chat Function Refactoring - (2025-12-02)
**Affects:** Core Module (API, Init, State, Utils)

#### Files Modified/Created
- **Created:** `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/utils/error_handler.lua` (new)
- **Modified:** `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/init.lua`
- **Modified:** `/Users/nathanbraun/code/github.com/nathanbraun/nvim-ai/lua/nai/api.lua`

#### Purpose
1. **Error Handling:** Eliminate inconsistent error handling patterns across async operations, ensure proper state cleanup in all error scenarios
2. **Code Quality:** Reduce complexity in `M.chat()` function (230+ lines → 65 lines) by extracting focused, testable components
3. **Robustness:** Fix buffer lifecycle bug in `M.reload()` function

#### Key Implementation Details

**Error Handler (`error_handler.lua`):**
- `handle_request_error(opts)`: Centralized error handling with guaranteed state cleanup
  - Updates request state to 'error'
  - Emits `request:error` event
  - Schedules error callback via `vim.schedule()`
  - Clears request from state after callback completes
- `handle_api_error(opts)`: Wrapper for API-specific errors, delegates to `handle_request_error()`
- `handle_request_cancellation(request_id)`: Standardized cancellation with state updates and event emission

**API Module Changes:**
- Replaced 6 different error handling paths in `process_response()` with standardized calls to `error_handler`
- All errors now follow consistent pattern: state update → event emission → callback → cleanup
- Updated `M.cancel_request()` to use `error_handler.handle_request_cancellation()`

**Chat Function Refactoring:**
Extracted `M.chat()` into 7 focused functions:
1. `validate_and_prepare_buffer(buffer_id)` - Buffer activation logic
2. `try_expand_blocks(buffer_id)` - Block expansion check
3. `parse_buffer_content(buffer_id)` - Parse buffer → messages + config
4. `ensure_user_message(buffer_id, messages)` - Validate/add user message
5. `prepare_chat_request(buffer_id, messages, chat_config)` - Create indicator, handle auto-title
6. `handle_chat_response(...)` - Process successful response, update buffer
7. `handle_chat_error(...)` - Handle error response, update buffer

New `M.chat()` is now a clean orchestrator with 7 clear steps.

#### Integration Points
- **State Module:** Error handler directly updates `state.active_requests` and clears requests after callbacks
- **Events Module:** All errors emit events (`request:error`, `request:cancel`) for potential monitoring/logging
- **API → Init Flow:** API handles state/events, Init handles UI (indicators, buffer updates)
- **Parser Module:** Chat refactoring maintains existing parser integration for message formatting

#### Design Decisions & Tradeoffs
1. **Separation of Concerns:** Error handler manages state/events; callers manage UI (indicators, buffers)
   - *Rationale:* Keeps error handler focused, allows different UI responses per context
   - *Tradeoff:* Slightly more coordination required between modules

2. **Local Functions for Chat Components:** Helper functions are local (not in M table)
   - *Rationale:* These are implementation details, not public API
   - *Tradeoff:* Not directly testable, but `M.chat()` integration tests cover them

3. **Async Callback Pattern:** Maintained existing callback-based approach rather than promises/coroutines
   - *Rationale:* Consistent with Neovim's async patterns, minimal disruption
   - *Tradeoff:* Callback nesting still exists but now more manageable

#### Breaking Changes
None. All changes are internal refactoring. Public API (`M.chat()`, `api.chat_request()`) signatures unchanged.

#### Bug Fixes
- **Fixed:** `M.reload()` referenced undefined `buffer_id` variable (line 116)
  - Changed to use `current_buf` which is properly defined

#### Testing Notes
- Existing test suite passes without modification
- Error scenarios now have consistent behavior (verified manually)
- Cancellation properly cleans up state and indicators

#### TODO/Follow-up
- Consider adding unit tests for individual chat helper functions (would require making them testable)
- Monitor error handler in production for edge cases
- Potential future: Add retry logic to `error_handler` for transient failures
- Consider extracting `handle_chat_response()` further (still ~70 lines)
