-- lua/nai/fileutils/youtube.lua
local M = {}

-- Get Dumpling API key (reusing from scrape module)
function M.get_api_key()
  local config = require('nai.config')
  return config.get_dumpling_api_key()
end

-- Fetch transcript from YouTube URL
function M.fetch_transcript(video_url, options, callback, on_error)
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

  -- Prepare request data
  local data = {
    videoUrl = video_url,
    includeTimestamps = options.include_timestamps ~= false, -- Default to true
    timestampsToCombine = options.timestamps_to_combine or 5,
    preferredLanguage = options.preferred_language or "en"
  }

  local json_data = vim.json.encode(data)
  local endpoint = "https://app.dumplingai.com/api/v1/get-youtube-transcript"
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

-- Process the YouTube block
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
    local temp_file = os.tmpname()
    local script = string.format([[
      curl -s -X POST "https://app.dumplingai.com/api/v1/get-youtube-transcript" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer %s" \
      -d '{"videoUrl":"%s","includeTimestamps":%s,"timestampsToCombine":%d,"preferredLanguage":"%s"}'
    ]],
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
      table.insert(result, string.format("==> YouTube Transcript (%s) <==\nVideo: %s\n\n%s",
        transcript_language, url, transcript_content))
    else
      table.insert(result,
        string.format("==> YouTube Transcript Error <==\nVideo: %s\n\nFailed to fetch transcript", url))
    end
  end

  -- Add additional text if any
  if #additional_text > 0 then
    table.insert(result, "")
    table.insert(result, table.concat(additional_text, "\n"))
  end

  return table.concat(result, "\n\n")
end

-- Function to handle expanding YouTube blocks in naichat files
function M.expand_youtube_block(buffer_id, start_line, end_line)
  -- Get the YouTube block lines
  local lines = vim.api.nvim_buf_get_lines(buffer_id, start_line, end_line, false)

  -- Skip the first line which contains the youtube marker
  local url = nil
  local options = {
    include_timestamps = true,
    timestamps_to_combine = 5,
    preferred_language = "en"
  }

  -- Look for a URL in the block
  for i = 2, #lines do
    local line = lines[i]
    -- Look for anything that resembles a URL
    if line:match("https?://[%w%p]+") then
      url = line:match("https?://[%w%p]+")
      break
    elseif line:match("^%s*--") then
      -- Parse options
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
    end
  end

  -- If still no URL found, check for youtube.com or youtu.be in any form
  if not url then
    for i = 2, #lines do
      local line = lines[i]
      if line:match("youtube%.com") or line:match("youtu%.be") then
        url = line:gsub("%s+", "")
        break
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
        ">>> youtube-error",
        "❌ Error: No YouTube URL provided",
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
    { ">>> transcribing" }
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
    { "⏳ Fetching transcript..." }
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
    local status_text = animation_frames[current_frame] .. " Fetching transcript from " .. url

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

  -- Fetch the YouTube transcript asynchronously
  M.fetch_transcript(url, options,
    function(transcript, language, video_url)
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

      -- Format the transcript into lines
      local transcript_lines = vim.split(transcript, "\n")

      -- Build the result - changing youtube to transcript
      local result_lines = {
        ">>> transcript [" .. os.date("%Y-%m-%d %H:%M:%S") .. "]",
        url
      }

      -- Add options as comments if they were changed from defaults
      if not options.include_timestamps then
        table.insert(result_lines, "-- timestamps: false")
      end
      if options.timestamps_to_combine ~= 5 then
        table.insert(result_lines, "-- combine: " .. options.timestamps_to_combine)
      end
      if options.preferred_language ~= "en" then
        table.insert(result_lines, "-- language: " .. options.preferred_language)
      end

      -- Add a blank line and header
      table.insert(result_lines, "")
      table.insert(result_lines, "## YouTube Transcript (" .. language .. ")")
      table.insert(result_lines, "_Source: " .. url .. "_")
      table.insert(result_lines, "")

      -- Add the transcript lines
      for _, line in ipairs(transcript_lines) do
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

      -- Notify completion
      vim.notify("YouTube transcript fetched successfully", vim.log.levels.INFO)
    end,
    function(error_msg)
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
        ">>> youtube-error",
        url,
        "",
        "❌ Error fetching YouTube transcript: " .. url,
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
        vim.notify("Error fetching YouTube transcript: " .. error_msg, vim.log.levels.ERROR)
      end)
    end
  )

  -- Return the changed number of lines in the placeholder
  return 3 -- The marker line + url + spinner
end

-- Check if there are unexpanded YouTube blocks in the buffer
function M.has_unexpanded_youtube_blocks(buffer_id)
  local lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)

  for _, line in ipairs(lines) do
    -- Only match exact ">>> youtube" - not "transcribing" or "transcript"
    if line == ">>> youtube" then
      return true
    end
  end

  return false
end

-- Format a youtube block for the buffer
function M.format_youtube_block(url)
  return "\n>>> youtube\n\n" .. url
end

return M
