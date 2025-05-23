local M = {}

function M.fetch_url(url)
  -- Check for required tools
  local html2text_available = vim.fn.executable('html2text') == 1
  local lynx_available = vim.fn.executable('lynx') == 1

  if not (html2text_available or lynx_available) then
    return "Error: Required tools not found. Please install html2text or lynx."
  end

  -- First fetch the URL content with curl with a timeout and size limit
  local curl_cmd = 'curl -sL --max-time 10 --max-filesize 1000000 "' .. url .. '"'

  -- Use pcall to catch any errors
  local success, html_content = pcall(function()
    return vim.fn.system(curl_cmd)
  end)

  if not success or vim.v.shell_error ~= 0 then
    return "Error fetching URL: " .. url .. "\nDetails: " .. (html_content or "Unknown error")
  end

  -- Limit the size of the content to process
  if #html_content > 1000000 then -- 1MB limit
    html_content = string.sub(html_content, 1, 1000000) .. "\n\n[Content truncated due to large size]"
  end

  -- Convert to markdown with better error handling
  local md_content = ""
  success = pcall(function()
    if html2text_available then
      -- Use a temporary file approach for large content
      local temp_file = os.tmpname()
      local file = io.open(temp_file, "w")
      if file then
        file:write(html_content)
        file:close()
        md_content = vim.fn.system('html2text ' .. temp_file)
        os.remove(temp_file)
      else
        md_content = "Error: Failed to create temporary file"
      end
    elseif lynx_available then
      -- Create a temporary file for the HTML content
      local temp_file = os.tmpname()
      local file = io.open(temp_file, "w")
      file:write(html_content)
      file:close()

      -- Convert using lynx
      md_content = vim.fn.system('lynx -dump -nolist ' .. temp_file)

      -- Clean up
      os.remove(temp_file)
    end
  end)

  if not success then
    return "Error converting HTML to text for URL: " .. url
  end

  -- Limit the size of the final content
  if #md_content > 100000 then -- 100KB limit for display
    md_content = string.sub(md_content, 1, 100000) .. "\n\n[Content truncated due to large size]"
  end

  return "==> Web (Simple): " .. url .. " <==\n\n" .. md_content
end

function M.process_web_block(lines)
  local result = {}
  local urls = {}
  local additional_text = {}
  local processing_urls = true

  for _, line in ipairs(lines) do
    if processing_urls and line:match("^%s*$") then
      -- Empty line indicates end of URLs
      processing_urls = false
    elseif processing_urls and line ~= "" then
      -- Process as URL
      table.insert(urls, line)
    else
      -- Process as additional text
      table.insert(additional_text, line)
    end
  end

  -- Fetch and add content for each URL
  for _, url in ipairs(urls) do
    table.insert(result, M.fetch_url(url:gsub("%s+", "")))
  end

  -- Add additional text if any
  if #additional_text > 0 then
    table.insert(result, "")
    table.insert(result, table.concat(additional_text, "\n"))
  end

  return table.concat(result, "\n\n")
end

-- Use Dumpling AI to scrape a webpage
function M.fetch_url_with_dumpling(url)
  local config = require('nai.config')
  local api_key = config.get_dumpling_api_key()

  if not api_key then
    return "Error: Dumpling API key not found. Please add it to your credentials file."
  end

  local dumpling_config = config.options.tools.web.dumpling
  local data = {
    url = url,
    format = dumpling_config.format or "markdown",
    cleaned = dumpling_config.cleaned or true,
    renderJs = dumpling_config.render_js or true,
  }

  local json_data = vim.fn.json_encode(data)
  local auth_header = "Authorization: Bearer " .. api_key

  -- Show a notification that we're fetching
  vim.notify("Fetching URL with Dumpling: " .. url, vim.log.levels.INFO)

  -- Make the request to Dumpling API
  local response = vim.fn.system({
    "curl",
    "-s",
    "-X", "POST",
    dumpling_config.endpoint,
    "-H", "Content-Type: application/json",
    "-H", auth_header,
    "-d", json_data
  })

  if vim.v.shell_error ~= 0 then
    return "Error fetching URL with Dumpling: " .. url
  end

  local success, result = pcall(vim.fn.json_decode, response)
  if not success then
    return "Error parsing Dumpling response for URL: " .. url
  end

  if result.error then
    return "Dumpling API Error: " .. (result.error.message or "Unknown error")
  end

  -- Format the response with title and content
  local title = result.title or "No title"
  local content = result.content or "No content"

  vim.notify("Successfully fetched URL with Dumpling", vim.log.levels.INFO)

  return string.format("==> Web (Dumpling): %s - %s <==\n\n%s", url, title, content)
end

return M
