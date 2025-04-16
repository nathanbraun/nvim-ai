-- lua/nai/fileutils/crawl.lua
local M = {}
local config = require('nai.config')

-- Active crawl requests
M.active_requests = {}

-- Function to get the Dumpling API key (reusing from scrape module)
function M.get_api_key()
  return require('nai.config').get_dumpling_api_key()
end

-- Crawl a website using Dumpling API
function M.crawl_website(url, options, callback, on_error)
  local api_key = M.get_api_key()

  if not api_key then
    if on_error then
      vim.schedule(function()
        on_error(
          "Error: Dumpling API key not found. Please set DUMPLING_API_KEY environment variable or add it to your credentials file.")
      end)
    end
    return
  end

  -- Get dumpling configuration
  local dumpling_config = config.options.tools.dumpling or {}

  -- Merge with default options
  local default_options = {
    limit = 5,
    depth = 2,
    format = "markdown"
  }

  -- Merge passed options with defaults
  options = vim.tbl_deep_extend("force", default_options, options or {})

  -- Prepare request data
  local data = {
    url = url,
    limit = options.limit,
    depth = options.depth,
    format = options.format
  }

  local json_data = vim.json.encode(data)

  -- Use the base endpoint plus the specific endpoint for crawling
  local base_endpoint = dumpling_config.base_endpoint or "https://app.dumplingai.com/api/v1/"
  local endpoint = base_endpoint .. "crawl"

  -- Remove trailing slash if present in base_endpoint
  endpoint = endpoint:gsub("//", "/"):gsub(":/", "://")

  local auth_header = "Authorization: Bearer " .. api_key

  -- Show a notification that we're crawling
  vim.schedule(function()
    vim.notify("Crawling website: " .. url .. " (up to " .. options.limit .. " pages)", vim.log.levels.INFO)
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

    -- Schedule notification
    vim.schedule(function()
      vim.notify(string.format("Successfully crawled %s pages from %s", result.pages or 0, url), vim.log.levels.INFO)
    end)

    if callback then
      vim.schedule(function()
        callback(result, url)
      end)
    end
  end)

  return handle
end

-- Function to handle expanding crawl blocks in buffer
function M.expand_crawl_block(buffer_id, start_line, end_line)
  -- Get the crawl block lines
  local lines = vim.api.nvim_buf_get_lines(buffer_id, start_line, end_line, false)

  -- Skip the first line which contains the crawl marker
  local url = nil
  local options = {
    limit = 5,
    depth = 2,
    format = "markdown"
  }

  -- Parse the block content
  for i = 2, #lines do
    local line = lines[i]
    if not url and line:match("https?://[%w%p]+") then
      -- First non-empty line with URL is the target URL
      url = line:match("https?://[%w%p]+")
    elseif line:match("^%s*--") then
      -- Parse options
      local option_name, option_value = line:match("^%s*--%s*(%w+)%s*:%s*(.+)$")
      if option_name and option_value then
        if option_name == "limit" then
          options.limit = tonumber(option_value) or 5
        elseif option_name == "depth" then
          options.depth = tonumber(option_value) or 2
        elseif option_name == "format" then
          options.format = option_value
        end
      end
    end
  end

  if not url or url == "" then
    -- No URL found, insert error message
    vim.api.nvim_buf_set_lines(
      buffer_id,
      start_line, end_line,
      false,
      {
        ">>> crawl-error",
        "❌ Error: No URL provided for crawling",
        ""
      }
    )
    return (end_line - start_line)
  end

  -- Change marker to show it's in progress
  vim.api.nvim_buf_set_lines(
    buffer_id,
    start_line,
    start_line + 1,
    false,
    { ">>> crawling" }
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
    { "⏳ Crawling website..." }
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
    local status_text = animation_frames[current_frame] ..
        string.format(" Crawling %s (limit: %d, depth: %d)", url, options.limit, options.depth)

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

  -- Crawl the website asynchronously
  M.crawl_website(url, options,
    function(result, url)
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

      -- Format the results
      local result_lines = {
        ">>> crawled [" .. os.date("%Y-%m-%d %H:%M:%S") .. "]",
        url,
        string.format("-- limit: %d", options.limit),
        string.format("-- depth: %d", options.depth),
        string.format("-- format: %s", options.format),
        "",
        string.format("## Crawled %d pages from %s", result.pages or 0, url),
        ""
      }

      -- Add each crawled page
      if result.results and #result.results > 0 then
        for i, page in ipairs(result.results) do
          table.insert(result_lines, "### Page " .. i .. ": " .. page.url)
          table.insert(result_lines, "")

          -- Add the content with proper indentation
          local content_lines = vim.split(page.content or "", "\n")
          for _, line in ipairs(content_lines) do
            table.insert(result_lines, line)
          end

          table.insert(result_lines, "")
          table.insert(result_lines, "---")
          table.insert(result_lines, "")
        end
      else
        table.insert(result_lines, "No pages were crawled.")
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
        ">>> crawl-error",
        url,
        "",
        "❌ Error crawling website: " .. url,
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
        vim.notify("Error crawling website: " .. error_msg, vim.log.levels.ERROR)
      end)
    end
  )

  -- Return the changed number of lines in the placeholder
  return 3 -- The marker line + url + spinner
end

-- Check if there are unexpanded crawl blocks in the buffer
function M.has_unexpanded_crawl_blocks(buffer_id)
  local lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)

  for _, line in ipairs(lines) do
    -- Only match exact ">>> crawl" - not "crawling" or "crawled"
    if vim.trim(line) == ">>> crawl" then
      return true
    end
  end

  return false
end

-- Expand all crawl blocks in a buffer
function M.expand_crawl_blocks_in_buffer(buffer_id)
  -- Guard against invalid buffer
  if not vim.api.nvim_buf_is_valid(buffer_id) then
    return
  end

  -- Get all buffer content
  local lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)
  local line_offset = 0

  -- Find and expand crawl blocks
  for i, line in ipairs(lines) do
    if line:match("^>>> crawl$") then
      -- This is a crawl block
      local block_start = i - 1 + line_offset

      -- Find the end of the crawl block (next >>> or <<<)
      local block_end = #lines
      for j = i + 1, #lines do
        if lines[j]:match("^>>>") or lines[j]:match("^<<<") then
          block_end = j - 1 + line_offset
          break
        end
      end

      -- Expand the crawl block directly in the buffer
      local new_line_count = M.expand_crawl_block(buffer_id, block_start, block_end + 1)

      -- Adjust line offset for any additional lines added
      line_offset = line_offset + (new_line_count - (block_end - block_start + 1))

      -- Re-fetch buffer lines since they've changed
      lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)
    end
  end
end

-- Check if there are active crawl requests
function M.has_active_requests()
  return M.active_requests and #M.active_requests > 0
end

-- Process crawl block for API requests
function M.process_crawl_block(lines)
  -- For API requests, just use the text that's already in the buffer
  -- since we've already expanded the crawl
  return table.concat(lines, "\n")
end

return M
