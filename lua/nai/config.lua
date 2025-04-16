-- lua/nai/config.lua
local M = {}

local path = require('nai.utils.path')

-- Default configuration
M.defaults = {
  credentials = {
    file_path = "~/.config/nvim-ai/credentials.json", -- Single file for all credentials
  },
  active_filetypes = {
    patterns = { "*.md", "*.markdown", "*.wiki" }, -- File patterns to activate on
    autodetect = true,                             -- Detect chat blocks in any file
    enable_overlay = true,                         -- Enable syntax overlay
    enable_folding = true,                         -- Enable chat folding
  },
  default_system_prompt = "You are a general assistant.",
  active_provider = "openrouter", -- "openai", "openrouter", etc.
  mappings = {
    enabled = true,               -- Whether to apply default key mappings
    intercept_ctrl_c = true,      -- New option to intercept Ctrl+C
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
    ollama = {
      name = "Ollama",
      description = "Local models via Ollama",
      model = "llama3.2:latest",
      temperature = 0.7,
      max_tokens = 4000,
      endpoint = "http://localhost:11434/api/chat",
      models = {
        "llama3.2:latest",
      },
    },
  },
  chat_files = {
    directory = vim.fn.expand("~/nvim-ai-notes"), -- Default save location
    format = "{id}.md",                           -- Filename format
    auto_save = false,                            -- Save after each interaction
    id_length = 4,                                -- Length of random ID
    use_timestamp = false,                        -- Use timestamp instead of random ID if true
    auto_title = true,                            -- Automatically generate title for untitled chats
    header = {
      enabled = true,                             -- Whether to include YAML header
      template = [[---
title: {title}
date: {date}
tags: [ai]
---]],
    },
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
      "You are an interpretor. Translate any further text/user messages you recieve to Spanish. If the text is a question, don't answer it, just translate the question to Spanish.",
      user_prefix = "",
      config = {
        model = "openai/gpt-4o-mini",
        temperature = 0.1,
      }
    },
    refactor = {
      system =
      "You are a coding expert. Refactor the provided code to improve readability, efficiency, and adherence to best practices. Explain your key improvements.",
      user_prefix = "Refactor the following code:",
    },
    test = {
      system =
      "You are a testing expert. Generate comprehensive unit tests for the provided code, focusing on edge cases and full coverage.",
      user_prefix = "Generate tests for:",
    },
    ["check-todo-list"] = {
      system =
      [[Your job is to evaluate a todo list and make sure everything is checked off.


Instructions:
- If everything is checked off, respond "Looks good!" and nothing else.
- Otherwise remind me what I still have to do.]],
      config = {
        expand_placeholders = true
      },
      user_prefix = [[The todo is here:
        $FILE_CONTENTS
        ]]
    },
  },
  format_response = {
    enabled = true,             -- Whether to format the assistant's response
    exclude_code_blocks = true, -- Don't format inside code blocks
    wrap_width = 80             -- Width to wrap text at
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
  local config_dir = vim.fn.fnamemodify(path.expand(M.options.credentials.file_path), ":h")
  return path.mkdir(config_dir)
end

-- Function to read credentials from JSON file
local function read_credentials()
  local credentials = {}
  local config_file = path.expand(M.options.credentials.file_path)

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
  if provider == "ollama" then
    -- Check if endpoint is not localhost
    local endpoint = M.options.providers.ollama.endpoint
    if not endpoint:match("localhost") and not endpoint:match("127.0.0.1") then
      -- Try environment variable first
      local key = vim.env.OLLAMA_API_KEY
      if key and key ~= "" then
        return key
      end

      -- Try credentials file
      local credentials = read_credentials()
      if credentials.ollama then
        return credentials.ollama
      end
    else
      -- Return a dummy key for local instances that don't need auth
      return "local"
    end
  end

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

  -- Validate configuration
  local validator = require('nai.validate')
  local valid = validator.apply_validation(M.options)

  if not valid then
    vim.notify("Using default configuration due to validation errors", vim.log.levels.WARN)
    -- We'll continue with merged config, but user has been warned about issues
  end

  -- Initialize configuration
  init_config()

  -- Initialize state with config
  require('nai.state').init(M.options)

  -- If Ollama is the active provider, ensure the model is valid
  if M.options.active_provider == "ollama" then
    M.ensure_valid_ollama_model(M.options.providers.ollama)
  end

  return M.options
end

-- For backward compatibility
function M.switch_provider(provider)
  M.options.active_provider = provider
end

function M.save_credential(provider, api_key)
  -- Ensure directory exists
  local success = ensure_config_dir()
  if not success then
    vim.notify("Failed to create config directory", vim.log.levels.ERROR)
    return false
  end

  -- Read existing credentials
  local credentials = read_credentials()

  -- Update the credential
  credentials[provider] = api_key

  -- Write back to file
  local config_file = path.expand(M.options.credentials.file_path)
  local json_str = vim.json.encode(credentials)

  local file = io.open(config_file, "w")
  if file then
    file:write(json_str)
    file:close()

    -- Set permissions to be readable only by the owner
    if vim.fn.has('unix') == 1 then
      vim.fn.system("chmod 600 " .. vim.fn.shellescape(config_file))
    end

    return true
  else
    vim.notify("Failed to save API key: could not write to " .. config_file, vim.log.levels.ERROR)
    return false
  end
end

function M.get_dumpling_api_key()
  -- Try environment variable first
  local key = vim.env["DUMPLING_API_KEY"]
  if key and key ~= "" then
    if M.options.debug and M.options.debug.enabled then
      vim.notify("DEBUG: Found Dumpling API key in environment variable", vim.log.levels.DEBUG)
    end
    return key
  end

  -- Try credentials file
  local credentials = read_credentials()
  if credentials["dumpling"] then
    if M.options.debug and M.options.debug.enabled then
      vim.notify("DEBUG: Found Dumpling API key in credentials file", vim.log.levels.DEBUG)
    end
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

  if M.options.debug and M.options.debug.enabled then
    vim.notify("DEBUG: No Dumpling API key found", vim.log.levels.DEBUG)
  end
  return nil
end

function M.ensure_valid_ollama_model(provider_config)
  -- Only do this for Ollama provider
  if provider_config.name ~= "Ollama" then
    return
  end

  -- Check if ollama command is available
  if vim.fn.executable('ollama') ~= 1 then
    vim.notify("Ollama executable not found, can't verify model availability", vim.log.levels.WARN)
    return
  end

  -- Get current model
  local current_model = provider_config.model

  -- Get available models from ollama
  vim.system({ "ollama", "list" }, { text = true }, function(obj)
    if obj.code ~= 0 then
      vim.schedule(function()
        vim.notify("Failed to get Ollama models: " .. (obj.stderr or "unknown error"), vim.log.levels.WARN)
      end)
      return
    end

    local output = obj.stdout
    if not output or output == "" then
      vim.schedule(function()
        vim.notify("No models found in Ollama", vim.log.levels.WARN)
      end)
      return
    end

    -- Parse the output to extract model names
    local available_models = {}

    -- Skip the header line
    local lines = vim.split(output, "\n")
    for i = 2, #lines do
      local line = lines[i]
      if line ~= "" then
        -- Extract the first column (model name)
        local model_name = line:match("^(%S+)")
        if model_name then
          table.insert(available_models, model_name)
        end
      end
    end

    -- Check if the current model exists in available models
    local model_exists = false
    for _, model in ipairs(available_models) do
      if model == current_model then
        model_exists = true
        break
      end
    end

    -- If current model doesn't exist, use the first available model
    if not model_exists and #available_models > 0 then
      vim.schedule(function()
        local new_model = available_models[1]
        vim.notify("Model '" .. current_model .. "' not found. Using '" .. new_model .. "' instead.", vim.log.levels
          .INFO)
        provider_config.model = new_model

        -- Update state if it's the active provider
        if M.options.active_provider == "ollama" then
          require('nai.state').set_current_model(new_model)
        end
      end)
    end
  end)
end

return M
