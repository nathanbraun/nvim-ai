-- lua/nai/config.lua
-- Configuration for the plugin

local M = {}

-- Default configuration
M.defaults = {
  provider = "openrouter", -- "openai" or "openrouter"
  openai = {
    api_key = nil,
    model = "gpt-4o",
    temperature = 0.7,
    max_tokens = 1000,
    token_file_path = "~/.config/openai.token",
    endpoint = "https://api.openai.com/v1/chat/completions",
  },
  openrouter = {
    api_key = nil,
    model = "google/gemini-2.0-flash-001",
    temperature = 0.7,
    max_tokens = 1000,
    token_file_path = "~/.config/open-router.token",
    endpoint = "https://openrouter.ai/api/v1/chat/completions",
  },
  ui = {
    chat_position = "split", -- "split", "vsplit", or "tab"
  },
}

-- Current configuration (will be populated by setup)
M.options = vim.deepcopy(M.defaults) -- Initialize with defaults immediately

-- Helper function to read API key from file
local function read_api_key_from_file(file_path)
  -- Expand ~ to home directory
  file_path = vim.fn.expand(file_path)

  -- Check if file exists
  if vim.fn.filereadable(file_path) == 0 then
    return nil
  end

  -- Read the file
  local lines = vim.fn.readfile(file_path)
  if #lines == 0 then
    return nil
  end

  -- Return the first line, trimmed
  return vim.fn.trim(lines[1])
end

-- Auto-initialize with defaults and try to load API key
local function init_config()
  -- Get the active provider settings
  local provider = M.options.provider
  local provider_config = M.options[provider]

  -- Try to load API key in this order:
  -- 1. From user provided config
  -- 2. From environment variable (provider specific)
  -- 3. From token file
  if not provider_config.api_key then
    local env_var = provider:upper() .. "_API_KEY"
    provider_config.api_key = vim.env[env_var]
  end

  if not provider_config.api_key then
    provider_config.api_key = read_api_key_from_file(provider_config.token_file_path)
  end
end

-- Setup function to merge user config with defaults
function M.setup(opts)
  -- Merge user options with defaults
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})

  -- Try to load API key
  init_config()

  return M.options
end

-- Function to get current provider config
function M.get_provider_config()
  return M.options[M.options.provider]
end

-- Initialize with defaults right away
init_config()

return M
