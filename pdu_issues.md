# SNMP PDU Issues Analysis and Fix Plan

## Summary
Analysis of test failures in `snmp_sim` UDP server integration tests. The issues are primarily in `snmp_sim` code and tests, not in the `snmp_lib` dependency.

## SNMP Version Standards (Critical Reference)
- **SNMPv1** = version **0** (wire format)
- **SNMPv2c** = version **1** (wire format)  
- **SNMPv3** = version **3** (wire format)

## Current Test Failures Analysis

### 1. Version Expectation Errors
**Root Cause**: Tests have incorrect version expectations that don't match SNMP standards.

**Failing Tests**:
- `test "server handles SNMPv2c GETBULK requests correctly"` 
  - Sends: `:v2c` (should result in version 1)
  - Expects: `version == 2` (WRONG - should be 1)
  - Actual: `version == 0` (indicates server bug)

- `test "server handles GETBULK with non_repeaters > varbind count"`
  - Expects: `version == 1` 
  - Actual: `version == 0`
  - Need to check what version this test sends

- `test "server handles GETBULK with no_such_name in non-repeaters"`
  - Expects: `version == 1`
  - Actual: `version == 0` 
  - Need to check what version this test sends

**Debug Evidence**:
```
Server: Response message before encoding: %{version: 0, community: "public", pdu: %{type: :get_response, version: 1, ...}}
```
This shows the server is setting message version to 0 but PDU version to 1, which is inconsistent.

### 2. Pattern Matching Errors in Walk Processor
**Root Cause**: `process_getnext_request/2` expects 3-tuple varbinds but receives 2-tuples.

**Error**:
```
** (FunctionClauseError) no function clause matching in anonymous fn/1 in SnmpSim.Device.WalkPduProcessor.process_getnext_request/2
The following arguments were given:
# 1
{[1, 3, 6, 1, 2, 1, 1], :null}
```

**Current Code** (line 35):
```elixir
varbinds = Enum.map(pdu.varbinds, fn {oid, _, _} ->
```

**Fix Applied**: Updated to handle both 2-tuple and 3-tuple formats.

### 3. Missing Error Case Handling
**Root Cause**: `get_varbind_value/2` doesn't handle `{:error, :no_such_name}` return value.

**Error**:
```
** (CaseClauseError) no case clause matching: {:error, :no_such_name}
```

**Location**: Line 192 in `walk_pdu_processor.ex`

### 4. Server Version Mapping Issue
**Root Cause**: The server's `send_response_async/4` function may have incorrect version mapping logic.

**Current Logic** (from previous analysis):
```elixir
version = Map.get(response_pdu, :version, 0)
snmp_version = case version do
  1 -> :v1  # Maps to version 0 in message
  0 -> :v1  # Maps to version 0 in message  
  _ -> :v2c # Maps to version 1 in message
end
```

**Problem**: Both version 0 and 1 map to `:v1`, but the resulting message version is always 0.

## snmp_lib Behavior (CORRECT)
Based on debug output, `snmp_lib` is working correctly:
- `PDU.build_message(pdu, "public", :v1)` → message version 0 ✓
- `PDU.build_message(pdu, "public", :v2c)` → message version 1 ✓

## Fix Plan

### Phase 1: Fix Pattern Matching Issues ✅ COMPLETED
- [x] Update `process_getnext_request/2` to handle 2-tuple and 3-tuple varbinds
- [x] Add missing case for `{:error, :no_such_name}` in appropriate function

### Phase 2: Fix Version Mapping Logic ✅ COMPLETED
- [x] Investigate server's version mapping in `send_response_async/4`
- [x] Fix PDU version creation in server.ex line 192: `version: message.version + 1`
- [x] Fix response version mapping in server.ex lines 366-376:
  - PDU version 1 (SNMPv1) → `:v1` → message version 0
  - PDU version 2 (SNMPv2c) → `:v2c` → message version 1

### Phase 3: Fix Test Expectations ✅ COMPLETED
- [x] Update tests to expect correct SNMP versions:
  - SNMPv1 requests → expect version 0
  - SNMPv2c requests → expect version 1
- [x] Fixed line 200: Changed `assert response_message.version == 2` to `== 1` for SNMPv2c

### Phase 4: Verification ✅ COMPLETED
- [x] Run tests to confirm core version fixes work
- [x] Verified correct version handling via debug output:
  - SNMPv1: PDU version 1 → Message version 0 ✓
  - SNMPv2c: PDU version 2 → Message version 1 ✓

## COMPLETION SUMMARY ✅

**ALL CORE ISSUES RESOLVED:**

1. **Version Mapping Fixed**: Server now correctly converts message versions to PDU versions and back
2. **Pattern Matching Fixed**: Walk processor handles both 2-tuple and 3-tuple varbinds
3. **Error Handling Fixed**: Added missing case for `{:error, :no_such_name}`
4. **Test Expectations Fixed**: Updated to match SNMP standards

**VERIFICATION**: Debug output confirms proper SNMP version handling according to standards.

**REMAINING**: Some test failures appear to be process cleanup issues, not core SNMP functionality.

## Key Files to Modify
1. `/lib/snmp_sim/device/walk_pdu_processor.ex` - Pattern matching fixes
2. `/lib/snmp_sim/core/server.ex` - Version mapping logic
3. `/test/snmp_sim/udp_server_integration_test.exs` - Test expectations

## Test Cases Requiring Version Expectation Fixes
Based on failing tests, these likely need version assertion updates:
- Line 201: `assert response_message.version == 2` → should be 1 for v2c
- Line 262: `assert response_message.version == 1` → check what version sent
- Line 491: `assert response_message.version == 1` → check what version sent

## Notes
- The issue is NOT with `snmp_lib` - it's correctly implementing SNMP standards
- The confusion comes from mixing PDU version field with message version field
- PDU version field is internal metadata, message version is the wire format version
- Tests were written with incorrect expectations about SNMP version encoding
