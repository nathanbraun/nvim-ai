-- lua/nai/config.lua
local M = {}

-- Default configuration
M.defaults = {
  credentials = {
    file_path = "~/.config/nvim-ai/credentials.json", -- Single file for all credentials
  },
  active_provider = "openrouter",                     -- "openai", "openrouter", etc.
  mappings = {
    enabled = true,                                   -- Whether to apply default key mappings
    intercept_ctrl_c = true,                          -- New option to intercept Ctrl+C
    -- Default mappings will be used from the mappings module
  },
  providers = {
    openai = {
      name = "OpenAI",
      description = "OpenAI API (GPT models)",
      model = "gpt-4o",
      temperature = 0.7,
      max_tokens = 10000,
      endpoint = "https://api.openai.com/v1/chat/completions",
    },
    openrouter = {
      name = "OpenRouter",
      description = "OpenRouter API (Multiple providers)",
      model = "anthropic/claude-3.7-sonnet",
      temperature = 0.7,
      max_tokens = 10000,
      endpoint = "https://openrouter.ai/api/v1/chat/completions",
      models = {
        "anthropic/claude-3.7-sonnet",
        "google/gemini-2.0-flash-001",
        "openai/gpt-4o",
        "openai/gpt-4o-mini",
        "perplexity/r1-1776",
      },
    },
  },
  active_filetypes = {
    patterns = { "*.md", "*.markdown", "*.wiki" }, -- File patterns to activate on
    autodetect = true,                             -- Detect chat blocks in any file
    enable_overlay = true,                         -- Enable syntax overlay
    enable_folding = true,                         -- Enable chat folding
  },
  tools = {
    dumpling = {
      base_endpoint = "https://app.dumplingai.com/api/v1/", -- Base endpoint for all Dumpling API calls
      format = "markdown",                                  -- Output format: markdown, html, or screenshot
      cleaned = true,                                       -- Whether to clean the output
      render_js = true,                                     -- Whether to render JavaScript
      max_content_length = 100000,                          -- Max length to prevent excessively large responses
      include_timestamps = true,                            -- Whether to include timestamps in the output
    },
  },
  chat_files = {
    directory = vim.fn.expand("~/notes/"), -- Default save location
    format = "{id}.wiki",                  -- Filename format
    auto_save = false,                     -- Save after each interaction
    id_length = 4,                         -- Length of random ID
    use_timestamp = false,                 -- Use timestamp instead of random ID if true
    auto_title = true,                     -- Automatically generate title for untitled chats
    header = {
      enabled = true,                      -- Whether to include YAML header
      template = [[---
title: {title}
date: {date}
tags: [ai]
---]],
    },
  },
  default_system_prompt = "You are a general assistant.",
  expand_placeholders = false,
  highlights = {
    user = { fg = "#88AAFF", bold = true },            -- User message highlighting
    assistant = { fg = "#AAFFAA", bold = true },       -- Assistant message highlighting
    system = { fg = "#FFAA88", bold = true },          -- System message highlighting
    special_block = { fg = "#AAAAFF", bold = true },   -- Special blocks (scrape, youtube, etc.)
    error_block = { fg = "#FF8888", bold = true },     -- Error blocks
    content_start = { fg = "#AAAAAA", italic = true }, -- Content markers
    placeholder = { fg = "#FFCC66", bold = true },     -- Golden yellow for placeholders
  },
  aliases = {
    translate = {
      system =
      "Translate the following text to Spanish",
      user_prefix = "",
    },
    ["daily-review"] = {
      system =
      [[Your job is to evaluate some markdown text containing notes for a daily review and making sure it includes everything it's supposed to.

Rules:
- Only look at the sections under `# 2. NOTES` and `# 3. REVIEW` -- you can
  ignore everything under `# 1. PLAN.`
- Under 3, make sure the following sections are filled out (extra sections are
  OK) with the following:

  - PROJECTS
    - projects worked on
    - make sure number of pomos is listed for each project
  - BLOCK DONE
    - block tasks done this day
    - can be 'na' or 'none' but shouldn't be empty
  - then under TODO there should be three sub sections
    - CAN WAIT
      - tasks/notes that can wait till next weekly review
      - can be 'na' or 'none' but shouldn't be empty
    - SHOULDN'T WAIT
      - tasks/notes that should not wait till next weekly review
      - can be 'na' or 'none' but shouldn't be empty
    - NEW BLOCK
      - new small block toask items
      - can be 'na' or 'none' but shouldn't be empty
      - items that are also under BLOCK DONE are fine, that just means they were added and completed the same day
  - GRATITUDE
    - three things I'm grateful for

- Then make sure 2. NOTES has:
  - INTERSTITIAL
    - notes as bullet points in the format hh:mm, with notes underneath, like
      this:

```
- 08:58
  - weekly review
```

Instructions:
- If all of these sections are present, the plan meets the requirements. In this case respond, "Plan meets requirements" and nothing else.
- If any are missing, the plan does not meet requirements, no matter what else is there. In this case, respond "Plan does not meet requirements.", then concisely detail what's missing.
- Note it's not your job to evaluate the specific content of each section unless specified above.]],
      user_prefix = [[The file is here:
        $FILE_CONTENTS
        ]]
    },
    refactor = {
      system =
      "You are a coding expert. Refactor the provided code to improve readability, efficiency, and adherence to best practices. Explain your key improvements.",
      user_prefix = "Refactor the following code:",
    },
    explain = {
      system =
      "You are a coding teacher. Explain the following code in detail, including its purpose, how it works, and any notable patterns or techniques used.",
      user_prefix = "Explain this code:",
    },
    test = {
      system =
      "You are a testing expert. Generate comprehensive unit tests for the provided code, focusing on edge cases and full coverage.",
      user_prefix = "Generate tests for:",
    },
  },
  debug = {
    enabled = false,
    auto_title = false,
  },
}

-- Current configuration (will be populated by setup)
M.options = vim.deepcopy(M.defaults) -- Initialize with defaults immediately

-- Function to ensure the credentials directory exists
local function ensure_config_dir()
  local config_dir = vim.fn.fnamemodify(vim.fn.expand(M.options.credentials.file_path), ":h")
  if vim.fn.isdirectory(config_dir) == 0 then
    vim.fn.mkdir(config_dir, "p")
    return true -- Directory was created
  end
  return false  -- Directory already existed
end

-- Function to read credentials from JSON file
local function read_credentials()
  local credentials = {}
  local config_file = vim.fn.expand(M.options.credentials.file_path)

  -- Check if file exists
  if vim.fn.filereadable(config_file) == 1 then
    local content = vim.fn.readfile(config_file)
    local success, creds = pcall(vim.json.decode, table.concat(content, '\n'))

    if success and type(creds) == "table" then
      credentials = creds
    else
      -- Log error but don't expose details that might contain API keys
      vim.notify("Error parsing credentials file", vim.log.levels.ERROR)
    end
  end

  return credentials
end

-- Function to get API key for a specific provider
function M.get_api_key(provider)
  -- Try environment variable first
  local env_var = provider:upper() .. "_API_KEY"
  local key = vim.env[env_var]
  if key and key ~= "" then
    return key
  end

  -- Try credentials file
  local credentials = read_credentials()
  if credentials[provider] then
    return credentials[provider]
  end

  -- For backward compatibility, try old token files
  local legacy_paths = {
    openai = "~/.config/openai.token",
    openrouter = "~/.config/open-router.token"
  }

  if legacy_paths[provider] then
    local token_file = vim.fn.expand(legacy_paths[provider])
    if vim.fn.filereadable(token_file) == 1 then
      local lines = vim.fn.readfile(token_file)
      if #lines > 0 then
        key = vim.fn.trim(lines[1])
        if key ~= "" then
          return key
        end
      end
    end
  end

  return nil
end

-- Function to get the current provider configuration
function M.get_provider_config()
  local provider = M.options.active_provider
  return M.options.providers[provider]
end

-- Auto-initialize with defaults and try to load API key
local function init_config()
  -- Create config directory if needed
  ensure_config_dir()

  -- For backward compatibility with old config structure
  if M.options.provider then
    M.options.active_provider = M.options.provider
  end
end

-- Setup function to merge user config with defaults
function M.setup(opts)
  -- Merge user options with defaults
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})

  -- Handle backward compatibility
  if opts and opts.openai then
    -- Convert old config structure to new
    if not M.options.providers then
      M.options.providers = {}
    end

    -- Migrate openai config
    if not M.options.providers.openai then
      M.options.providers.openai = {}
    end
    for k, v in pairs(opts.openai) do
      if k ~= "api_key" and k ~= "token_file_path" then
        M.options.providers.openai[k] = v
      end
    end

    -- Migrate openrouter config
    if opts.openrouter and not M.options.providers.openrouter then
      M.options.providers.openrouter = {}
      for k, v in pairs(opts.openrouter) do
        if k ~= "api_key" and k ~= "token_file_path" then
          M.options.providers.openrouter[k] = v
        end
      end
    end
  end

  -- Initialize configuration
  init_config()

  return M.options
end

-- For backward compatibility
function M.switch_provider(provider)
  M.options.active_provider = provider
end

function M.save_credential(provider, api_key)
  -- Ensure directory exists
  ensure_config_dir()

  -- Read existing credentials
  local credentials = read_credentials()

  -- Update the credential
  credentials[provider] = api_key

  -- Write back to file
  local config_file = vim.fn.expand(M.options.credentials.file_path)
  local json_str = vim.json.encode(credentials)

  local file = io.open(vim.fn.expand(config_file), "w")
  if file then
    file:write(json_str)
    file:close()
    vim.notify("Saved API key for " .. provider, vim.log.levels.INFO)
    return true
  else
    vim.notify("Failed to save API key", vim.log.levels.ERROR)
    return false
  end
end

function M.get_dumpling_api_key()
  -- Try environment variable first
  local key = vim.env["DUMPLING_API_KEY"]
  if key and key ~= "" then
    return key
  end

  -- Try credentials file
  local credentials = read_credentials()
  if credentials["dumpling"] then
    return credentials["dumpling"]
  end

  -- Fall back to legacy path (if any)
  local legacy_path = "~/.config/dumpling.token"
  local token_file = vim.fn.expand(legacy_path)
  if vim.fn.filereadable(token_file) == 1 then
    local lines = vim.fn.readfile(token_file)
    if #lines > 0 then
      key = vim.fn.trim(lines[1])
      if key ~= "" then
        return key
      end
    end
  end

  return nil
end

return M
