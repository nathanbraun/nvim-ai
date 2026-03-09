-- lua/nai/health.lua
-- Health check for :checkhealth nai

local M = {}

function M.check()
  vim.health.start("nvim-ai")

  -- Check required dependencies
  if vim.fn.executable("curl") == 1 then
    vim.health.ok("curl found")
  else
    vim.health.error("curl not found", { "Install curl for API requests to work" })
  end

  -- Check optional dependencies
  if vim.fn.executable("html2text") == 1 then
    vim.health.ok("html2text found (optional)")
  else
    vim.health.info("html2text not found (optional, used for web content formatting)")
  end

  -- Check configuration
  local ok, config = pcall(require, "nai.config")
  if not ok then
    vim.health.error("Failed to load nai.config", { "Check your plugin installation" })
    return
  end

  local provider = config.options.active_provider
  local model = config.options.active_model
  vim.health.ok("Active provider: " .. provider)
  vim.health.ok("Active model: " .. (model or "not set"))

  -- Check API keys
  local providers_to_check = { "openai", "openrouter", "google", "ollama" }
  local no_key_providers = { openclaw = true, claude_proxy = true }

  for _, p in ipairs(providers_to_check) do
    local key = config.get_api_key(p)
    if key then
      vim.health.ok(p .. ": API key configured")
    else
      if p == provider then
        vim.health.error(p .. ": API key NOT configured (active provider)", {
          "Run :NAISetKey " .. p,
          "Or set " .. p:upper() .. "_API_KEY environment variable",
        })
      else
        vim.health.info(p .. ": API key not configured")
      end
    end
  end

  -- Check for local providers that don't need keys
  if no_key_providers[provider] then
    vim.health.ok(provider .. ": no API key required (local provider)")
  end

  -- Check credentials file
  local path = require("nai.utils.path")
  local cred_path = path.expand(config.options.credentials.file_path)
  if vim.fn.filereadable(cred_path) == 1 then
    vim.health.ok("Credentials file: " .. cred_path)
  else
    vim.health.info("Credentials file not found: " .. cred_path)
  end

  -- Check chat directory
  local chat_dir = vim.fn.expand(config.options.chat_files.directory)
  if vim.fn.isdirectory(chat_dir) == 1 then
    vim.health.ok("Chat directory: " .. chat_dir)
  else
    vim.health.info("Chat directory does not exist yet: " .. chat_dir .. " (will be created on first chat)")
  end
end

return M
