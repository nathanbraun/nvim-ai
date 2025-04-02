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

M.active_request = nil

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

  -- Cancel any existing request
  if M.active_request then
    if vim.system and M.active_request.terminate then
      M.active_request:terminate()
    elseif not vim.system and M.active_request.close then
      M.active_request:close()
    end
    M.active_request = nil
  end

  -- Remember the original buffer and position
  local destination_buffer = vim.api.nvim_get_current_buf()
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local start_line = cursor_pos[1] - 1 -- Convert to 0-indexed
  local start_col = cursor_pos[2]

  -- Show a notification that we're working
  local notification_id = vim.notify("Generating AI completion...", vim.log.levels.INFO, {
    title = "nvim-ai",
    replace = notification_id
  })

  -- Use the simple non-streaming version temporarily
  M.active_request = api.complete_simple(
    full_prompt,

    function(final_text)
      -- Check if the buffer still exists
      if not vim.api.nvim_buf_is_valid(destination_buffer) then
        notification_id = vim.notify("Target buffer no longer exists", vim.log.levels.WARN, {
          title = "nvim-ai",
          replace = notification_id
        })
        return
      end

      -- Insert the text
      vim.api.nvim_buf_set_text(
        destination_buffer,
        start_line, start_col,
        start_line, start_col,
        vim.split(final_text, "\n")
      )

      notification_id = vim.notify("AI completion inserted", vim.log.levels.INFO, {
        title = "nvim-ai",
        replace = notification_id
      })
      M.active_request = nil
    end,

    function(err_msg)
      notification_id = vim.notify(err_msg, vim.log.levels.ERROR, {
        title = "nvim-ai",
        replace = notification_id
      })
      M.active_request = nil
    end
  )
end

-- Add a function to cancel the current request
function M.cancel()
  if M.active_request then
    if vim.system and M.active_request.terminate then
      M.active_request:terminate()
      vim.notify("AI completion cancelled", vim.log.levels.INFO)
    elseif not vim.system and M.active_request.close then
      M.active_request:close()
      vim.notify("AI completion cancelled", vim.log.levels.INFO)
    end
    M.active_request = nil
  end
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
