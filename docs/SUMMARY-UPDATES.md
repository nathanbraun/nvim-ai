# Summary Updates

Changes made since the main summaries were last generated. When updates in a module become substantial, consider regenerating the affected SUMMARY-.md file.

> **Last Full Regeneration:** 2026-02-04
> - SUMMARY.md

## 2026
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
