# SnmpLib Varbind Encoding Bug Report

## Summary
The SnmpLib library has a critical bug where varbind values in SNMP responses are lost during the encode/decode cycle. This affects both SNMPv1 and SNMPv2c protocols.

## Issue Description
When encoding an SNMP response PDU with actual varbind values and then decoding it:
- The varbind type always becomes `:auto` 
- String values (`:octet_string`) become `:null`
- Other types are partially preserved but wrapped in tuples

## Detailed Analysis

### 1. String Values Are Completely Lost
**Input varbind:**
```elixir
{[1, 3, 6, 1, 2, 1, 1, 1, 0], :octet_string, "Test String"}
```

**After encode/decode:**
```elixir
{[1, 3, 6, 1, 2, 1, 1, 1, 0], :auto, :null}
```

The string value "Test String" is completely lost and replaced with `:null`.

### 2. Non-String Types Are Partially Preserved
For non-string types, the value is preserved but wrapped in a tuple with the type:

**Integer:**
- Input: `{oid, :integer, 42}`
- Output: `{oid, :auto, 42}`

**Counter32:**
- Input: `{oid, :counter32, 999}`
- Output: `{oid, :auto, {:counter32, 999}}`

**Timeticks:**
- Input: `{oid, :timeticks, 123456}`
- Output: `{oid, :auto, {:timeticks, 123456}}`

### 3. The Bug Affects Both v1 and v2c
The same behavior occurs for both SNMP versions:
- v1 (version: 0)
- v2c (version: 1)

### 4. Raw Byte Analysis
Looking at the encoded bytes for a simple response with an octet_string value:

**v1 bytes (hex):**
```
30 28 02 01 00 04 06 70 75 62 6C 69 63 A2 1B 02 03 01 86 9F 02 01 00 02 01 00 30 0E 30 0C 06 08 2B 06 01 02 01 01 01 00 05 00
```

**v2c bytes (hex):**
```
30 28 02 01 01 04 06 70 75 62 6C 69 63 A2 1B 02 03 01 86 9F 02 01 00 02 01 00 30 0E 30 0C 06 08 2B 06 01 02 01 01 01 00 05 00
```

The only difference is the version byte (00 vs 01). Both end with `05 00`, which is a NULL value (tag 0x05, length 0). This suggests the encoder is writing NULL values instead of the actual string values.

## Test Code to Reproduce

```elixir
alias SnmpLib.PDU

# Create a response with a string value
response_pdu = %{
  type: :get_response,
  request_id: 12345,
  varbinds: [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :octet_string, "Test String"}],
  error_status: 0,
  error_index: 0
}

# Build and encode the message
message = PDU.build_message(response_pdu, "public", :v1)
{:ok, encoded} = PDU.encode_message(message)

# Decode it back
{:ok, decoded} = PDU.decode_message(encoded)

# Check the varbinds
IO.inspect(decoded.pdu.varbinds)
# Output: [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :auto, :null}]
# Expected: [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :octet_string, "Test String"}]
```

## Impact
This bug makes it impossible to properly test SNMP simulators or agents that use SnmpLib, as response values cannot be verified after encoding/decoding. The simulator correctly generates responses with proper values, but they are lost during transmission.

## Root Cause Hypothesis
The encoder appears to be:
1. Ignoring the actual varbind values when encoding responses
2. Always encoding NULL (0x05 0x00) for string values
3. Using a different encoding pattern for non-string types that preserves some information

This might be due to:
- The encoder expecting a different varbind format for responses
- A bug in the ASN.1 encoding logic for OCTET STRING types
- The decoder always returning `:auto` type instead of preserving the original type

## Workaround
Currently, there is no workaround within the SnmpLib API. The only options are:
1. Use a different SNMP library
2. Skip tests that verify response values
3. Test at a lower level without encoding/decoding
