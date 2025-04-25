-- lua/nai/verification.lua
local M = {}
local config = require('nai.config')

M.verified_regions = {} -- Buffer ID -> { { start_line, end_line, signature_line }, ... }

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

function M.get_verification_key()
  local pepper_file = vim.fn.stdpath('data') .. '/nvim-ai/verification.key'

  -- Check if the key file exists
  if vim.fn.filereadable(pepper_file) == 1 then
    -- Read the existing key
    local lines = vim.fn.readfile(pepper_file)
    if #lines > 0 then
      return lines[1]
    end
  end

  -- Generate a new key if none exists
  math.randomseed(os.time())
  local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  local new_pepper = ""
  for i = 1, 32 do
    local rand = math.random(#chars)
    new_pepper = new_pepper .. chars:sub(rand, rand)
  end

  -- Ensure directory exists
  vim.fn.mkdir(vim.fn.fnamemodify(pepper_file, ':h'), 'p')

  -- Write the new key
  vim.fn.writefile({ new_pepper }, pepper_file)

  -- Set permissions to be readable only by the owner on Unix
  if vim.fn.has('unix') == 1 then
    vim.fn.system("chmod 600 " .. vim.fn.shellescape(pepper_file))
  end

  return new_pepper
end

-- Generate a hash for the given messages and response
function M.generate_hash(messages, response, context, algorithm_version)
  -- Default to v1 if no algorithm specified
  algorithm_version = algorithm_version or "v1"

  -- Add a context parameter to identify which function is calling this
  context = context or "unknown"
  local constants = require('nai.constants')

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

    -- If this is a system message, remove the auto-title instruction
    if msg.role == "system" then
      normalized_content = normalized_content:gsub(vim.pesc(constants.AUTO_TITLE_INSTRUCTION), "")
    end

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

  -- Get the verification key (pepper)
  local verification_key = M.get_verification_key()

  -- Add the pepper to the content before hashing
  content = content .. "\n" .. verification_key

  -- Hash with the specified algorithm
  local hash = M.hash_with_algorithm(content, algorithm_version)

  return hash, algorithm_version
end

function M.hash_with_algorithm(content, algorithm_version)
  algorithm_version = algorithm_version or "v1"

  if algorithm_version == "v1" then
    -- Use the existing SHA-256 approach
    local temp_file = os.tmpname()
    local temp = io.open(temp_file, "w")
    temp:write(content)
    temp:close()

    local handle = io.popen("sha256sum " .. vim.fn.shellescape(temp_file))
    local hash_output = handle:read("*a")
    handle:close()

    -- Clean up the temporary file
    os.remove(temp_file)

    -- Extract just the hash part (remove filename and whitespace)
    local hash = hash_output:match("^([0-9a-f]+)")
    return hash
  elseif algorithm_version == "v2" then
    -- Example of a different algorithm (SHA-512)
    local temp_file = os.tmpname()
    local temp = io.open(temp_file, "w")
    temp:write(content)
    temp:close()

    local handle = io.popen("sha512sum " .. vim.fn.shellescape(temp_file))
    local hash_output = handle:read("*a")
    handle:close()

    -- Clean up the temporary file
    os.remove(temp_file)

    -- Extract just the hash part and take first 64 chars
    local hash = hash_output:match("^([0-9a-f]+)")
    return hash:sub(1, 64) -- Trim to same length as v1 for consistency
  else
    -- Unknown algorithm version, fall back to v1
    M.debug_log("Unknown algorithm version: " .. algorithm_version .. ", falling back to v1")
    return M.hash_with_algorithm(content, "v1")
  end
end

-- Format a signature line to be added to the buffer
function M.format_signature(hash, algorithm_version)
  algorithm_version = algorithm_version or "v1" -- Default to v1
  return "<<< signature " .. algorithm_version .. ":" .. hash
end

function M.add_signature_after_response(bufnr, insertion_row, messages, response, force_signature)
  -- Only proceed if verification is enabled or forced
  if not (force_signature or (config.options.verification and config.options.verification.enabled)) then
    return insertion_row
  end

  M.debug_log("Adding signature", {
    buffer = bufnr,
    insertion_row = insertion_row
  })

  -- Clean up messages by removing auto-title instruction from system messages
  local constants = require('nai.constants')
  local clean_messages = vim.deepcopy(messages)
  for _, msg in ipairs(clean_messages) do
    if msg.role == "system" and msg.content then
      msg.content = msg.content:gsub(vim.pesc(constants.AUTO_TITLE_INSTRUCTION), "")
    end
  end

  -- Generate hash with context
  local hash, algorithm_version = M.generate_hash(clean_messages, response, "original_signature", "v1")

  -- Format signature line with algorithm version
  local signature_line = M.format_signature(hash, algorithm_version)

  -- Check if there's already a signature line at or after the insertion point
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local has_existing_signature = false

  -- Look for existing signature within the next few lines
  for i = insertion_row, math.min(insertion_row + 3, line_count - 1) do
    local line_content = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1]
    if line_content and line_content:match("^<<< signature") then
      -- Found existing signature, update it
      vim.api.nvim_buf_set_lines(bufnr, i, i + 1, false, { signature_line })

      -- Apply highlighting
      vim.api.nvim_buf_clear_namespace(bufnr, M.namespace_id, i, i + 1)
      if config.options.verification and config.options.verification.highlight_verified then
        vim.api.nvim_buf_add_highlight(bufnr, M.namespace_id, "DiagnosticOk", i, 0, -1)
      end

      has_existing_signature = true
      return i + 1 -- Return position after the signature
    end
  end

  -- If no existing signature found, insert a new one
  if not has_existing_signature then
    -- Insert signature at the specified insertion row
    vim.api.nvim_buf_set_lines(bufnr, insertion_row, insertion_row, false, { "", signature_line })

    -- Apply highlighting if enabled
    if config.options.verification and config.options.verification.highlight_verified then
      -- Use naichatSignature for the signature line itself
      vim.api.nvim_buf_add_highlight(bufnr, M.namespace_id, "naichatSignature", insertion_row + 1, 0, -1)
    end

    return insertion_row + 2 -- Return the new position after insertion
  end
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
  local algorithm_version, stored_hash = signature:match("<<< signature ([^:]+):([0-9a-f]+)")

  M.debug_log("Stored hash", stored_hash)

  if not algorithm_version or not stored_hash then
    -- Try the old format as fallback
    stored_hash = signature:match("<<< signature ([0-9a-f]+)")
    algorithm_version = "v1" -- Assume v1 for old format

    if not stored_hash then
      M.debug_log("Invalid signature format")
      return false, "Invalid signature format"
    end
  end

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

  -- Process aliases using the same function used for API requests
  local processed_messages, _ = parser.process_alias_messages(parsed_messages)

  M.debug_log("After alias processing, message count", #processed_messages)
  for i, msg in ipairs(processed_messages) do
    M.debug_log("Processed message " .. i, {
      role = msg.role,
      content_preview = msg.content:sub(1, 50) .. (msg.content:len() > 50 and "..." or "")
    })
  end

  -- Filter out any signature blocks from processed messages
  local filtered_messages = {}
  for _, msg in ipairs(processed_messages) do
    -- Skip messages that are just signature blocks
    if msg.role == "assistant" and msg.content and msg.content:match("^<<< signature") then
      M.debug_log("Filtered out signature block from processed messages")
    else
      table.insert(filtered_messages, msg)
    end
  end

  -- Generate expected hash with context and the same algorithm version
  local expected_hash = M.generate_hash(filtered_messages, response, "verification", algorithm_version)
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

  if is_verified then
    -- Initialize the verified regions table for this buffer if needed
    if not M.verified_regions[bufnr] then
      M.verified_regions[bufnr] = {}
    end

    -- Check if we already have this region tracked
    local existing_index = nil
    for i, region in ipairs(M.verified_regions[bufnr]) do
      if region.signature_line == signature_line then
        existing_index = i
        break
      end
    end

    -- Update or add the region
    local region_data = {
      start_line = response_start_line,
      end_line = signature_line - 1,
      signature_line = signature_line
    }

    if existing_index then
      M.verified_regions[bufnr][existing_index] = region_data
    else
      table.insert(M.verified_regions[bufnr], region_data)
    end

    -- Set up change detection
    M.attach_change_detection(bufnr)
  end

  return is_verified, is_verified and "Response verified" or "Response has been modified"
end

function M.verify_last_response(bufnr)
  -- Get all lines in buffer
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Clear existing verification indicators
  vim.api.nvim_buf_clear_namespace(bufnr, M.namespace_id, 0, -1)

  -- Initialize verified regions for this buffer (but don't use signature_line yet)
  M.verified_regions[bufnr] = {}

  -- Reset the attachment flag so we can reattach
  if vim.b[bufnr] then
    vim.b[bufnr].nai_verification_attached = nil
  end

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

    -- Add visual indicator - use naichatSignature for the line itself
    vim.api.nvim_buf_add_highlight(bufnr, M.namespace_id, "naichatSignature", last_signature_line, 0, -1)

    -- Add the appropriate verification indicator based on verification status
    local highlight_group = is_verified and "DiagnosticOk" or "DiagnosticError"
    local status_text = is_verified and "✓ Verified" or "✗ Modified"

    vim.api.nvim_buf_set_extmark(bufnr, M.namespace_id, last_signature_line, 0, {
      virt_text = { { status_text, highlight_group } },
      virt_text_pos = "eol",
    })

    -- Track this region for change detection regardless of verification status
    if not M.verified_regions[bufnr] then
      M.verified_regions[bufnr] = {}
    end

    -- Add or update the region
    local region_data = {
      start_line = last_assistant_start,
      end_line = last_signature_line - 1,
      signature_line = last_signature_line,
      is_verified = is_verified -- Store verification status
    }

    -- Check if we already have this region tracked
    local existing_index = nil
    for i, region in ipairs(M.verified_regions[bufnr]) do
      if region.signature_line == last_signature_line then
        existing_index = i
        break
      end
    end

    if existing_index then
      M.verified_regions[bufnr][existing_index] = region_data
    else
      table.insert(M.verified_regions[bufnr], region_data)
    end

    -- Set up change detection
    M.attach_change_detection(bufnr)

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

function M.attach_change_detection(bufnr)
  -- Skip if buffer isn't valid anymore
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Always detach first if already attached (to ensure we're starting fresh)
  if vim.b[bufnr] and vim.b[bufnr].nai_verification_attached then
    -- We can't directly detach, but we can reset our state
    vim.b[bufnr].nai_verification_attached = nil
  end

  -- Set buffer variable to track attachment
  vim.api.nvim_buf_set_var(bufnr, "nai_verification_attached", true)

  -- Attach to buffer changes with simplified logic
  vim.api.nvim_buf_attach(bufnr, false, {
    on_lines = function(_, buf, _, first_line, last_line_old, last_line_new, _)
      -- Skip if no verified regions
      if not M.verified_regions[buf] then
        return true
      end

      -- Check if lines were added or removed
      if last_line_old ~= last_line_new then
        -- Clear all verification indicators
        vim.api.nvim_buf_clear_namespace(buf, M.namespace_id, 0, -1)
        -- Clear all tracking
        M.verified_regions[buf] = {}
        return true
      end

      -- For in-place edits, check each region
      for i = #M.verified_regions[buf], 1, -1 do -- Iterate in reverse to safely remove items
        local region = M.verified_regions[buf][i]

        -- If the change is at or before the end of this region
        -- (any change before or within the region could affect verification)
        if first_line <= region.end_line then
          -- Clear the verification indicator
          M.clear_verification_indicator(buf, region.signature_line)
          -- Remove this region from tracking
          table.remove(M.verified_regions[buf], i)
        end
      end

      return true
    end,
    on_detach = function()
      M.verified_regions[bufnr] = nil
    end,
  })

  -- Set up cleanup on buffer unload
  local augroup = vim.api.nvim_create_augroup('NaiVerificationCleanup' .. bufnr, { clear = true })
  vim.api.nvim_create_autocmd("BufUnload", {
    group = augroup,
    buffer = bufnr,
    callback = function()
      M.verified_regions[bufnr] = nil
    end
  })
end

function M.clear_verification_indicator(bufnr, signature_line)
  -- Skip if buffer isn't valid anymore
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Check if the line still exists in the buffer
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if signature_line >= line_count then
    return
  end

  -- Get the current line content to check if it's still a signature line
  local line_content = vim.api.nvim_buf_get_lines(bufnr, signature_line, signature_line + 1, false)[1]
  if not line_content or not line_content:match("^<<< signature") then
    -- If this isn't a signature line anymore, just clear highlights and return
    vim.api.nvim_buf_clear_namespace(bufnr, M.namespace_id, signature_line, signature_line + 1)
    return
  end

  -- Clear the highlight and extmark for just this line
  vim.api.nvim_buf_clear_namespace(bufnr, M.namespace_id, signature_line, signature_line + 1)
end

return M
