-- lua/nai/tests/test_state_store.lua
local framework = require('nai.tests.framework')
local Store = require('nai.state.store')

-- Reset results before running
framework.reset_results()

-- Test: Create store with initial state
framework.run_test("Create store with initial state", function()
  local store = Store.new({ foo = "bar", nested = { value = 42 } })
  local state = store:get()

  assert(framework.assert_equals(state.foo, "bar", "Initial foo value"))
  assert(framework.assert_equals(state.nested.value, 42, "Initial nested value"))
  return true
end)

-- Test: Get nested values
framework.run_test("Get nested values", function()
  local store = Store.new({ a = { b = { c = "deep" } } })
  local value, err = store:get("a.b.c")

  assert(framework.assert_equals(err, nil, "No error"))
  assert(framework.assert_equals(value, "deep", "Correct nested value"))
  return true
end)

-- Test: Get non-existent path returns error
framework.run_test("Get non-existent path", function()
  local store = Store.new({ foo = "bar" })
  local value, err = store:get("nonexistent.path")

  assert(framework.assert_type(err, "string", "Error message returned"))
  assert(framework.assert_equals(value, nil, "Value is nil"))
  return true
end)

-- Test: Set simple value
framework.run_test("Set simple value", function()
  local store = Store.new({})
  local success, err = store:set("foo", "bar")

  assert(framework.assert_equals(success, true, "Set succeeds"))
  assert(framework.assert_equals(err, nil, "No error"))

  local value = store:get("foo")
  assert(framework.assert_equals(value, "bar", "Value is set"))
  return true
end)

-- Test: Set nested value
framework.run_test("Set nested value", function()
  local store = Store.new({})
  local success = store:set("a.b.c", "nested")

  assert(framework.assert_equals(success, true, "Set succeeds"))

  local value = store:get("a.b.c")
  assert(framework.assert_equals(value, "nested", "Nested value is set"))
  return true
end)

-- Test: Set with validator (valid)
framework.run_test("Set with validator - valid", function()
  local store = Store.new({})

  local validator = function(value)
    return type(value) == "number", "Must be a number"
  end

  local success = store:set("count", 42, validator)
  assert(framework.assert_equals(success, true, "Valid value accepted"))

  local value = store:get("count")
  assert(framework.assert_equals(value, 42, "Value is set"))
  return true
end)

-- Test: Set with validator (invalid)
framework.run_test("Set with validator - invalid", function()
  local store = Store.new({})

  local validator = function(value)
    return type(value) == "number", "Must be a number"
  end

  local success, err = store:set("count", "not a number", validator)
  assert(framework.assert_equals(success, false, "Invalid value rejected"))
  assert(framework.assert_type(err, "string", "Error message returned"))
  return true
end)

-- Test: Snapshot and restore
framework.run_test("Snapshot and restore", function()
  local store = Store.new({ foo = "bar", count = 1 })

  -- Create snapshot
  local snapshot = store:snapshot()

  -- Modify state
  store:set("foo", "modified")
  store:set("count", 99)

  local modified = store:get()
  assert(framework.assert_equals(modified.foo, "modified", "State is modified"))
  assert(framework.assert_equals(modified.count, 99, "Count is modified"))

  -- Restore snapshot
  store:restore(snapshot)

  local restored = store:get()
  assert(framework.assert_equals(restored.foo, "bar", "State is restored"))
  assert(framework.assert_equals(restored.count, 1, "Count is restored"))
  return true
end)

-- Test: Update multiple paths atomically
framework.run_test("Update multiple paths", function()
  local store = Store.new({ a = 1, b = 2 })

  local success = store:update({
    ["a"] = 10,
    ["b"] = 20,
    ["c"] = 30
  })

  assert(framework.assert_equals(success, true, "Update succeeds"))
  assert(framework.assert_equals(store:get("a"), 10, "a is updated"))
  assert(framework.assert_equals(store:get("b"), 20, "b is updated"))
  assert(framework.assert_equals(store:get("c"), 30, "c is created"))
  return true
end)

-- Test: Update rollback on failure
framework.run_test("Update rollback on validation failure", function()
  local store = Store.new({ count = 5 })

  local validator = function(value)
    return type(value) == "number", "Must be a number"
  end

  -- This should fail and rollback
  local success, err = store:update({
    ["count"] = 10,
    ["invalid"] = "not a number"
  }, validator)

  assert(framework.assert_equals(success, false, "Update fails"))
  assert(framework.assert_type(err, "string", "Error message returned"))

  -- Original value should be unchanged
  assert(framework.assert_equals(store:get("count"), 5, "Original value unchanged"))
  return true
end)

-- Test: Subscribe to changes
framework.run_test("Subscribe to changes", function()
  local store = Store.new({ value = 1 })

  local notification_received = false
  local received_new_value = nil
  local received_old_value = nil

  store:subscribe("value", function(new_val, old_val)
    notification_received = true
    received_new_value = new_val
    received_old_value = old_val
  end)

  store:set("value", 2)

  assert(framework.assert_equals(notification_received, true, "Notification received"))
  assert(framework.assert_equals(received_new_value, 2, "New value correct"))
  assert(framework.assert_equals(received_old_value, 1, "Old value correct"))
  return true
end)

-- Test: Wildcard subscription
framework.run_test("Wildcard subscription", function()
  local store = Store.new({ a = 1, b = 2 })

  local notifications = {}

  store:subscribe("*", function(new_val, old_val, path)
    table.insert(notifications, { path = path, new_val = new_val })
  end)

  store:set("a", 10)
  store:set("b", 20)

  assert(framework.assert_equals(#notifications, 2, "Two notifications received"))
  assert(framework.assert_equals(notifications[1].path, "a", "First path correct"))
  assert(framework.assert_equals(notifications[2].path, "b", "Second path correct"))
  return true
end)

-- Test: Unsubscribe
framework.run_test("Unsubscribe", function()
  local store = Store.new({ value = 1 })

  local count = 0
  local unsubscribe = store:subscribe("value", function()
    count = count + 1
  end)

  store:set("value", 2)
  assert(framework.assert_equals(count, 1, "First notification received"))

  unsubscribe()

  store:set("value", 3)
  assert(framework.assert_equals(count, 1, "No notification after unsubscribe"))
  return true
end)

-- Test: Immutability - external modifications don't affect store
framework.run_test("State immutability", function()
  local store = Store.new({ data = { value = 42 } })

  -- Get state and try to modify it
  local state = store:get()
  state.data.value = 999

  -- Store should still have original value
  local actual = store:get("data.value")
  assert(framework.assert_equals(actual, 42, "Store state unchanged by external modification"))
  return true
end)

-- Display results
framework.display_results()
