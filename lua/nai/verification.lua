-- lua/nai/verification.lua
local M = {}
local config = require('nai.config')

-- Namespace for verification indicators
M.namespace_id = vim.api.nvim_create_namespace('nvim_ai_verification')

-- Helper function for debug logging
function M.debug_log(message, data)
  local config = require('nai.config')

  if config.options.debug and config.options.debug.enabled then
    local debug_message = "VERIFICATION DEBUG: " .. message

    if data then
      if type(data) == "string" then
        debug_message = debug_message .. "\n" .. data
      else
        debug_message = debug_message .. "\n" .. vim.inspect(data)
      end
    end

    vim.notify(debug_message, vim.log.levels.DEBUG)
  end
end

-- Generate a hash for the given messages and response
function M.generate_hash(messages, response, context)
  -- Add a context parameter to identify which function is calling this
  context = context or "unknown"

  -- Start with an empty content string
  local content = ""

  -- Add all messages that were sent to the API, filtering out signature blocks
  for i, msg in ipairs(messages) do
    -- Skip if this is a signature block
    if msg.role == "assistant" and msg.content and msg.content:match("^<<< signature") then
      M.debug_log("Skipping signature block in message " .. i)
      goto continue
    end

    -- Normalize the content by trimming whitespace and removing blank lines
    local normalized_content = msg.content:gsub("^%s+", ""):gsub("%s+$", "")

    -- Remove any signature lines from the content
    normalized_content = normalized_content:gsub("\n<<< signature [0-9a-f]+", "")

    -- Remove all blank lines
    local lines = {}
    for line in normalized_content:gmatch("[^\r\n]+") do
      if line:match("%S") then -- Only keep lines with non-whitespace characters
        table.insert(lines, line)
      end
    end
    normalized_content = table.concat(lines, "\n")

    -- Add to the content string (no trailing newline after the last message)
    if i > 1 and content ~= "" then
      content = content .. "\n" -- Add a newline before each message except the first
    end

    content = content .. msg.role .. ":" .. normalized_content

    M.debug_log("Hash input message " .. i, {
      role = msg.role,
      content_preview = normalized_content:sub(1, 50) .. (normalized_content:len() > 50 and "..." or "")
    })

    ::continue::
  end

  -- Normalize the response by trimming whitespace and removing blank lines
  local normalized_response = response:gsub("^%s+", ""):gsub("%s+$", "")

  -- Remove any "A:" prefix that might appear in the buffer but not in the original
  normalized_response = normalized_response:gsub("^A:%s*", "")

  -- Remove any signature lines from the response
  normalized_response = normalized_response:gsub("\n<<< signature [0-9a-f]+", "")

  -- Remove all blank lines
  local response_lines = {}
  for line in normalized_response:gmatch("[^\r\n]+") do
    if line:match("%S") then -- Only keep lines with non-whitespace characters
      table.insert(response_lines, line)
    end
  end
  normalized_response = table.concat(response_lines, "\n")

  -- Add the normalized response with a single newline separator
  if content ~= "" then
    content = content .. "\n"
  end
  content = content .. "assistant:" .. normalized_response

  M.debug_log("Hash input response", normalized_response:sub(1, 50) .. (normalized_response:len() > 50 and "..." or ""))

  -- Create a more accessible directory for output files
  local output_dir = vim.fn.expand("~/.cache/nvim-ai/verification")
  vim.fn.mkdir(output_dir, "p") -- Create directory if it doesn't exist

  -- Generate a unique filename based on timestamp
  local timestamp = os.time()
  local output_file = output_dir .. "/hash_input_" .. context .. "_" .. timestamp .. ".txt"

  local file = io.open(output_file, "w")
  if file then
    file:write(content)
    file:close()

    M.debug_log("Wrote hash input to file", output_file)
    vim.notify("Wrote hash input to file: " .. output_file, vim.log.levels.INFO)
  else
    M.debug_log("Failed to write hash input to file", output_file)
    vim.notify("Failed to write hash input to file: " .. output_file, vim.log.levels.ERROR)
  end

  -- Generate SHA-256 hash
  local handle
  if file then
    handle = io.popen("sha256sum " .. vim.fn.shellescape(output_file))
  else
    -- If file writing failed, hash the content directly
    local temp_file = os.tmpname()
    local temp = io.open(temp_file, "w")
    temp:write(content)
    temp:close()
    handle = io.popen("sha256sum " .. vim.fn.shellescape(temp_file))
  end

  local hash_output = handle:read("*a")
  handle:close()

  -- Extract just the hash part (remove filename and whitespace)
  local hash = hash_output:match("^([0-9a-f]+)")
  M.debug_log("Generated hash", hash)

  return hash
end

-- Format a signature line to be added to the buffer
function M.format_signature(hash)
  return "<<< signature " .. hash
end

function M.add_signature_after_response(bufnr, insertion_row, messages, response)
  -- Only proceed if verification is enabled
  if not config.options.verification or not config.options.verification.enabled then
    return
  end

  M.debug_log("Adding signature", {
    buffer = bufnr,
    insertion_row = insertion_row,
    response_preview = response:sub(1, 50) .. (response:len() > 50 and "..." or "")
  })

  -- IMPORTANT: Do not add the response again, it's already in the buffer
  -- Just calculate the hash based on the messages and response

  -- Generate hash with context
  local hash = M.generate_hash(messages, response, "original_signature")

  -- Format signature line
  local signature_line = M.format_signature(hash)
  M.debug_log("Signature line", signature_line)

  -- Insert signature at the specified insertion row
  vim.api.nvim_buf_set_lines(bufnr, insertion_row, insertion_row, false, { "", signature_line })

  -- Apply highlighting if enabled
  if config.options.verification and config.options.verification.highlight_verified then
    vim.api.nvim_buf_add_highlight(bufnr, M.namespace_id, "DiagnosticOk", insertion_row, 0, -1)
  end

  return insertion_row + 2 -- Return the new position after insertion
end

-- Verify a single response
function M.verify_single_response(bufnr, response_start_line, signature_line)
  M.debug_log("Verifying response", {
    response_start_line = response_start_line,
    signature_line = signature_line
  })

  -- Get the current response from the buffer
  local lines = vim.api.nvim_buf_get_lines(bufnr, response_start_line + 1, signature_line, false)

  -- Clean up the response
  -- Remove any blank lines at the beginning
  while #lines > 0 and lines[1] == "" do
    table.remove(lines, 1)
  end

  -- Remove any blank lines at the end
  while #lines > 0 and lines[#lines] == "" do
    table.remove(lines, #lines)
  end

  -- Join the remaining lines
  local response = table.concat(lines, "\n")

  -- Remove any "A:" prefix that might appear
  response = response:gsub("^A:%s*", "")

  M.debug_log("Extracted response", response:sub(1, 100) .. (response:len() > 100 and "..." or ""))

  -- Get the stored hash from the signature line
  local signature = vim.api.nvim_buf_get_lines(bufnr, signature_line, signature_line + 1, false)[1]
  local stored_hash = signature:match("<<< signature ([0-9a-f]+)")

  M.debug_log("Stored hash", stored_hash)

  if not stored_hash then
    M.debug_log("Invalid signature format")
    return false, "Invalid signature format"
  end

  -- Get the messages that were sent to the API
  -- This is tricky because we need to reconstruct what was in the messages array
  -- when the API was called

  -- Get all buffer content up to the response
  local buffer_lines = vim.api.nvim_buf_get_lines(bufnr, 0, response_start_line, false)
  local buffer_content = table.concat(buffer_lines, "\n")

  -- Parse buffer to get messages
  local parser = require('nai.parser')
  local parsed_messages, _ = parser.parse_chat_buffer(buffer_content, bufnr)

  -- Log the parsed messages
  M.debug_log("Parsed messages count", #parsed_messages)
  for i, msg in ipairs(parsed_messages) do
    M.debug_log("Parsed message " .. i, {
      role = msg.role,
      content_preview = msg.content:sub(1, 50) .. (msg.content:len() > 50 and "..." or "")
    })
  end

  -- Filter out any signature blocks from parsed messages
  local filtered_messages = {}
  for _, msg in ipairs(parsed_messages) do
    -- Skip messages that are just signature blocks
    if msg.role == "assistant" and msg.content and msg.content:match("^<<< signature") then
      M.debug_log("Filtered out signature block from parsed messages")
    else
      table.insert(filtered_messages, msg)
    end
  end

  -- Generate expected hash with context
  local expected_hash = M.generate_hash(filtered_messages, response, "verification")
  M.debug_log("Generated hash", expected_hash)

  -- Compare hashes
  local is_verified = expected_hash == stored_hash
  M.debug_log("Verification result", is_verified and "VERIFIED" or "MODIFIED")

  if not is_verified then
    M.debug_log("Hash comparison", {
      expected = expected_hash,
      stored = stored_hash
    })
  end

  return is_verified, is_verified and "Response verified" or "Response has been modified"
end

-- Scan buffer and verify all responses
function M.verify_all_responses(bufnr)
  -- Get all lines in buffer
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Clear existing verification indicators
  vim.api.nvim_buf_clear_namespace(bufnr, M.namespace_id, 0, -1)

  -- Track verification status
  local all_verified = true
  local verification_count = 0

  -- Find assistant messages and their signatures
  local in_assistant = false
  local assistant_start = nil

  for i, line in ipairs(lines) do
    local row = i - 1 -- Convert to 0-indexed

    if line:match("^<<< assistant") then
      in_assistant = true
      assistant_start = row
    elseif in_assistant and line:match("^<<< signature") then
      -- Found a signature for an assistant message
      local is_verified, message = M.verify_single_response(bufnr, assistant_start, row)
      verification_count = verification_count + 1

      -- Add visual indicator
      local highlight_group = is_verified and "DiagnosticOk" or "DiagnosticError"
      local status_text = is_verified and "✓ Verified" or "✗ Modified"

      vim.api.nvim_buf_add_highlight(bufnr, M.namespace_id, highlight_group, row, 0, -1)
      vim.api.nvim_buf_set_extmark(bufnr, M.namespace_id, row, 0, {
        virt_text = { { status_text, highlight_group } },
        virt_text_pos = "eol",
      })

      if not is_verified then
        all_verified = false
      end

      in_assistant = false
    elseif in_assistant and (line:match("^>>>") or line:match("^<<<") and not line:match("^<<< signature")) then
      -- Found an assistant message without a signature
      vim.api.nvim_buf_add_highlight(bufnr, M.namespace_id, "DiagnosticWarn", assistant_start, 0, -1)
      vim.api.nvim_buf_set_extmark(bufnr, M.namespace_id, assistant_start, 0, {
        virt_text = { { "⚠ Not verified", "DiagnosticWarn" } },
        virt_text_pos = "eol",
      })

      all_verified = false
      in_assistant = false
    end
  end

  -- Show overall verification status
  if verification_count == 0 then
    vim.notify("No verifiable content found in buffer", vim.log.levels.INFO)
    return false
  else
    local status = all_verified and "✓ All responses verified" or "⚠ Some responses could not be verified"
    local level = all_verified and vim.log.levels.INFO or vim.log.levels.WARN
    vim.notify(status, level)
    return all_verified
  end
end

function M.verify_last_response(bufnr)
  -- Get all lines in buffer
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Clear existing verification indicators
  vim.api.nvim_buf_clear_namespace(bufnr, M.namespace_id, 0, -1)

  -- Find the last assistant message and its signature
  local last_assistant_start = nil
  local last_signature_line = nil
  local in_assistant = false
  local assistant_start = nil

  for i, line in ipairs(lines) do
    local row = i - 1 -- Convert to 0-indexed

    if line:match("^<<< assistant") then
      in_assistant = true
      assistant_start = row
    elseif in_assistant and line:match("^<<< signature") then
      -- Found a signature for an assistant message
      last_assistant_start = assistant_start
      last_signature_line = row
      in_assistant = false
    elseif in_assistant and (line:match("^>>>") or line:match("^<<<") and not line:match("^<<< signature")) then
      -- End of assistant message without signature
      in_assistant = false
    end
  end

  -- If we found a last assistant message with signature
  if last_assistant_start and last_signature_line then
    local is_verified, message = M.verify_single_response(bufnr, last_assistant_start, last_signature_line)

    -- Add visual indicator
    local highlight_group = is_verified and "DiagnosticOk" or "DiagnosticError"
    local status_text = is_verified and "✓ Verified" or "✗ Modified"

    vim.api.nvim_buf_add_highlight(bufnr, M.namespace_id, highlight_group, last_signature_line, 0, -1)
    vim.api.nvim_buf_set_extmark(bufnr, M.namespace_id, last_signature_line, 0, {
      virt_text = { { status_text, highlight_group } },
      virt_text_pos = "eol",
    })

    -- Show verification status
    local status = is_verified and "✓ Last response verified" or "⚠ Last response could not be verified"
    local level = is_verified and vim.log.levels.INFO or vim.log.levels.WARN
    vim.notify(status, level)

    return is_verified
  else
    vim.notify("No verifiable content found in buffer", vim.log.levels.INFO)
    return false
  end
end

return M
