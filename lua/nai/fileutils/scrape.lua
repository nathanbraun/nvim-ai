-- lua/nai/fileutils/scrape.lua
local M = {}
local config = require('nai.config')
local utils = require('nai.utils')

-- Active scrape requests
M.active_requests = {}

-- Create a namespace for our extmarks
M.namespace_id = vim.api.nvim_create_namespace('nai_scrape_indicators')

-- Get Dumpling API key
function M.get_api_key()
  -- Try environment variable first
  local key = vim.env["DUMPLING_API_KEY"]
  if key and key ~= "" then
    return key
  end

  -- Try credentials from nvim-ai config
  local key = config.get_dumpling_api_key()
  if key then
    return key
  end

  -- If not found, notify user
  return nil
end

-- Process the URL content through Dumpling API
function M.fetch_url(url, callback, on_error)
  local api_key = M.get_api_key()
  local config = require('nai.config')

  if config.options.debug and config.options.debug.enabled then
    vim.notify("DEBUG: fetch_url called for: " .. url, vim.log.levels.DEBUG)
    vim.notify("DEBUG: Dumpling API key found: " .. (api_key ~= nil and "YES" or "NO"), vim.log.levels.DEBUG)
  end

  if not api_key then
    if on_error then
      vim.schedule(function()
        on_error(
          "Error: Dumpling API key not found. Please set DUMPLING_API_KEY environment variable or add it to your credentials file.")
      end)
    end
    return
  end

  -- Get complete dumpling configuration
  local dumpling_config = config.options.tools.dumpling or {}

  -- Use the base endpoint plus the specific endpoint for scraping
  local base_endpoint = dumpling_config.base_endpoint or "https://app.dumplingai.com/api/v1/"
  local endpoint = base_endpoint .. "scrape"

  -- Remove trailing slash if present in base_endpoint
  endpoint = endpoint:gsub("//", "/"):gsub(":/", "://")

  if config.options.debug and config.options.debug.enabled then
    vim.notify("DEBUG: Using Dumpling endpoint: " .. endpoint, vim.log.levels.DEBUG)
  end

  local data = {
    url = url,
    format = dumpling_config.format or "markdown",
    cleaned = dumpling_config.cleaned ~= false,    -- Default to true
    renderJs = dumpling_config.render_js ~= false, -- Default to true
  }

  local json_data = vim.json.encode(data)
  local auth_header = "Authorization: Bearer " .. api_key

  -- Show a notification that we're fetching
  vim.schedule(function()
    vim.notify("Fetching URL with Dumpling: " .. url, vim.log.levels.INFO)
  end)

  -- Make the request to Dumpling API
  local handle = vim.system({
    "curl",
    "-s",
    "-X", "POST",
    endpoint,
    "-H", "Content-Type: application/json",
    "-H", auth_header,
    "-d", json_data
  }, { text = true }, function(obj)
    if obj.code ~= 0 then
      if on_error then
        vim.schedule(function()
          on_error("Error: curl request failed with code " .. obj.code)
        end)
      end
      return
    end

    local response = obj.stdout
    if not response or response == "" then
      if on_error then
        vim.schedule(function()
          on_error("Error: Empty response from API")
        end)
      end
      return
    end

    local success, result = pcall(vim.json.decode, response)
    if not success then
      if on_error then
        vim.schedule(function()
          on_error("Error parsing Dumpling response: " .. result)
        end)
      end
      return
    end

    if result.error then
      if on_error then
        vim.schedule(function()
          on_error("Dumpling API Error: " .. (result.error.message or "Unknown error"))
        end)
      end
      return
    end

    -- Format the response with title and content
    local title = result.title or "No title"
    local content = result.content or "No content"

    -- Truncate if too large
    local max_content_length = dumpling_config.max_content_length or 100000
    if #content > max_content_length then
      content = string.sub(content, 1, max_content_length) ..
          "\n\n[Content truncated due to large size]"
    end

    -- Schedule notification
    vim.schedule(function()
      vim.notify("Successfully fetched URL with Dumpling", vim.log.levels.INFO)
    end)

    if callback then
      vim.schedule(function()
        callback(title, content, url)
      end)
    end
  end)

  return handle
end

-- Function to handle expanding scrape blocks in naichat files
function M.expand_scrape_block(buffer_id, start_line, end_line)
  local config = require('nai.config')

  -- Debug logging
  if config.options.debug and config.options.debug.enabled then
    vim.notify("DEBUG: expand_scrape_block called for lines " .. start_line .. " to " .. end_line, vim.log.levels.DEBUG)
  end

  -- Get the scrape block lines
  local lines = vim.api.nvim_buf_get_lines(buffer_id, start_line, end_line, false)

  -- Debug print lines
  if config.options.debug and config.options.debug.enabled then
    vim.notify("DEBUG: Scrape block content: " .. vim.inspect(lines), vim.log.levels.DEBUG)
  end

  -- Skip the first line which contains the scrape marker
  local url = nil
  for i = 2, #lines do
    local line = lines[i]
    if line:match("%S") then -- First non-empty line
      url = line:gsub("%s+", "")
      break
    end
  end

  if not url or url == "" then
    -- No URL found, insert error message
    vim.api.nvim_buf_set_lines(
      buffer_id,
      start_line, end_line,
      false,
      {
        ">>> scrape-error",
        "❌ Error: No URL provided for scraping",
        ""
      }
    )
    return (end_line - start_line)
  end

  if config.options.debug and config.options.debug.enabled then
    vim.notify("DEBUG: Found URL in scrape block: " .. url, vim.log.levels.DEBUG)
  end

  -- Change marker to show it's in progress
  vim.api.nvim_buf_set_lines(
    buffer_id,
    start_line,
    start_line + 1,
    false,
    { ">>> scraping" }
  )

  -- Create a spinner animation at the end of the block
  local indicator = {
    buffer_id = buffer_id,
    start_row = start_line,
    end_row = end_line,
    spinner_row = start_line + 2, -- Add spinner after URL
    timer = nil
  }

  -- Insert spinner line
  vim.api.nvim_buf_set_lines(
    buffer_id,
    start_line + 2,
    start_line + 2,
    false,
    { "⏳ Fetching content..." }
  )

  -- Start the animation
  local animation_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
  local current_frame = 1

  indicator.timer = vim.loop.new_timer()
  indicator.timer:start(0, 120, vim.schedule_wrap(function()
    -- Check if buffer still exists
    if not vim.api.nvim_buf_is_valid(buffer_id) then
      if indicator.timer then
        indicator.timer:stop()
        indicator.timer:close()
        indicator.timer = nil
      end
      return
    end

    -- Update the spinner animation
    local status_text = animation_frames[current_frame] .. " Fetching content from " .. url

    -- Update the text in the buffer
    vim.api.nvim_buf_set_lines(
      buffer_id,
      indicator.spinner_row,
      indicator.spinner_row + 1,
      false,
      { status_text }
    )

    -- Move to the next animation frame
    current_frame = (current_frame % #animation_frames) + 1
  end))

  -- Track this request
  local request = {
    buffer_id = buffer_id,
    indicator = indicator,
    start_line = start_line,
    end_line = end_line,
    url = url
  }

  -- Store in active requests
  if not M.active_requests then
    M.active_requests = {}
  end
  table.insert(M.active_requests, request)

  -- Fetch the URL asynchronously
  M.fetch_url(url,
    function(title, content, url)
      -- Remove request from active requests
      for i, req in ipairs(M.active_requests) do
        if req == request then
          table.remove(M.active_requests, i)
          break
        end
      end

      -- Stop the timer
      if indicator.timer then
        indicator.timer:stop()
        indicator.timer:close()
        indicator.timer = nil
      end

      -- Check if buffer is still valid
      if not vim.api.nvim_buf_is_valid(buffer_id) then
        return
      end

      -- Format the result block
      local content_lines = vim.split(content, "\n")

      -- Build the result - changing scrape to scraped
      local result_lines = {
        ">>> scraped [" .. os.date("%Y-%m-%d %H:%M:%S") .. "]",
        url,
        "",
        "## " .. title,
        "_Source: " .. url .. "_",
        ""
      }

      -- Add the content lines
      for _, line in ipairs(content_lines) do
        table.insert(result_lines, line)
      end

      -- Replace the placeholder with the result
      vim.api.nvim_buf_set_lines(
        buffer_id,
        indicator.start_row,
        math.max(indicator.end_row, indicator.start_row + 3), -- Ensure we get all lines with spinner
        false,
        result_lines
      )
    end,
    function(error_msg)
      -- Remove request from active requests
      for i, req in ipairs(M.active_requests) do
        if req == request then
          table.remove(M.active_requests, i)
          break
        end
      end

      -- Stop the timer
      if indicator.timer then
        indicator.timer:stop()
        indicator.timer:close()
        indicator.timer = nil
      end

      -- Check if buffer is still valid
      if not vim.api.nvim_buf_is_valid(buffer_id) then
        return
      end

      -- Format the error
      local error_lines = {
        ">>> scrape-error",
        url,
        "",
        "❌ Error fetching URL: " .. url,
        error_msg,
        ""
      }

      -- Replace the placeholder with the error
      vim.api.nvim_buf_set_lines(
        buffer_id,
        indicator.start_row,
        math.max(indicator.end_row, indicator.start_row + 3),
        false,
        error_lines
      )

      -- Show error notification
      vim.schedule(function()
        vim.notify("Error scraping URL: " .. error_msg, vim.log.levels.ERROR)
      end)
    end
  )

  -- Return the changed number of lines in the placeholder
  return 3 -- The marker line + url + spinner
end

-- Expand all scrape blocks in a buffer
function M.expand_scrape_blocks_in_buffer(buffer_id)
  -- Guard against invalid buffer
  if not vim.api.nvim_buf_is_valid(buffer_id) then
    return
  end

  -- Get all buffer content
  local lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)
  local line_offset = 0

  -- Find and expand scrape blocks
  for i, line in ipairs(lines) do
    if line:match("^>>> scrape$") then
      -- This is a scrape block
      local block_start = i - 1 + line_offset

      -- Find the end of the scrape block (next >>> or <<<)
      local block_end = #lines
      for j = i + 1, #lines do
        if lines[j]:match("^>>>") or lines[j]:match("^<<<") then
          block_end = j - 1 + line_offset
          break
        end
      end

      -- Expand the scrape block directly in the buffer
      local new_line_count = M.expand_scrape_block(buffer_id, block_start, block_end + 1)

      -- Adjust line offset for any additional lines added
      line_offset = line_offset + (new_line_count - (block_end - block_start + 1))

      -- Re-fetch buffer lines since they've changed
      lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)
    end
  end
end

-- Check if there are unexpanded scrape blocks in the buffer
function M.has_unexpanded_scrape_blocks(buffer_id)
  local lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)
  local constants = require('nai.constants')

  -- Track if we're inside an ignore block
  local in_ignored_block = false

  for i, line in ipairs(lines) do
    if line:match("^" .. vim.pesc(constants.MARKERS.IGNORE or "```ignore") .. "$") then
      in_ignored_block = true
    elseif in_ignored_block and line:match("^" .. vim.pesc(constants.MARKERS.IGNORE_END or "```") .. "$") then
      in_ignored_block = false
    elseif line == ">>> scrape" then
      return true
    end
  end

  return false
end

-- Check if there are active scrape requests
function M.has_active_requests()
  return M.active_requests and #M.active_requests > 0
end

return M
