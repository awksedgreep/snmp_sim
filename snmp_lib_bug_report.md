# Bug Report: snmp_lib Varbind Encoding/Decoding Issues

## Summary
The `snmp_lib` library (version 1.0.4) has inconsistent behavior when encoding and decoding SNMP varbinds with certain types, specifically `:object_identifier` and `:end_of_mib_view` types.

## Environment
- **snmp_lib version**: 1.0.4 (from GitHub repository)
- **Elixir version**: 1.18.3
- **Erlang/OTP version**: 26

## Issue Description

### Problem 1: Object Identifier Varbinds
When encoding varbinds with type `:object_identifier` and string values, the library encodes them successfully but decodes them incorrectly as `:null` type with `:null` value.

**Expected behavior**: String OID values should either be properly decoded back to strings, or the library should reject string values during encoding and require OID lists.

**Actual behavior**: String values are silently accepted during encoding but become `:null` during decoding.

### Problem 2: End of MIB View Varbinds
When encoding varbinds with type `:end_of_mib_view` and tuple values `{:end_of_mib_view, nil}`, the library encodes them but decodes them incorrectly.

**Expected behavior**: The library should consistently handle `:end_of_mib_view` values.

**Actual behavior**: Tuple values are accepted during encoding but decoded incorrectly.

## Reproduction Steps

### Test Case 1: Object Identifier Issue
```elixir
# This demonstrates the object identifier encoding/decoding issue
varbind = {[1, 3, 6, 1, 2, 1, 1, 2, 0], :object_identifier, "SNMPv2-SMI::enterprises.4491.2.4.1"}

pdu = %{
  type: :get_response,
  version: 2,
  request_id: 12345,
  community: "public",
  varbinds: [varbind],
  error_status: 0,
  error_index: 0
}

# Build and encode message
message = SnmpLib.PDU.build_message(pdu, "public", :v2c)
{:ok, encoded} = SnmpLib.PDU.encode_message(message)

# Decode message
{:ok, decoded} = SnmpLib.PDU.decode_message(encoded)

# BUG: Original varbind has :object_identifier type with string value
# Decoded varbind has :null type with :null value
IO.inspect(pdu.varbinds)      # [{[1,3,6,1,2,1,1,2,0], :object_identifier, "SNMPv2-SMI::enterprises.4491.2.4.1"}]
IO.inspect(decoded.pdu.varbinds)  # [{[1,3,6,1,2,1,1,2,0], :null, :null}]
```

### Test Case 2: Working Object Identifier (with OID list)
```elixir
# This works correctly when using OID lists instead of strings
varbind = {[1, 3, 6, 1, 2, 1, 1, 2, 0], :object_identifier, [1, 3, 6, 1, 4, 1, 4491, 2, 4, 1]}

# Same encoding/decoding process as above
# Result: Correctly encodes and decodes as :object_identifier with OID list value
```

### Test Case 3: End of MIB View Issue
```elixir
# This demonstrates the end_of_mib_view encoding/decoding issue
varbind = {[1, 3, 6, 1, 2, 1, 99, 99, 0], :end_of_mib_view, {:end_of_mib_view, nil}}

# Same encoding/decoding process
# BUG: Tuple value is accepted during encoding but decoded incorrectly
# Works correctly when using nil value instead of tuple
```

## Expected Fix Options

### Option 1: Input Validation (Recommended)
The library should validate varbind values during encoding and reject incompatible types:
- For `:object_identifier` type, only accept OID lists (arrays of integers)
- For `:end_of_mib_view` type, only accept `nil` values
- Return clear error messages for invalid combinations

### Option 2: Value Conversion
The library could automatically convert string OID values to OID lists during encoding, but this requires knowledge of OID mappings.

### Option 3: Documentation
At minimum, clearly document the expected value formats for each varbind type.

## Current Workaround
We've implemented varbind normalization in our application before calling the snmp_lib functions:

```elixir
defp normalize_varbind_value(:object_identifier, value) when is_binary(value) do
  # Convert string OID to OID list
  parse_oid_string(value)
end

defp normalize_varbind_value(:end_of_mib_view, {:end_of_mib_view, nil}), do: nil
defp normalize_varbind_value(:end_of_mib_view, _), do: nil
defp normalize_varbind_value(_type, value), do: value
```

## Impact
This bug causes silent data corruption in SNMP applications, where varbinds are encoded successfully but decoded with incorrect types and values. This can lead to:
- Failed SNMP operations
- Incorrect network monitoring data
- Difficult-to-debug integration issues

## Additional Notes
- Other varbind types (`:octet_string`, `:integer`, `:timeticks`, `:gauge32`, `:counter32`) work correctly
- The issue is consistent across different SNMP versions (v1, v2c)
- The library's encoding succeeds, making this a particularly subtle bug
