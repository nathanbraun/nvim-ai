-- lua/nai/init.lua
-- Main module for nvim-ai plugin

local M = {}
local config = require('nai.config')
local api = require('nai.api')
local utils = require('nai.utils')

-- Setup function that should be called by the user
function M.setup(opts)
  config.setup(opts)

  -- Additional setup if needed
  return M
end

-- Complete text function
function M.complete(opts)
  -- Get the text range if a range was provided
  local text = ""
  if opts.range > 0 then
    text = utils.get_visual_selection()
  end

  -- Get the prompt from command arguments
  local prompt = opts.args or ""

  -- Combine text and prompt
  local full_prompt = prompt
  if text ~= "" then
    if prompt ~= "" then
      full_prompt = prompt .. ":\n" .. text
    else
      full_prompt = text
    end
  end

  -- Don't do anything if no prompt
  if full_prompt == "" then
    vim.notify("No prompt provided", vim.log.levels.WARN)
    return
  end

  -- Show a notification that we're working
  vim.notify("Generating AI completion...", vim.log.levels.INFO)

  -- Call the API and insert the result
  api.complete(full_prompt, function(result)
    if result then
      -- Insert the text at cursor position
      utils.insert_text_at_cursor(result)
      vim.notify("AI completion inserted", vim.log.levels.INFO)
    else
      vim.notify("Failed to get AI completion", vim.log.levels.ERROR)
    end
  end)
end

-- Edit text function
function M.edit(opts)
  -- Implementation similar to complete but replaces the selection
  -- Will implement in next iteration
  vim.notify("NAIEdit not yet implemented", vim.log.levels.INFO)
end

-- Chat function
function M.chat(opts)
  -- Implementation for chat
  -- Will implement in next iteration
  vim.notify("NAIChat not yet implemented", vim.log.levels.INFO)
end

-- Development helper to reload the plugin
function M.reload()
  -- Clear the module cache for the plugin
  for k in pairs(package.loaded) do
    if k:match("^nai") then
      package.loaded[k] = nil
    end
  end

  -- Reload the main module
  return require("nai")
end

-- Function to switch between providers
function M.switch_provider(provider)
  if provider ~= "openai" and provider ~= "openrouter" then
    vim.notify("Invalid provider. Use 'openai' or 'openrouter'", vim.log.levels.ERROR)
    return
  end

  require('nai.config').options.provider = provider
  require('nai.config').init_config() -- Make sure API key is loaded
  vim.notify("Switched to " .. provider .. " provider", vim.log.levels.INFO)
end

return M
