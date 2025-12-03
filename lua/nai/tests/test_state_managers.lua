-- lua/nai/tests/test_state_managers.lua
-- Tests for buffers, indicators, and UI managers

local framework = require('nai.tests.framework')
local BufferManager = require('nai.state.buffers')
local IndicatorManager = require('nai.state.indicators')
local UIManager = require('nai.state.ui')

framework.reset_results()

-- ============================================================================
-- Buffer Manager Tests
-- ============================================================================

framework.run_test("Buffer: Activate buffer", function()
  local manager = BufferManager.new()

  local success, err = manager:activate(1)
  assert(framework.assert_equals(success, true, "Activate succeeds"))
  assert(framework.assert_equals(err, nil, "No error"))
  assert(framework.assert_equals(manager:is_activated(1), true, "Buffer is activated"))
  return true
end)

framework.run_test("Buffer: Activate with invalid bufnr", function()
  local manager = BufferManager.new()

  local success, err = manager:activate("not a number")
  assert(framework.assert_equals(success, false, "Activate fails"))
  assert(framework.assert_type(err, "string", "Error message returned"))
  return true
end)

framework.run_test("Buffer: Deactivate buffer", function()
  local manager = BufferManager.new()

  manager:activate(1)
  assert(framework.assert_equals(manager:is_activated(1), true, "Buffer activated"))

  local success = manager:deactivate(1)
  assert(framework.assert_equals(success, true, "Deactivate succeeds"))
  assert(framework.assert_equals(manager:is_activated(1), false, "Buffer deactivated"))
  return true
end)

framework.run_test("Buffer: Get all activated", function()
  local manager = BufferManager.new()

  manager:activate(1)
  manager:activate(2)
  manager:activate(3)

  local buffers = manager:get_all()
  assert(framework.assert_equals(vim.tbl_count(buffers), 3, "Three buffers"))
  assert(framework.assert_equals(buffers[1], true, "Buffer 1 activated"))
  assert(framework.assert_equals(buffers[2], true, "Buffer 2 activated"))
  return true
end)

framework.run_test("Buffer: Clear all", function()
  local manager = BufferManager.new()

  manager:activate(1)
  manager:activate(2)

  manager:clear_all()

  local buffers = manager:get_all()
  assert(framework.assert_equals(vim.tbl_count(buffers), 0, "No buffers"))
  return true
end)

-- ============================================================================
-- Indicator Manager Tests
-- ============================================================================

framework.run_test("Indicator: Register indicator", function()
  local manager = IndicatorManager.new()

  local id, err = manager:register("ind1", { type = "spinner" })
  assert(framework.assert_equals(err, nil, "No error"))
  assert(framework.assert_equals(id, "ind1", "Correct ID returned"))
  return true
end)

framework.run_test("Indicator: Register with invalid ID", function()
  local manager = IndicatorManager.new()

  local id, err = manager:register("", { type = "spinner" })
  assert(framework.assert_equals(id, nil, "Returns nil"))
  assert(framework.assert_type(err, "string", "Error message"))
  return true
end)

framework.run_test("Indicator: Get indicator", function()
  local manager = IndicatorManager.new()

  manager:register("ind1", { type = "spinner", active = true })

  local indicator, err = manager:get("ind1")
  assert(framework.assert_equals(err, nil, "No error"))
  assert(framework.assert_equals(indicator.type, "spinner", "Correct type"))
  assert(framework.assert_equals(indicator.active, true, "Correct active"))
  return true
end)

framework.run_test("Indicator: Update indicator", function()
  local manager = IndicatorManager.new()

  manager:register("ind1", { status = "pending" })

  local success = manager:update("ind1", { status = "complete" })
  assert(framework.assert_equals(success, true, "Update succeeds"))

  local indicator = manager:get("ind1")
  assert(framework.assert_equals(indicator.status, "complete", "Status updated"))
  return true
end)

framework.run_test("Indicator: Clear indicator", function()
  local manager = IndicatorManager.new()

  manager:register("ind1", { data = "test" })

  local success = manager:clear("ind1")
  assert(framework.assert_equals(success, true, "Clear succeeds"))

  local indicator, err = manager:get("ind1")
  assert(framework.assert_type(err, "string", "Indicator not found"))
  return true
end)

framework.run_test("Indicator: Get all", function()
  local manager = IndicatorManager.new()

  manager:register("ind1", { type = "spinner" })
  manager:register("ind2", { type = "progress" })

  local indicators = manager:get_all()
  assert(framework.assert_equals(vim.tbl_count(indicators), 2, "Two indicators"))
  return true
end)

-- ============================================================================
-- UI Manager Tests
-- ============================================================================

framework.run_test("UI: Initialize with provider and model", function()
  local manager = UIManager.new("openai", "gpt-4")

  assert(framework.assert_equals(manager:get_provider(), "openai", "Provider set"))
  assert(framework.assert_equals(manager:get_model(), "gpt-4", "Model set"))
  return true
end)

framework.run_test("UI: Set valid provider", function()
  local manager = UIManager.new()

  local success, err = manager:set_provider("openai")
  assert(framework.assert_equals(success, true, "Set succeeds"))
  assert(framework.assert_equals(err, nil, "No error"))
  assert(framework.assert_equals(manager:get_provider(), "openai", "Provider updated"))
  return true
end)

framework.run_test("UI: Set invalid provider", function()
  local manager = UIManager.new()

  local success, err = manager:set_provider("invalid_provider")
  assert(framework.assert_equals(success, false, "Set fails"))
  assert(framework.assert_type(err, "string", "Error message"))
  return true
end)

framework.run_test("UI: Set model", function()
  local manager = UIManager.new()

  local success = manager:set_model("gpt-4")
  assert(framework.assert_equals(success, true, "Set succeeds"))
  assert(framework.assert_equals(manager:get_model(), "gpt-4", "Model updated"))
  return true
end)

framework.run_test("UI: Set processing state", function()
  local manager = UIManager.new()

  local success = manager:set_processing(true)
  assert(framework.assert_equals(success, true, "Set succeeds"))
  assert(framework.assert_equals(manager:is_processing(), true, "Processing true"))

  manager:set_processing(false)
  assert(framework.assert_equals(manager:is_processing(), false, "Processing false"))
  return true
end)

framework.run_test("UI: Subscribe to provider changes", function()
  local manager = UIManager.new("openai", "gpt-4")

  local notified = false
  local new_provider = nil

  manager:subscribe_provider(function(new_val)
    notified = true
    new_provider = new_val
  end)

  manager:set_provider("ollama")

  assert(framework.assert_equals(notified, true, "Notified"))
  assert(framework.assert_equals(new_provider, "ollama", "Correct new provider"))
  return true
end)

framework.run_test("UI: Debug info", function()
  local manager = UIManager.new("openai", "gpt-4")

  local debug = manager:debug()
  assert(framework.assert_equals(debug.current_provider, "openai", "Provider in debug"))
  assert(framework.assert_equals(debug.current_model, "gpt-4", "Model in debug"))
  assert(framework.assert_equals(debug.is_processing, false, "Processing in debug"))
  return true
end)

framework.display_results()
