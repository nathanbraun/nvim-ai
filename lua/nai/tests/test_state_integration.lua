-- lua/nai/tests/test_state_integration.lua
-- Integration tests for the unified state module

local framework = require('nai.tests.framework')

framework.reset_results()

-- Test: Initialize state
framework.run_test("State: Initialize with config", function()
  local state = require('nai.state')
  
  local config = {
    active_provider = "openai",
    providers = {
      openai = {
        model = "gpt-4"
      }
    }
  }
  
  state.init(config)
  
  assert(framework.assert_type(state.requests, "table", "Requests manager exists"))
  assert(framework.assert_type(state.buffers, "table", "Buffers manager exists"))
  assert(framework.assert_type(state.indicators, "table", "Indicators manager exists"))
  assert(framework.assert_type(state.ui, "table", "UI manager exists"))
  
  assert(framework.assert_equals(state.get_current_provider(), "openai", "Provider set"))
  assert(framework.assert_equals(state.get_current_model(), "gpt-4", "Model set"))
  
  return true
end)

-- Test: Request workflow
framework.run_test("State: Request workflow", function()
  local state = require('nai.state')
  
  -- Register a request
  local id, err = state.register_request("test_req", { data = "test" })
  assert(framework.assert_equals(err, nil, "No error"))
  assert(framework.assert_equals(id, "test_req", "Request registered"))
  
  -- Check it exists
  assert(framework.assert_equals(state.has_active_requests(), true, "Has active requests"))
  
  -- Update it
  local success = state.update_request("test_req", { status = "complete" })
  assert(framework.assert_equals(success, true, "Request updated"))
  
  -- Clear it
  success = state.clear_request("test_req")
  assert(framework.assert_equals(success, true, "Request cleared"))
  assert(framework.assert_equals(state.has_active_requests(), false, "No active requests"))
  
  return true
end)

-- Test: Buffer workflow
framework.run_test("State: Buffer workflow", function()
  local state = require('nai.state')
  
  -- Activate a buffer
  local success = state.activate_buffer(1)
  assert(framework.assert_equals(success, true, "Buffer activated"))
  assert(framework.assert_equals(state.is_buffer_activated(1), true, "Buffer is activated"))
  
  -- Deactivate it
  success = state.deactivate_buffer(1)
  assert(framework.assert_equals(success, true, "Buffer deactivated"))
  assert(framework.assert_equals(state.is_buffer_activated(1), false, "Buffer not activated"))
  
  return true
end)

-- Test: Indicator workflow
framework.run_test("State: Indicator workflow", function()
  local state = require('nai.state')
  
  local id, err = state.register_indicator("ind1", { type = "spinner" })
  assert(framework.assert_equals(err, nil, "No error"))
  assert(framework.assert_equals(id, "ind1", "Indicator registered"))
  
  local success = state.clear_indicator("ind1")
  assert(framework.assert_equals(success, true, "Indicator cleared"))
  
  return true
end)

-- Test: UI state workflow
framework.run_test("State: UI state workflow", function()
  local state = require('nai.state')
  
  local success = state.set_current_provider("ollama")
  assert(framework.assert_equals(success, true, "Provider set"))
  assert(framework.assert_equals(state.get_current_provider(), "ollama", "Provider updated"))
  
  success = state.set_current_model("llama2")
  assert(framework.assert_equals(success, true, "Model set"))
  assert(framework.assert_equals(state.get_current_model(), "llama2", "Model updated"))
  
  return true
end)

-- Test: Reset processing state
framework.run_test("State: Reset processing state", function()
  local state = require('nai.state')
  
  -- Create some state
  state.register_request("req1", { data = "test" })
  state.register_indicator("ind1", { type = "spinner" })
  
  -- Reset
  local success = state.reset_processing_state()
  assert(framework.assert_equals(success, true, "Reset succeeds"))
  
  -- Verify everything is cleared
  assert(framework.assert_equals(state.has_active_requests(), false, "No requests"))
  assert(framework.assert_equals(vim.tbl_count(state.indicators:get_all()), 0, "No indicators"))
  
  return true
end)

-- Test: Snapshot and restore
framework.run_test("State: Snapshot and restore", function()
  local state = require('nai.state')
  
  -- Set up some state
  state.register_request("req1", { data = "original" })
  state.activate_buffer(1)
  state.set_current_provider("openai")
  
  -- Take snapshot
  local snapshot = state.snapshot()
  assert(framework.assert_type(snapshot, "table", "Snapshot created"))
  
  -- Modify state
  state.register_request("req2", { data = "new" })
  state.activate_buffer(2)
  state.set_current_provider("ollama")
  
  -- Verify modifications
  assert(framework.assert_equals(vim.tbl_count(state.get_active_requests()), 2, "Two requests"))
  assert(framework.assert_equals(state.get_current_provider(), "ollama", "Provider changed"))
  
  -- Restore snapshot
  local success, err = state.restore(snapshot)
  assert(framework.assert_equals(success, true, "Restore succeeds"))
  assert(framework.assert_equals(err, nil, "No error"))
  
  -- Verify restoration
  local requests = state.get_active_requests()
  assert(framework.assert_equals(vim.tbl_count(requests), 1, "Back to one request"))
  assert(framework.assert_type(requests.req1, "table", "Original request exists"))
  assert(framework.assert_equals(state.get_current_provider(), "openai", "Provider restored"))
  
  return true
end)

-- Test: Debug info
framework.run_test("State: Debug info", function()
  local state = require('nai.state')
  
  state.register_request("req1", { data = "test" })
  state.activate_buffer(1)
  
  local debug = state.debug()
  assert(framework.assert_type(debug, "table", "Debug info returned"))
  assert(framework.assert_type(debug.requests, "table", "Request debug info"))
  assert(framework.assert_type(debug.buffers, "table", "Buffer debug info"))
  assert(framework.assert_type(debug.indicators, "table", "Indicator debug info"))
  assert(framework.assert_type(debug.ui, "table", "UI debug info"))
  
  return true
end)

-- Test: Subscriptions
framework.run_test("State: Subscribe to requests", function()
  local state = require('nai.state')
  
  local notified = false
  state.subscribe_requests(function()
    notified = true
  end)
  
  state.register_request("req1", { data = "test" })
  assert(framework.assert_equals(notified, true, "Subscription fired"))
  
  return true
end)

framework.display_results()

