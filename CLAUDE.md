# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

nvim-ai is a Neovim plugin for AI-powered chat within the editor. Users chat in markdown buffers with special block syntax for embedding files and directory trees. Conversations are saved as `.nai` (markdown) files.

## Running Tests

Tests run inside Neovim:
```
:lua require('nai').run_tests()
:lua require('nai.tests').run_all()
```
Test files are in `lua/nai/tests/` using a custom framework (`framework.lua`). Results display in a floating window.

## Architecture

**Core flow**: User triggers `:NAIChat` → `init.lua:chat()` → blocks expanded → `parser.lua` extracts messages → `api.lua` sends request → response inserted into buffer → new user prompt appended.

**Key modules** (all under `lua/nai/`):
- `init.lua` — Main orchestration: chat flow, buffer lifecycle, `setup()` entry point
- `api.lua` — Unified API handler; dispatches to all providers via curl
- `api/request_body.lua` — Provider-specific request formatting (OpenAI-style, Google, Ollama, o3)
- `api/response_parser.lua` — Provider-specific response extraction
- `config.lua` — Provider definitions, model lists, credentials loading from `~/.config/nvim-ai/credentials.json`
- `parser.lua` — Converts buffer content ↔ API message arrays, handles aliases
- `state.lua` — Facade over specialized state managers in `state/`
- `openclaw.lua` — HTTP/SSE gateway for OpenClaw provider (not OpenAI-compatible)
- `gateway.lua` — WebSocket integration for moltbot
- `verification.lua` — Cryptographic signature generation/verification for chat integrity
- `fileutils/` — Block expansion: file references, snapshots, directory trees

**Plugin commands** are registered in `plugin/nvim-ai.lua`: `:NAIChat`, `:NAINew`, `:NAICancel`, `:NAIExpand`, `:NAIModel`, `:NAIProvider`, `:NAIUser`, `:NAIReference`, `:NAISnapshot`, `:NAITree`.

## Provider System

Providers are defined in `config.lua` with endpoint, models, and auth. The `api.lua` module routes through a single `chat_request()` function. Adding a provider requires:
1. Config entry in `config.lua` (endpoint, models, description)
2. Request body formatting in `api/request_body.lua`
3. Response parsing in `api/response_parser.lua`

Providers treating API keys as unnecessary (local providers like ollama, openclaw, claude_proxy) are handled specially in `config.lua:get_api_key()`.

## Design Patterns

- **Registry pattern**: Processor registry in `parser/` allows extensible message/block types (used by external plugins like nvim-dumpling)
- **Async-first**: All network operations are non-blocking with error callbacks and state cleanup
- **Facade pattern**: `state.lua` delegates to specialized managers in `state/`
- **Event system**: Pub/sub for cross-component communication

## File Format

`.nai` files are markdown with role markers (`## user`, `## assistant`, `## system`) and special blocks (`@file`, `@snapshot`, `@tree`) that get expanded before sending to the API.
