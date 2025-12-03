-- lua/nai/fileutils/scrape.lua
local M = {}
local config = require('nai.config')
local block_processor = require('nai.fileutils.block_processor')

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
          "Dumpling API key not found. Please set DUMPLING_API_KEY environment variable or add it to your credentials file.")
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
          on_error("curl request failed with code " .. obj.code)
        end)
      end
      return
    end

    local response = obj.stdout
    if not response or response == "" then
      if on_error then
        vim.schedule(function()
          on_error("Empty response from API")
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
          "\n[Content truncated due to large size]"
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
  return block_processor.expand_async_block({
    buffer_id = buffer_id,
    start_line = start_line,
    end_line = end_line,
    block_type = "scrape",
    progress_marker = ">>> scraping",
    completed_marker = ">>> scraped",
    error_marker = ">>> scrape-error",
    
    -- Spinner message
    spinner_message = function(url, options)
      return "Fetching content from " .. url
    end,
    
    -- Execute the scrape
    execute = function(url, options, callback, on_error)
      M.fetch_url(url, 
        function(title, content, url)
          callback({ title = title, content = content, url = url })
        end,
        on_error
      )
    end,
    
    -- Format the result
    format_result = function(result, url, options)
      local lines = block_processor.format_completed_header(
        ">>> scraped",
        url,
        nil, -- No options to display for scrape
        nil  -- Use default timestamp
      )
      
      -- Add title and content
      table.insert(lines, "## " .. result.title)
      table.insert(lines, "_Source: " .. result.url .. "_")
      table.insert(lines, "")
      
      -- Add content lines
      local content_lines = vim.split(result.content, "\n")
      for _, line in ipairs(content_lines) do
        table.insert(lines, line)
      end
      
      return lines
    end,
  })
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
  -- Check block_processor for any scrape-type requests
  for request_id, request in pairs(block_processor.active_requests) do
    if request.block_type == "scrape" then
      return true
    end
  end
  return false
end

-- Process scrape block for API requests (used by parser)
function M.process_scrape_block(text_buffer)
  -- In API requesting mode, we want to reference the content, not the command
  local in_content_section = false
  local content_lines = {}

  for _, line in ipairs(text_buffer) do
    if line:match("^<<< content%s+%[") then
      in_content_section = true
    elseif in_content_section then
      table.insert(content_lines, line)
    end
  end

  if #content_lines > 0 then
    -- If we have content, use that
    return table.concat(content_lines, "\n"):gsub("^%s*(.-)%s*$", "%1") -- trim
  else
    -- Otherwise, use the raw text
    return table.concat(text_buffer, "\n"):gsub("^%s*(.-)%s*$", "%1") -- trim
  end
end

-- Register scrape processor with the expander
local function register_with_expander()
  local expander = require('nai.blocks.expander')
  
  expander.register_processor('scrape', {
    marker = function(line)
      return line == ">>> scrape"
    end,
    
    has_unexpanded = M.has_unexpanded_scrape_blocks,
    
    expand = M.expand_scrape_block,
    
    -- Check for active async requests
    has_active_requests = M.has_active_requests,
  })
end

-- Auto-register when module is loaded
register_with_expander()

return M
