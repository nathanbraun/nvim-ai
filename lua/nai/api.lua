-- lua/nai/api.lua
-- API interactions for AI providers

local M = {}
local config = require('nai.config')

-- Safe notification function for callbacks
local function safe_notify(msg, level)
  vim.schedule(function()
    vim.notify(msg, level)
  end)
end

-- Simple AI completion function using curl
function M.complete(prompt, callback)
  -- Get the active provider config
  local provider_config = config.get_provider_config()

  -- Ensure we have an API key
  local api_key = provider_config.api_key
  if not api_key then
    safe_notify("API key not found for " .. config.options.provider, vim.log.levels.ERROR)
    callback(nil)
    return
  end

  -- Prepare the data
  local data = {
    model = provider_config.model,
    messages = {
      { role = "user", content = prompt }
    },
    temperature = provider_config.temperature,
    max_tokens = provider_config.max_tokens,
  }

  -- Convert to JSON
  local json_data = vim.json.encode(data)

  -- Debug to a file instead of using vim.notify
  local debug_log = ""
  local function log_debug(msg)
    debug_log = debug_log .. os.date("%Y-%m-%d %H:%M:%S") .. " - " .. msg .. "\n"
  end

  -- Log completion of the debug
  local function finish_debug()
    if debug_log ~= "" then
      -- Write debug log to a file
      local log_file = io.open(vim.fn.stdpath("cache") .. "/nvim-ai-debug.log", "a")
      if log_file then
        log_file:write(debug_log)
        log_file:close()
      end
    end
  end

  -- Determine endpoint URL
  local endpoint_url = provider_config.endpoint

  log_debug("Using provider: " .. config.options.provider)
  log_debug("Starting API request with model: " .. provider_config.model)
  log_debug("Sending request to endpoint: " .. endpoint_url)
  log_debug("API key present: " .. tostring(api_key ~= nil))

  -- Check if vim.system is available (Neovim 0.10+)
  if vim.system then
    -- Set up auth header based on provider
    local auth_header = "Authorization: Bearer " .. api_key

    -- Use vim.system for Neovim 0.10+
    vim.system({
      "curl",
      "-s",
      "-X", "POST",
      endpoint_url,
      "-H", "Content-Type: application/json",
      "-H", auth_header,
      "-d", json_data
    }, { text = true }, function(obj)
      if obj.code ~= 0 then
        log_debug("API request failed with code " .. obj.code)
        finish_debug()
        vim.schedule(function()
          vim.notify("API request failed with code " .. obj.code, vim.log.levels.ERROR)
          callback(nil)
        end)
        return
      end

      local response_text = obj.stdout
      if not response_text or response_text == "" then
        log_debug("Empty response from API")
        finish_debug()
        vim.schedule(function()
          vim.notify("Empty response from API", vim.log.levels.ERROR)
          callback(nil)
        end)
        return
      end

      -- Log raw response (limited length to avoid huge logs)
      local preview = response_text
      if #preview > 500 then
        preview = preview:sub(1, 497) .. "..."
      end
      log_debug("Raw API response preview: " .. preview)

      -- Parse the JSON response
      local success, parsed = pcall(vim.json.decode, response_text)

      if not success then
        log_debug("Failed to parse API response: " .. parsed)
        finish_debug()
        vim.schedule(function()
          vim.notify("Failed to parse API response", vim.log.levels.ERROR)
          callback(nil)
        end)
        return
      end

      -- Log structure checks
      log_debug("Response has choices: " .. tostring(parsed.choices ~= nil))
      if parsed.choices then
        log_debug("Number of choices: " .. #parsed.choices)
      end

      -- Check for error response
      if parsed.error then
        log_debug("API Error: " .. vim.inspect(parsed.error))
        finish_debug()
        vim.schedule(function()
          vim.notify("API Error: " .. (parsed.error.message or "Unknown error"), vim.log.levels.ERROR)
          callback(nil)
        end)
        return
      end

      -- Extract the response text with careful checks
      if parsed and parsed.choices and #parsed.choices > 0 then
        local first_choice = parsed.choices[1]

        log_debug("First choice: " .. vim.inspect(first_choice))

        if first_choice.message and first_choice.message.content then
          local result = first_choice.message.content
          log_debug("Successfully extracted content")
          finish_debug()
          vim.schedule(function()
            callback(result)
          end)
        else
          log_debug("Message or content missing in API response")
          finish_debug()
          vim.schedule(function()
            vim.notify("Message or content missing in API response", vim.log.levels.ERROR)
            callback(nil)
          end)
        end
      else
        log_debug("No choices in API response")
        finish_debug()
        vim.schedule(function()
          vim.notify("No choices in API response", vim.log.levels.ERROR)
          callback(nil)
        end)
      end
    end)
  else
    -- Fallback for older Neovim versions
    -- Write data to a temporary file
    local temp_input_file = os.tmpname()
    local f = io.open(temp_input_file, "w")
    f:write(json_data)
    f:close()

    -- Temporary file for the response
    local temp_output_file = os.tmpname()

    -- Set up auth header based on provider
    local auth_header = "Authorization: Bearer " .. api_key

    -- Build the curl command
    local cmd = string.format(
      "curl -s -X POST %s " ..
      "-H 'Content-Type: application/json' " ..
      "-H '%s' " ..
      "-d @%s " ..
      "> %s",
      endpoint_url,
      auth_header,
      temp_input_file,
      temp_output_file
    )

    -- Execute the command
    local handle = io.popen(cmd)
    handle:close() -- Wait for the command to complete

    -- Read the response
    local response = {}
    local file = io.open(temp_output_file, "r")
    if file then
      for line in file:lines() do
        table.insert(response, line)
      end
      file:close()
    end

    -- Clean up temp files
    os.remove(temp_input_file)
    os.remove(temp_output_file)

    if #response == 0 then
      safe_notify("Empty response from API", vim.log.levels.ERROR)
      callback(nil)
      return
    end

    -- Parse the JSON response
    local response_text = table.concat(response, "\n")
    local success, parsed = pcall(vim.json.decode, response_text)

    if not success then
      safe_notify("Failed to parse API response: " .. parsed, vim.log.levels.ERROR)
      callback(nil)
      return
    end

    -- Check for error response
    if parsed.error then
      safe_notify("API Error: " .. (parsed.error.message or "Unknown error"), vim.log.levels.ERROR)
      callback(nil)
      return
    end

    -- Extract the response text with careful checks
    if parsed and parsed.choices and #parsed.choices > 0 then
      local first_choice = parsed.choices[1]

      if first_choice.message and first_choice.message.content then
        local result = first_choice.message.content
        callback(result)
      else
        safe_notify("Message or content missing in API response", vim.log.levels.ERROR)
        callback(nil)
      end
    else
      safe_notify("No choices in API response", vim.log.levels.ERROR)
      callback(nil)
    end
  end
end

return M
