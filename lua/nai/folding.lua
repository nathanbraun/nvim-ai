-- lua/nai/folding.lua
local M = {}
local constants = require('nai.constants')

-- Store original fold settings for buffers
M.original_settings = {}

-- Helper function to get the original fold level
function M.get_original_fold_level(lnum, winid)
  local win_key = "win_" .. winid
  if M.original_settings[win_key] and M.original_settings[win_key].original_foldexpr then
    -- Save current foldexpr
    local current_foldexpr = vim.wo[winid].foldexpr

    -- Temporarily restore original foldexpr
    vim.wo[winid].foldexpr = M.original_settings[win_key].original_foldexpr

    -- Get the fold level using original expression
    local level = vim.fn.foldlevel(lnum)

    -- Restore our foldexpr
    vim.wo[winid].foldexpr = current_foldexpr

    return level
  end
  return 0
end

-- Calculate fold level for a line
function M.get_fold_level(lnum)
  local line = vim.fn.getline(lnum)
  local prev_line = lnum > 1 and vim.fn.getline(lnum - 1) or ""
  local winid = vim.fn.win_getid()

  -- Check for chat markers
  if line:match("^" .. vim.pesc(constants.MARKERS.USER) .. "$") then
    return ">1" -- Start a fold for user messages
  elseif line:match("^" .. vim.pesc(constants.MARKERS.ASSISTANT) .. "$") then
    return ">1" -- Start a fold for assistant messages
  elseif line:match("^" .. vim.pesc(constants.MARKERS.SYSTEM) .. "$") then
    return ">1" -- Start a fold for system messages
  elseif line:match("^" .. vim.pesc(constants.MARKERS.CONFIG) .. "$") then
    return ">1" -- Start a fold for config messages
  end

  -- Check for special blocks (nested folding)
  if line:match("^>>> %w+") then
    -- Any special block marker (scrape, youtube, etc.)
    return ">2" -- Nested fold
  end

  -- If we're inside a YAML header, fold it
  if lnum == 1 and line == "---" then
    return ">1" -- Start fold for YAML header
  elseif line == "---" and prev_line ~= "" then
    return "<1" -- End fold for YAML header
  end

  -- For headings, use markdown-style folding
  if line:match("^#%s") then
    return ">1" -- Level 1 heading
  elseif line:match("^##%s") then
    return ">2" -- Level 2 heading
  elseif line:match("^###%s") then
    return ">3" -- Level 3 heading
  elseif line:match("^####%s") then
    return ">4" -- Level 4 heading
  elseif line:match("^#####%s") then
    return ">5" -- Level 5 heading
  elseif line:match("^######%s") then
    return ">6" -- Level 6 heading
  end

  -- Check for VimWiki syntax
  if vim.bo.filetype == "vimwiki" then
    if line:match("^=%s") then
      return ">1" -- Level 1 heading
    elseif line:match("^==%s") then
      return ">2" -- Level 2 heading
    elseif line:match("^===%s") then
      return ">3" -- Level 3 heading
    elseif line:match("^====%s") then
      return ">4" -- Level 4 heading
    elseif line:match("^=====%s") then
      return ">5" -- Level 5 heading
    elseif line:match("^======%s") then
      return ">6" -- Level 6 heading
    end
  end

  -- Default: keep current fold level
  return "="
end

-- Apply folding to a buffer
function M.apply_to_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Store buffer ID for later use with autocmds
  local augroup = vim.api.nvim_create_augroup('NaiFolding' .. bufnr, { clear = true })

  -- Set up an autocmd for when this buffer is displayed in a window
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = augroup,
    buffer = bufnr,
    callback = function()
      local winid = vim.fn.bufwinid(bufnr)
      if winid ~= -1 then
        -- Store original settings (keyed by window ID)
        local win_key = "win_" .. winid
        M.original_settings[win_key] = {
          foldmethod = vim.wo[winid].foldmethod,
          foldexpr = vim.wo[winid].foldexpr,
          original_foldexpr = vim.wo[winid].foldexpr, -- Save for reference
        }

        -- Set our custom folding (window-local)
        vim.wo[winid].foldmethod = "expr"
        vim.wo[winid].foldexpr = "v:lua.require('nai.folding').get_fold_level(v:lnum)"
        vim.wo[winid].foldenable = true
        vim.wo[winid].foldlevel = 0 -- Start with all folds closed
      end
    end
  })

  -- Also handle when buffer is removed from window
  vim.api.nvim_create_autocmd("BufWinLeave", {
    group = augroup,
    buffer = bufnr,
    callback = function()
      local winid = vim.fn.bufwinid(bufnr)
      if winid ~= -1 then
        local win_key = "win_" .. winid
        if M.original_settings[win_key] then
          -- Restore original settings
          vim.wo[winid].foldmethod = M.original_settings[win_key].foldmethod
          vim.wo[winid].foldexpr = M.original_settings[win_key].foldexpr

          -- Clean up
          M.original_settings[win_key] = nil
        end
      end
    end
  })

  -- If buffer is already in a window, apply settings now
  local winid = vim.fn.bufwinid(bufnr)
  if winid ~= -1 then
    -- Store original settings
    local win_key = "win_" .. winid
    M.original_settings[win_key] = {
      foldmethod = vim.wo[winid].foldmethod,
      foldexpr = vim.wo[winid].foldexpr,
      original_foldexpr = vim.wo[winid].foldexpr, -- Save for reference
    }

    -- Apply our settings
    vim.wo[winid].foldmethod = "expr"
    vim.wo[winid].foldexpr = "v:lua.require('nai.folding').get_fold_level(v:lnum)"
    vim.wo[winid].foldenable = true
    vim.wo[winid].foldlevel = 0
  end
end

-- Restore original folding settings
function M.restore_original(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Clear the autocmds
  vim.api.nvim_clear_autocmds({ group = 'NaiFolding' .. bufnr })

  -- If buffer is in a window, restore settings
  local winid = vim.fn.bufwinid(bufnr)
  if winid ~= -1 then
    local win_key = "win_" .. winid
    if M.original_settings[win_key] then
      vim.wo[winid].foldmethod = M.original_settings[win_key].foldmethod
      vim.wo[winid].foldexpr = M.original_settings[win_key].foldexpr
      M.original_settings[win_key] = nil
    end
  end

  -- Clean up any other stored settings for this buffer
  for key in pairs(M.original_settings) do
    if key:match("^win_") then
      M.original_settings[key] = nil
    end
  end
end

return M
