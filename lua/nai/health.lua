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

  -- Claude proxy checks
  if provider == "claude_proxy" then
    vim.health.start("nvim-ai: claude_proxy")

    if vim.fn.executable("python3") == 1 then
      vim.health.ok("python3 found")
    else
      vim.health.error("python3 not found", { "Install Python 3 to run the claude-proxy server" })
    end

    if vim.fn.executable("claude") == 1 then
      vim.health.ok("claude CLI found")
    else
      vim.health.error("claude CLI not found", {
        "Install the Claude CLI: https://docs.anthropic.com/en/docs/claude-cli",
        "Make sure it is authenticated (run: claude login)",
      })
    end

    -- Find the proxy script
    local script_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h:h")
    local script_path = script_dir .. "/scripts/claude-proxy.py"
    if vim.fn.filereadable(script_path) == 1 then
      vim.health.ok("Proxy script: " .. script_path)
    else
      vim.health.warn("Proxy script not found at: " .. script_path)
    end

    -- Check if the proxy is currently running
    local endpoint = config.options.providers.claude_proxy
      and config.options.providers.claude_proxy.endpoint
      or "http://127.0.0.1:5757/v1/chat/completions"
    local health_url = endpoint:gsub("/v1/chat/completions$", "/health")
    local result = vim.fn.system("curl -s -o /dev/null -w '%{http_code}' --connect-timeout 2 " .. vim.fn.shellescape(health_url))
    if vim.trim(result) == "200" then
      vim.health.ok("Proxy server is running at " .. health_url)
    else
      vim.health.warn("Proxy server is not running", {
        "Start it with: python3 " .. script_path,
      })
    end
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
