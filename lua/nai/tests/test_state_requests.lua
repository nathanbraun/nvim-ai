-- lua/nai/tests/test_state_requests.lua
local framework = require('nai.tests.framework')
local RequestManager = require('nai.state.requests')

framework.reset_results()

-- Test: Create request manager
framework.run_test("Create request manager", function()
  local manager = RequestManager.new()
  assert(framework.assert_type(manager, "table", "Manager is a table"))
  assert(framework.assert_equals(manager:has_active(), false, "No active requests initially"))
  return true
end)

-- Test: Register a request
framework.run_test("Register a request", function()
  local manager = RequestManager.new()

  local id, err = manager:register("req1", {
    provider = "openai",
    model = "gpt-4"
  })

  assert(framework.assert_equals(err, nil, "No error"))
  assert(framework.assert_equals(id, "req1", "Correct ID returned"))
  assert(framework.assert_equals(manager:has_active(), true, "Has active requests"))
  assert(framework.assert_equals(manager:is_processing(), true, "Is processing"))
  return true
end)

-- Test: Register with invalid ID
framework.run_test("Register with invalid ID", function()
  local manager = RequestManager.new()

  local id, err = manager:register("", { data = "test" })
  assert(framework.assert_equals(id, nil, "Returns nil"))
  assert(framework.assert_type(err, "string", "Returns error message"))
  return true
end)

-- Test: Register with invalid data
framework.run_test("Register with invalid data", function()
  local manager = RequestManager.new()

  local id, err = manager:register("req1", "not a table")
  assert(framework.assert_equals(id, nil, "Returns nil"))
  assert(framework.assert_type(err, "string", "Returns error message"))
  return true
end)

-- Test: Get a specific request
framework.run_test("Get specific request", function()
  local manager = RequestManager.new()

  manager:register("req1", { provider = "openai" })

  local request, err = manager:get("req1")
  assert(framework.assert_equals(err, nil, "No error"))
  assert(framework.assert_equals(request.provider, "openai", "Correct data"))
  return true
end)

-- Test: Get non-existent request
framework.run_test("Get non-existent request", function()
  local manager = RequestManager.new()

  local request, err = manager:get("nonexistent")
  assert(framework.assert_type(err, "string", "Returns error"))
  return true
end)

-- Test: Update a request
framework.run_test("Update request", function()
  local manager = RequestManager.new()

  manager:register("req1", { status = "pending" })

  local success, err = manager:update("req1", { status = "completed" })
  assert(framework.assert_equals(success, true, "Update succeeds"))
  assert(framework.assert_equals(err, nil, "No error"))

  local request = manager:get("req1")
  assert(framework.assert_equals(request.status, "completed", "Status updated"))
  return true
end)

-- Test: Update non-existent request
framework.run_test("Update non-existent request", function()
  local manager = RequestManager.new()

  local success, err = manager:update("nonexistent", { status = "done" })
  assert(framework.assert_equals(success, false, "Update fails"))
  assert(framework.assert_type(err, "string", "Returns error"))
  return true
end)

-- Test: Clear a request
framework.run_test("Clear request", function()
  local manager = RequestManager.new()

  manager:register("req1", { data = "test" })
  assert(framework.assert_equals(manager:has_active(), true, "Has active"))

  local success = manager:clear("req1")
  assert(framework.assert_equals(success, true, "Clear succeeds"))
  assert(framework.assert_equals(manager:has_active(), false, "No active requests"))
  assert(framework.assert_equals(manager:is_processing(), false, "Not processing"))
  return true
end)

-- Test: Clear with multiple requests
framework.run_test("Clear with multiple requests", function()
  local manager = RequestManager.new()

  manager:register("req1", { data = "test1" })
  manager:register("req2", { data = "test2" })
  assert(framework.assert_equals(manager:has_active(), true, "Has active"))

  manager:clear("req1")
  assert(framework.assert_equals(manager:has_active(), true, "Still has active"))
  assert(framework.assert_equals(manager:is_processing(), true, "Still processing"))

  manager:clear("req2")
  assert(framework.assert_equals(manager:has_active(), false, "No active requests"))
  assert(framework.assert_equals(manager:is_processing(), false, "Not processing"))
  return true
end)

-- Test: Get all requests
framework.run_test("Get all requests", function()
  local manager = RequestManager.new()

  manager:register("req1", { data = "test1" })
  manager:register("req2", { data = "test2" })

  local requests = manager:get_all()
  assert(framework.assert_equals(vim.tbl_count(requests), 2, "Two requests"))
  assert(framework.assert_type(requests.req1, "table", "req1 exists"))
  assert(framework.assert_type(requests.req2, "table", "req2 exists"))
  return true
end)

-- Test: Clear all requests
framework.run_test("Clear all requests", function()
  local manager = RequestManager.new()

  manager:register("req1", { data = "test1" })
  manager:register("req2", { data = "test2" })

  local success = manager:clear_all()
  assert(framework.assert_equals(success, true, "Clear all succeeds"))
  assert(framework.assert_equals(manager:has_active(), false, "No active requests"))
  assert(framework.assert_equals(manager:is_processing(), false, "Not processing"))
  return true
end)

-- Test: Snapshot and restore
framework.run_test("Snapshot and restore", function()
  local manager = RequestManager.new()

  manager:register("req1", { data = "original" })

  local snapshot = manager:snapshot()

  manager:register("req2", { data = "new" })
  assert(framework.assert_equals(vim.tbl_count(manager:get_all()), 2, "Two requests"))

  manager:restore(snapshot)
  local requests = manager:get_all()
  assert(framework.assert_equals(vim.tbl_count(requests), 1, "Back to one request"))
  assert(framework.assert_type(requests.req1, "table", "req1 still exists"))
  assert(framework.assert_equals(requests.req2, nil, "req2 removed"))
  return true
end)

-- Test: Subscribe to changes
framework.run_test("Subscribe to request changes", function()
  local manager = RequestManager.new()

  local notification_count = 0
  manager:subscribe(function()
    notification_count = notification_count + 1
  end)

  manager:register("req1", { data = "test" })
  assert(framework.assert_equals(notification_count, 1, "Notified on register"))

  manager:clear("req1")
  assert(framework.assert_equals(notification_count, 2, "Notified on clear"))
  return true
end)

-- Test: Subscribe to processing state
framework.run_test("Subscribe to processing state", function()
  local manager = RequestManager.new()

  local processing_states = {}
  manager:subscribe_processing(function(new_val)
    table.insert(processing_states, new_val)
  end)

  manager:register("req1", { data = "test" })
  assert(framework.assert_equals(processing_states[1], true, "Processing started"))

  manager:clear("req1")
  assert(framework.assert_equals(processing_states[2], false, "Processing stopped"))
  return true
end)

-- Test: Automatic timestamp
framework.run_test("Automatic timestamp", function()
  local manager = RequestManager.new()

  manager:register("req1", { data = "test" })

  local request = manager:get("req1")
  assert(framework.assert_type(request.timestamp, "number", "Timestamp added"))
  return true
end)

-- Test: Debug info
framework.run_test("Debug info", function()
  local manager = RequestManager.new()

  manager:register("req1", { data = "test1" })
  manager:register("req2", { data = "test2" })

  local debug = manager:debug()
  assert(framework.assert_equals(debug.active_count, 2, "Correct count"))
  assert(framework.assert_equals(debug.is_processing, true, "Processing flag correct"))
  assert(framework.assert_equals(#debug.request_ids, 2, "Correct number of IDs"))
  return true
end)

framework.display_results()
