-- lua/nai/fileutils/youtube.lua
local M = {}
local block_processor = require('nai.fileutils.block_processor')

-- Get Dumpling API key (reusing from scrape module)
function M.get_api_key()
  local config = require('nai.config')
  return config.get_dumpling_api_key()
end

-- Fetch transcript from YouTube URL
function M.fetch_transcript(video_url, options, callback, on_error)
  local api_key = M.get_api_key()
  local config = require('nai.config')

  if not api_key then
    if on_error then
      vim.schedule(function()
        on_error(
          "Dumpling API key not found. Please set DUMPLING_API_KEY environment variable or add it to your credentials file.")
      end)
    end
    return
  end

  -- Merge with default options from config
  local dumpling_config = config.options.tools.dumpling or {}

  -- Default options from config or hardcoded defaults
  local default_options = {
    include_timestamps = dumpling_config.include_timestamps ~= false, -- Default to true
    timestamps_to_combine = dumpling_config.timestamps_to_combine or 5,
    preferred_language = dumpling_config.preferred_language or "en"
  }

  -- Merge passed options with defaults
  options = vim.tbl_deep_extend("force", default_options, options or {})

  -- Prepare request data
  local data = {
    videoUrl = video_url,
    includeTimestamps = options.include_timestamps,
    timestampsToCombine = options.timestamps_to_combine,
    preferredLanguage = options.preferred_language
  }

  local json_data = vim.json.encode(data)

  -- Use the base endpoint plus the specific endpoint for YouTube transcripts
  local base_endpoint = dumpling_config.base_endpoint or "https://app.dumplingai.com/api/v1/"
  local endpoint = base_endpoint .. "get-youtube-transcript"

  -- Remove trailing slash if present in base_endpoint
  endpoint = endpoint:gsub("//", "/"):gsub(":/", "://")

  local auth_header = "Authorization: Bearer " .. api_key

  -- Show a notification that we're fetching
  vim.schedule(function()
    vim.notify("Fetching YouTube transcript: " .. video_url, vim.log.levels.INFO)
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
          on_error("Dumpling API Error: " .. (result.error or "Unknown error"))
        end)
      end
      return
    end

    -- Extract transcript and language
    local transcript = result.transcript or "No transcript available"
    local language = result.language or "unknown"

    -- Schedule notification
    vim.schedule(function()
      vim.notify("Successfully fetched YouTube transcript", vim.log.levels.INFO)
    end)

    if callback then
      vim.schedule(function()
        callback(transcript, language, video_url)
      end)
    end
  end)

  return handle
end

-- Function to handle expanding YouTube blocks in naichat files
function M.expand_youtube_block(buffer_id, start_line, end_line)
  return block_processor.expand_async_block({
    buffer_id = buffer_id,
    start_line = start_line,
    end_line = end_line,
    block_type = "youtube",
    progress_marker = ">>> transcribing",
    completed_marker = ">>> transcript",
    error_marker = ">>> youtube-error",

    -- Default options
    default_options = {
      include_timestamps = true,
      timestamps_to_combine = 5,
      preferred_language = "en"
    },

    -- Spinner message
    spinner_message = function(url, options)
      return "Fetching transcript from " .. url
    end,

    -- Validate URL
    validate_target = function(url)
      return url:match("youtube%.com") or url:match("youtu%.be")
    end,

    -- Execute the transcript fetch
    execute = function(url, options, callback, on_error)
      M.fetch_transcript(url, options,
        function(transcript, language, video_url)
          callback({
            transcript = transcript,
            language = language,
            url = video_url,
            options = options
          })
        end,
        on_error
      )
    end,

    -- Format the result
    format_result = function(result, url, options)
      local lines = block_processor.format_completed_header(
        ">>> transcript",
        url,
        nil, -- We'll add options manually for better control
        nil  -- Use default timestamp
      )

      -- Add options as comments if they differ from defaults
      if not result.options.include_timestamps then
        table.insert(lines, "-- timestamps: false")
      end
      if result.options.timestamps_to_combine ~= 5 then
        table.insert(lines, "-- combine: " .. result.options.timestamps_to_combine)
      end
      if result.options.preferred_language ~= "en" then
        table.insert(lines, "-- language: " .. result.options.preferred_language)
      end

      -- Add blank line if we added options
      if lines[#lines]:match("^%-%-") then
        table.insert(lines, "")
      end

      -- Add header
      table.insert(lines, "## YouTube Transcript (" .. result.language .. ")")
      table.insert(lines, "_Source: " .. result.url .. "_")
      table.insert(lines, "")

      -- Add transcript lines
      local transcript_lines = vim.split(result.transcript, "\n ")
      for _, line in ipairs(transcript_lines) do
        table.insert(lines, line)
      end

      return lines
    end,
  })
end

-- Check if there are unexpanded YouTube blocks in the buffer
function M.has_unexpanded_youtube_blocks(buffer_id)
  local lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)
  local constants = require('nai.constants')

  -- Track if we're inside an ignore block
  local in_ignored_block = false

  for i, line in ipairs(lines) do
    if line:match("^" .. vim.pesc(constants.MARKERS.IGNORE or "```ignore") .. "$") then
      in_ignored_block = true
    elseif in_ignored_block and line:match("^" .. vim.pesc(constants.MARKERS.IGNORE_END or "```") .. "$") then
      in_ignored_block = false
    elseif vim.trim(line) == ">>> youtube" then
      return true
    end
  end

  return false
end

-- Process the YouTube block for API requests (used by parser)
function M.process_youtube_block(lines)
  -- For API requests, we'll process this synchronously
  -- This is similar to the web block processing

  local result = {}
  local video_urls = {}
  local additional_text = {}
  local options = {
    include_timestamps = true,
    timestamps_to_combine = 5,
    preferred_language = "en"
  }

  local processing_urls = true
  local processing_options = false

  for i, line in ipairs(lines) do
    if line:match("^%s*--") then
      -- This is a comment/option line
      processing_options = true

      -- Try to parse options
      local option_name, option_value = line:match("^%s*--%s*(%w+)%s*:%s*(.+)$")
      if option_name and option_value then
        if option_name == "timestamps" then
          options.include_timestamps = option_value:lower() == "true"
        elseif option_name == "combine" then
          options.timestamps_to_combine = tonumber(option_value) or 5
        elseif option_name == "language" then
          options.preferred_language = option_value
        end
      end
    elseif processing_urls and line:match("^%s*$") and not processing_options then
      -- Empty line indicates end of URLs (if not in options section)
      processing_urls = false
      processing_options = false
    elseif processing_urls and line ~= "" and not line:match("^%s*--") then
      -- Process as URL
      table.insert(video_urls, line:gsub("%s+", ""))
    else
      -- Process as additional text
      table.insert(additional_text, line)
    end
  end

  -- Make synchronous requests for each URL
  for _, url in ipairs(video_urls) do
    -- This is inefficient for the API call but necessary for the synchronous operation
    local transcript_fetched = false
    local transcript_content = "Error: Could not fetch transcript"
    local transcript_language = "unknown"

    -- Create a temporary script to make a synchronous call
    local path = require('nai.utils.path')
    local temp_file = path.tmpname()
    local dumpling_config = require('nai.config').options.tools.dumpling or {}
    local base_endpoint = dumpling_config.base_endpoint or "https://app.dumplingai.com/api/v1/"
    local endpoint = base_endpoint .. "get-youtube-transcript"
    endpoint = endpoint:gsub("//", "/"):gsub(":/", "://")

    local script = string.format([[
  curl -s -X POST "%s" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer %s" \
  -d '{"videoUrl":"%s","includeTimestamps":%s,"timestampsToCombine":%d,"preferredLanguage":"%s"}'
]],
      endpoint,
      M.get_api_key(),
      url,
      tostring(options.include_timestamps):lower(),
      options.timestamps_to_combine,
      options.preferred_language)

    -- Write the script to a temporary file
    local f = io.open(temp_file, "w")
    f:write(script)
    f:close()

    -- Execute the script
    local handle = io.popen("bash " .. temp_file)
    if handle then
      local response = handle:read("*a")
      handle:close()
      os.remove(temp_file)

      -- Parse the response
      local success, result = pcall(vim.json.decode, response)
      if success and result and result.transcript then
        transcript_content = result.transcript
        transcript_language = result.language or "unknown"
        transcript_fetched = true
      end
    else
      os.remove(temp_file)
    end

    -- Format the response
    if transcript_fetched then
      table.insert(result, string.format("==> YouTube Transcript (%s) <==\n Video: \n%s",
        transcript_language, url, transcript_content))
    else
      table.insert(result,
        string.format("==> YouTube Transcript Error <==\n Video: %s \n Failed to fetch transcript", url))
    end
  end

  -- Add additional text if any
  if #additional_text > 0 then
    table.insert(result, "")
    table.insert(result, table.concat(additional_text, "\n "))
  end

  return table.concat(result, "\n ")
end

-- Format a youtube block for the buffer
function M.format_youtube_block(url)
  return "\n >>> youtube " .. url
end

-- Register YouTube processor with the expander
local function register_with_expander()
  local expander = require('nai.blocks.expander')

  expander.register_processor('youtube', {
    marker = function(line)
      return vim.trim(line) == ">>> youtube"
    end,

    has_unexpanded = M.has_unexpanded_youtube_blocks,

    expand = M.expand_youtube_block,

    -- No active requests tracking for YouTube (handled internally by block_processor)
    has_active_requests = nil,
  })
end

-- Auto-register when module is loaded
register_with_expander()

return M
