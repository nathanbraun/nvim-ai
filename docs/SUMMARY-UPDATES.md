# Summary Updates

Changes made since the main summaries were last generated. When updates in a module become substantial, consider regenerating the affected SUMMARY-.md file.

> **Last Full Regeneration:** 2026-02-04
> - SUMMARY.md

## 2026
### Web Features Extracted to nvim-dumpling Plugin - (2026-02-05)
**Affects:** Core plugin architecture, web content gathering

**Files Changed:**
- `lua/nai/fileutils/scrape.lua` - (deleted) Moved to nvim-dumpling
- `lua/nai/fileutils/crawl.lua` - (deleted) Moved to nvim-dumpling
- `lua/nai/fileutils/youtube.lua` - (deleted) Moved to nvim-dumpling
- `lua/nai/fileutils/web.lua` - (deleted) Moved to nvim-dumpling
- `lua/nai/parser/processors/scrape.lua` - (deleted) Moved to nvim-dumpling
- `lua/nai/parser/processors/crawl.lua` - (deleted) Moved to nvim-dumpling
- `lua/nai/parser/processors/youtube.lua` - (deleted) Moved to nvim-dumpling
- `lua/nai/parser/processors/web.lua` - (deleted) Moved to nvim-dumpling
- `lua/nai/constants.lua` - (modified) Removed WEB, SCRAPE, YOUTUBE, CRAWL markers
- `lua/nai/config.lua` - (modified) Removed tools.dumpling section and get_dumpling_api_key()
- `lua/nai/parser.lua` - (modified) Removed web-related processor registrations and format functions
- `plugin/nvim-ai.lua` - (modified) Removed NAIScrape, NAICrawl, NAIYoutube, NAIWeb, NAIExpandScrape commands; added deprecation stubs

**Purpose:** Reduce plugin bloat by extracting rarely-used web content gathering features (Dumpling API integration) into a separate optional plugin, improving maintainability and conceptual clarity of nvim-ai's core chat functionality.

**Implementation:** Created new `nvim-dumpling` plugin (separate repository) that contains all web scraping, crawling, YouTube transcript, and simple web fetching features. The new plugin can work standalone or integrate with nvim-ai by detecting its presence and registering processors/expanders with nvim-ai's registry system. Deprecation stubs in nvim-ai provide helpful migration messages pointing users to the new plugin. The `block_processor.lua` utility was copied (not moved) to nvim-dumpling to avoid cross-plugin dependencies, as it's still used by nvim-ai's snapshot/tree/reference features.

**New Dependencies:** None for nvim-ai (features removed). nvim-dumpling requires Dumpling API key for scrape/crawl/youtube features.

**Breaking Changes:** Users relying on `:NAIScrape`, `:NAICrawl`, `:NAIYoutube`, `:NAIWeb` commands will see deprecation warnings. Migration: Install nvim-dumpling plugin and use new commands (`:DumpScrape`, `:DumpCrawl`, `:DumpYoutube`, `:DumpWeb`). Existing chat files with `>>> scrape`, `>>> crawl`, etc. blocks will not expand unless nvim-dumpling is installed.

**Related Files:**
- `lua/nai/fileutils/block_processor.lua` - Still used by nvim-ai for snapshot/tree/reference expansion
- `lua/nai/blocks/expander.lua` - Registry system that nvim-dumpling integrates with
- `lua/nai/parser/registry.lua` - Message processor registry that nvim-dumpling uses
- nvim-dumpling plugin repository: https://github.com/nathanbraun/nvim-dumpling

**TODO/Follow-up:**
- Test nvim-dumpling integration with nvim-ai in real usage
- Consider whether to remove deprecation stubs after a few release cycles
- Update nvim-ai README to mention nvim-dumpling as optional extension
- Verify all existing chat files with web blocks still work when nvim-dumpling is installed

### Tree Command Ignore Pattern Support - (2026-02-05)
**Affects:** fileutils/tree, plugin commands

**Files Changed:**
- `lua/nai/fileutils/tree.lua` - (modified) Added ignore pattern parsing from marker line and support for `-I` flag
- `plugin/nvim-ai.lua` - (modified) Updated `:NAITree` command to parse and pass ignore patterns

**Purpose:** Enable users to exclude specific directories from tree output (e.g., `node_modules`, `dist`, `build`) using the standard tree `-I` flag, matching the behavior of the system `tree` command.

**Implementation:** 
- Added `parse_marker_options()` function to extract options from the tree marker line itself (e.g., `>>> tree -I 'node_modules|dist'`)
- Updated `expand_tree_in_buffer()` to parse options from first line and append them to the tree command execution
- Modified `format_tree_block()` to accept optional `ignore_patterns` parameter and include it in the marker line
- Updated `:NAITree` command parser to extract `-I` flag with quoted or unquoted patterns (supports both single/double quotes)
- Maintains backward compatibility with existing tree blocks without ignore patterns
- Updated `has_unexpanded_tree_blocks()` to match `>>> tree` with optional content after marker

**New Dependencies:** None

**Breaking Changes:** None - existing tree blocks continue to work as before

**Related Files:** 
- `lua/nai/blocks/expander.lua` - Calls the tree processor's marker matching function
- `lua/nai/parser/processors/tree.lua` - Processes tree blocks for API requests (unchanged, uses expanded content)

**TODO/Follow-up:** Could add support for other tree flags (`-L` for depth limit, `-a` for hidden files) using same pattern if needed
### Unified Model Picker with OpenClaw Context Awareness - (2026-02-05)
**Affects:** Model Selection, OpenClaw Integration

**Files Changed:**
- `lua/nai/tools/picker.lua` - (modified) Added context-aware model selection based on active provider

**Purpose:** Enables seamless switching between traditional providers and OpenClaw models within a single `:NAIModel` command, while providing an escape hatch to switch providers when in OpenClaw mode.

**Implementation:** The `select_model()` function now checks `config.options.active_provider` to determine context. If `active_provider == "openclaw"`, it calls `select_model_openclaw_context()` which fetches available models from the current gateway and displays them with a "→ Switch Provider/Gateway..." option at the top (followed by divider). Selecting this option calls `select_model_traditional()` to show the standard provider/model picker. If `active_provider` is not openclaw, it directly shows the traditional picker. The `select_model_traditional()` function was extracted from the original `select_model()` to enable reuse. All picker implementations (snacks, telescope, fzf-lua, simple) handle the special `__switch_provider__` value and dividers appropriately.

**New Dependencies:** None

**Breaking Changes:** None - behavior is additive. `:NAIModel` now adapts to context but maintains backward compatibility.

**Related Files:**
- `lua/nai/openclaw.lua` - Provides `fetch_models()`, `get_session_key()`, `set_model()` functions
- `lua/nai/config.lua` - Source of `active_provider` state
- `plugin/nvim-ai.lua` - `:NAIModel` and `:NAIOpenClawModel` commands (both still functional)

**TODO/Follow-up:**
- Consider removing `:NAIOpenClawModel` command if redundant (currently kept for explicit model-only switching)
 Could add gateway selection if user has multiple OpenClaw gateways configured (currently uses first/active gateway)

### OpenClaw Model Selection Integration - (2026-02-05)
**Affects:** OpenClaw Integration, Tools/Picker

**Files Changed:**
- `lua/nai/openclaw.lua` - (modified) Added `fetch_models()`, `set_model()`, `get_current_model()`, `set_current_model()` functions
- `lua/nai/tools/picker.lua` - (modified) Added `select_openclaw_model()` and picker implementations for snacks/telescope/fzf-lua/simple
- `plugin/nvim-ai.lua` - (modified) Added `:NAIOpenClawModel` command

**Purpose:** Enables users to select and change the AI model being used in OpenClaw sessions directly from Neovim, similar to how `:NAIModel` works for other providers.

**Implementation:** The feature works in two parts: (1) openclaw-nvim plugin exposes a `GET /nvim/models` endpoint that reads from `config.agents.defaults.models` to return available models with their aliases and tags, (2) nvim-ai fetches this list, displays a picker, and sends `/model <selection>` as a directive-only message to OpenClaw to set the model for the current session. Model selection is tracked locally per-buffer via `vim.b[bufnr].openclaw_model` for display purposes.

**New Dependencies:** None

**Breaking Changes:** None

**Related Files:** 
- `openclaw-nvim/src/http-handler.ts` - Added `/nvim/models` endpoint (separate repo)
- OpenClaw's `config.agents.defaults.models` - Source of model allowlist/catalog

**TODO/Follow-up:** 
- Consider integrating into `:NAIModel` to auto-detect OpenClaw provider
- Could add gateway selection if multiple gateways are configured
- Could query current session model from OpenClaw instead of tracking locally

### Fixed Multiple Block Expansion Bug - (2026-02-05)
**Affects:** Block Expansion System

**Files Changed:**
- `lua/nai/blocks/expander.lua` - (modified) Rewrote `expand_block_type()` to restart loop after each expansion

**Purpose:** Fixed bug where only the first block of each type (snapshot, scrape, etc.) would expand when multiple blocks existed in a buffer, causing subsequent blocks to be skipped.

**Implementation:** The original loop used a single pass with line offset tracking, but after expanding a block and re-fetching buffer lines, the loop counter would skip over blocks that shifted position. New implementation uses a `while` loop that restarts from the beginning after each successful expansion, with a safety limit of 100 iterations to prevent infinite loops. The `has_unexpanded()` function naturally terminates the loop when no more blocks need expansion (e.g., `>>> snapshot` becomes `>>> snapshotted [timestamp]`).

**New Dependencies:** None

**Breaking Changes:** None - behavior change is a bug fix, not an API change

**Related Files:** 
- `lua/nai/fileutils/snapshot.lua` - Uses `has_unexpanded_snapshot_blocks()` to detect unexpanded blocks
- `lua/nai/fileutils/scrape.lua` - Uses `has_unexpanded_scrape_blocks()` to detect unexpanded blocks
- `lua/nai/fileutils/crawl.lua` - Similar pattern (not verified but likely affected)
- `lua/nai/fileutils/youtube.lua` - Similar pattern (not verified but likely affected)
- `lua/nai/fileutils/tree.lua` - Similar pattern (not verified but likely affected)
- `lua/nai/fileutils/reference.lua` - NOT affected (reference blocks are parser-only, don't register with expander)

**TODO/Follow-up:** None
