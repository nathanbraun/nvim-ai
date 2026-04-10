--- Shared session key utilities
--- Used by gateway.lua for frontmatter-based session keys

local M = {}

--- Extract a value from YAML frontmatter
--- @param buffer_id number Buffer number
--- @param field_name string YAML field to look for (e.g., "session_key", "moltbot_session")
--- @param max_lines? number How many lines to scan (default 30)
--- @return string|nil value The trimmed value, or nil if not found/empty
function M.read_frontmatter_field(buffer_id, field_name, max_lines)
  max_lines = max_lines or 30
  local lines = vim.api.nvim_buf_get_lines(buffer_id, 0, max_lines, false)
  local in_frontmatter = false

  for i, line in ipairs(lines) do
    if line:match('^%-%-%-') then
      if not in_frontmatter then
        in_frontmatter = true
      else
        break -- End of frontmatter
      end
    elseif in_frontmatter then
      local value = line:match('^' .. vim.pesc(field_name) .. ':%s*(.+)$')
      if value then
        local trimmed = value:gsub('^%s*(.-)%s*$', '%1')
        if trimmed ~= '' then
          return trimmed
        end
      end
    end
  end

  return nil
end

--- Generate a unique request ID
--- @param prefix? string Optional prefix (default "nvim")
--- @return string
function M.generate_request_id(prefix)
  prefix = prefix or "nvim"
  return string.format("%s_%d_%d_%04d",
    prefix,
    vim.fn.getpid(),
    os.time(),
    math.random(0, 9999)
  )
end

return M
