-- lua/nai/fileutils/crawl.lua
local M = {}
local config = require('nai.config')
local block_processor = require('nai.fileutils.block_processor')

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
          "Dumpling API key not found. Please set DUMPLING_API_KEY environment variable or add it to your credentials file.")
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
  return block_processor.expand_async_block({
    buffer_id = buffer_id,
    start_line = start_line,
    end_line = end_line,
    block_type = "crawl",
    progress_marker = ">>> crawling",
    completed_marker = ">>> crawled",
    error_marker = ">>> crawl-error",
    
    -- Default options
    default_options = {
      limit = 5,
      depth = 2,
      format = "markdown"
    },
    
    -- Spinner message
    spinner_message = function(url, options)
      return string.format("Crawling %s (limit: %d, depth: %d)", 
        url, options.limit or 5, options.depth or 2)
    end,
    
    -- Execute the crawl
    execute = function(url, options, callback, on_error)
      M.crawl_website(url, options,
        function(result, url)
          callback({
            result = result,
            url = url,
            options = options
          })
        end,
        on_error
      )
    end,
    
    -- Format the result
    format_result = function(data, url, options)
      local result = data.result
      local lines = block_processor.format_completed_header(
        ">>> crawled",
        url,
        {
          limit = options.limit,
          depth = options.depth,
          format = options.format
        },
        nil -- Use default timestamp
      )
      
      -- Add summary header
      table.insert(lines, string.format("## Crawled %d pages from %s", 
        result.pages or 0, url))
      table.insert(lines, "")
      
      -- Add each crawled page
      if result.results and #result.results > 0 then
        for i, page in ipairs(result.results) do
          table.insert(lines, "### Page " .. i .. ": " .. page.url)
          table.insert(lines, "")

          -- Add the content with proper indentation
          local content_lines = vim.split(page.content or "", "\n ")
          for _, line in ipairs(content_lines) do
            table.insert(lines, line)
          end

          table.insert(lines, "")
          table.insert(lines, "---")
          table.insert(lines, "")
        end
      else
        table.insert(lines, "No pages were crawled.")
      end
      
      return lines
    end,
  })
end

-- Check if there are unexpanded crawl blocks in the buffer
function M.has_unexpanded_crawl_blocks(buffer_id)
  local lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)
  local constants = require('nai.constants')

  -- Track if we're inside an ignore block
  local in_ignored_block = false

  for _, line in ipairs(lines) do
    if line:match("^" .. vim.pesc(constants.MARKERS.IGNORE or "```ignore") .. "$") then
      in_ignored_block = true
    elseif in_ignored_block and line:match("^" .. vim.pesc(constants.MARKERS.IGNORE_END or "```") .. "$") then
      in_ignored_block = false
    elseif vim.trim(line) == ">>> crawl" then
      return true
    end
  end

  return false
end

-- Check if there are active crawl requests
function M.has_active_requests()
  -- Check block_processor for any crawl-type requests
  for request_id, request in pairs(block_processor.active_requests) do
    if request.block_type == "crawl" then
      return true
    end
  end
  return false
end

-- Process crawl block for API requests
function M.process_crawl_block(lines)
  -- For API requests, just use the text that's already in the buffer
  -- since we've already expanded the crawl
  return table.concat(lines, "\n")
end

-- Register crawl processor with the expander
local function register_with_expander()
  local expander = require('nai.blocks.expander')

  expander.register_processor('crawl', {
    marker = function(line)
      return vim.trim(line) == ">>> crawl"
    end,

    has_unexpanded = M.has_unexpanded_crawl_blocks,

    expand = M.expand_crawl_block,

    -- Check for active async requests
    has_active_requests = M.has_active_requests,
  })
end

-- Auto-register when module is loaded
register_with_expander()


return M
