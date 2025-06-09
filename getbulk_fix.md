# SNMP GETBULK Fix Guide

This document provides a comprehensive guide for diagnosing and fixing SNMP GETBULK test failures in the Elixir SNMP simulator.

## Problem Summary

GETBULK tests were failing with the error "OID not increasing" because the simulator was returning the same OID that was queried instead of progressing to the next OID in the MIB tree.

## Root Cause Analysis

### The Core Issue
The GETBULK tests were not using the `WalkPduProcessor` but instead falling back to the legacy PDU processor, which doesn't properly handle OID progression for GETBULK requests.

### Why This Happened
1. **Device Configuration**: Test devices were created without walk data
2. **Routing Logic**: The PDU routing logic in `process_pdu` checks `state.has_walk_data` to decide between processors
3. **Fallback Behavior**: Without walk data, devices use mock implementation with `has_walk_data: false`

### Key Code Paths

#### Device Initialization (`lib/snmp_sim/device.ex`)
```elixir
# Lines 268-283: Walk file loading logic
has_walk_data = case Map.get(device_config, :walk_file) do
  nil -> false
  walk_file -> 
    # Load walk file and set has_walk_data: true
end

# Lines 616-655: initialize_device_state function
case Enum.member?(profiles, state.device_type) do
  true -> {:ok, %{state | has_walk_data: true}}
  false -> {:ok, %{state | has_walk_data: false}}
end
```

#### PDU Routing (`lib/snmp_sim/device/pdu_processor.ex`)
```elixir
# Lines 22-29: Critical routing logic
if state.has_walk_data do
  case pdu.type do
    :get_bulk_request -> WalkPduProcessor.process_getbulk_request(pdu, state)
    # ... other cases
  end
else
  # Legacy processor - causes OID progression issues
end
```

## The Fix

### What Was Changed
Modified the test helper function `call_process_snmp_pdu` in `test/snmp_sim/getbulk_functionality_test.exs`:

```elixir
# BEFORE
GenServer.start_link(Device, %{
  device_type: :cable_modem,
  device_id: "test_#{:rand.uniform(10000)}",
  port: 20000 + :rand.uniform(1000)
})

# AFTER
GenServer.start_link(Device, %{
  device_type: :cable_modem,
  device_id: "test_#{:rand.uniform(10000)}",
  port: 20000 + :rand.uniform(1000),
  walk_file: "priv/walks/cable_modem.walk"  # <-- This line fixes everything
})
```

### Why This Works
1. **Enables Walk Data**: Adding `walk_file` sets `has_walk_data: true` during device initialization
2. **Correct Routing**: PDU requests now route to `WalkPduProcessor` instead of legacy processor
3. **Proper OID Progression**: `WalkPduProcessor` uses walk data to correctly progress through OIDs

## Diagnostic Steps for Future Issues

### 1. Check if WalkPduProcessor is Being Used
Look for debug output: `"WalkPduProcessor: PDU version: X"`

If you don't see this, the device is using the legacy processor.

### 2. Verify Device Configuration
Check if the test device includes a `walk_file` parameter:
```bash
# Search for device creation in tests
grep -r "GenServer.start_link(Device" test/
```

### 3. Check Available Walk Files
```bash
find priv/walks/ -name "*.walk"
```

### 4. Verify Walk File Content
```bash
head -20 priv/walks/cable_modem.walk
```
Should show SNMP walk data starting with standard MIB OIDs like `1.3.6.1.2.1.1.1.0`.

### 5. Test Walk Data Loading
```bash
mix run -e "IO.inspect(SnmpSim.MIB.SharedProfiles.list_profiles())"
```
Should return device types that have walk data loaded.

## Common Symptoms

### GETBULK Returns Same OID
```
GETBULK returned same OID '1.3.6.1' as query '1.3.6.1' - this causes 'OID not increasing' error
```
**Cause**: Using legacy processor instead of WalkPduProcessor
**Fix**: Add `walk_file` to device configuration

### Double-Wrapped Response Tuples
```
** (KeyError) key :varbinds not found in: {:ok, %{...}}
```
**Cause**: GenServer returning `{:ok, {:ok, response}}` 
**Fix**: Remove redundant `{:ok, ...}` wrapping in `process_pdu`

### No Debug Output
If you don't see "WalkPduProcessor: PDU version: X" in test output:
**Cause**: Device not using WalkPduProcessor
**Fix**: Ensure device has walk data loaded

## File Locations

### Key Files to Check
- `lib/snmp_sim/device.ex` - Device initialization and routing
- `lib/snmp_sim/device/pdu_processor.ex` - PDU routing logic
- `lib/snmp_sim/device/walk_pdu_processor.ex` - Walk-based processing
- `test/snmp_sim/getbulk_functionality_test.exs` - GETBULK tests
- `priv/walks/cable_modem.walk` - Walk data file

### Test Helper Function Location
File: `test/snmp_sim/getbulk_functionality_test.exs`
Function: `call_process_snmp_pdu/2` (around line 20)

## Prevention

### For New Tests
Always include `walk_file` when creating test devices that need to handle GETBULK:

```elixir
{:ok, device_pid} = GenServer.start_link(Device, %{
  device_type: :cable_modem,
  device_id: "test_device",
  port: 20000,
  walk_file: "priv/walks/cable_modem.walk"  # Essential for GETBULK
})
```

### For Production Devices
Ensure devices are configured with appropriate walk files or that their device_type exists in SharedProfiles.

## Verification Commands

```bash
# Run GETBULK tests
mix test test/snmp_sim/getbulk_functionality_test.exs --trace

# Run specific failing test
mix test test/snmp_sim/getbulk_functionality_test.exs:39 --trace

# Check for WalkPduProcessor usage (should see debug output)
mix test test/snmp_sim/getbulk_functionality_test.exs | grep "WalkPduProcessor"
```

## Success Indicators

1. **All GETBULK tests pass**: `6 tests, 0 failures`
2. **Debug output present**: `WalkPduProcessor: PDU version: 1`
3. **OID progression works**: Different OIDs returned than queried
4. **No double-wrapping errors**: Clean varbind extraction

## Historical Context

This issue has been encountered multiple times because:
1. The relationship between walk data and PDU routing wasn't obvious
2. Test devices were created without considering the need for walk data
3. The fallback to legacy processor was silent (no obvious error)
4. The fix was simple but the diagnosis was complex

This guide should prevent future iterations of the same debugging cycle.
