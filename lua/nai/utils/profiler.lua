-- lua/nai/utils/profiler.lua
local M = {}

-- Store timing data
M.timings = {}
M.enabled = false

-- Enable or disable profiling
function M.toggle(enable)
  if enable ~= nil then
    M.enabled = enable
  else
    M.enabled = not M.enabled
  end

  if M.enabled then
    vim.notify("NAI Profiling enabled", vim.log.levels.INFO)
  else
    vim.notify("NAI Profiling disabled", vim.log.levels.INFO)
    -- Print summary when disabling
    M.print_summary()
    -- Clear timings
    M.timings = {}
  end

  return M.enabled
end

-- Measure execution time of a function
function M.measure(name, func, ...)
  if not M.enabled then
    return func(...)
  end

  if not M.timings[name] then
    M.timings[name] = { count = 0, total_time = 0, max_time = 0 }
  end

  local start_time = vim.loop.hrtime()
  local result = { func(...) }
  local end_time = vim.loop.hrtime()

  local elapsed = (end_time - start_time) / 1000000 -- Convert to milliseconds

  M.timings[name].count = M.timings[name].count + 1
  M.timings[name].total_time = M.timings[name].total_time + elapsed
  M.timings[name].max_time = math.max(M.timings[name].max_time, elapsed)

  return unpack(result)
end

-- Print a summary of all timings
function M.print_summary()
  if vim.tbl_isempty(M.timings) then
    vim.notify("No profiling data available", vim.log.levels.INFO)
    return
  end

  -- Convert to a list for sorting
  local timing_list = {}
  for name, data in pairs(M.timings) do
    table.insert(timing_list, {
      name = name,
      count = data.count,
      total_time = data.total_time,
      avg_time = data.total_time / data.count,
      max_time = data.max_time
    })
  end

  -- Sort by total time (descending)
  table.sort(timing_list, function(a, b)
    return a.total_time > b.total_time
  end)

  -- Print the results
  local lines = { "NAI Profiling Results:", "--------------------" }
  table.insert(lines, string.format("%-30s %10s %15s %15s %15s",
    "Operation", "Count", "Total (ms)", "Avg (ms)", "Max (ms)"))

  for _, timing in ipairs(timing_list) do
    table.insert(lines, string.format("%-30s %10d %15.2f %15.2f %15.2f",
      timing.name, timing.count, timing.total_time, timing.avg_time, timing.max_time))
  end

  -- Display in a floating window
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local width = 90
  local height = #lines
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded"
  })

  -- Set buffer options
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")

  -- Close on any keypress
  vim.api.nvim_buf_set_keymap(buf, "n", "q", ":close<CR>", { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", ":close<CR>", { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, "n", "<CR>", ":close<CR>", { noremap = true, silent = true })
end

return M
