-- lua/nai/api/response_parser.lua
-- Extract content from provider-specific API response formats

local M = {}

function M.extract_content(parsed, provider)
  if provider == "ollama" then
    if parsed.message and parsed.message.content then
      return parsed.message.content
    end
  elseif provider == "google" then
    if parsed.candidates and #parsed.candidates > 0 and
        parsed.candidates[1].content and
        parsed.candidates[1].content.parts and
        #parsed.candidates[1].content.parts > 0 then
      return parsed.candidates[1].content.parts[1].text
    end
  else
    -- Standard OpenAI format
    if parsed.choices and #parsed.choices > 0 and parsed.choices[1].message then
      return parsed.choices[1].message.content
    end
  end

  return nil
end

return M
