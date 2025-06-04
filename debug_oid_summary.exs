#!/usr/bin/env elixir

Mix.install([
  {:snmp_lib, path: "../snmp_lib"}
])

IO.puts("=== Object Identifier Bug Summary ===")

# The bug: object identifier VALUES become :null during PDU encode/decode
test_oid = [1, 3, 6, 1, 2, 1, 1, 1, 0]

IO.puts("Problem demonstration:")
IO.puts("When an SNMP response contains a value that is an object identifier,")
IO.puts("the SnmpLib.PDU encode/decode process converts it to :null")

IO.puts("\nTest case:")
# Create varbinds where the VALUE should be an object identifier
original_varbinds = [{test_oid, :object_identifier, test_oid}]
IO.puts("Original varbind: #{inspect(hd(original_varbinds))}")

# Build response PDU
pdu = SnmpLib.PDU.build_response(12345, 0, 0, original_varbinds)
message = SnmpLib.PDU.build_message(pdu, "public", :v2c)

# Encode and decode
{:ok, encoded} = SnmpLib.PDU.encode_message(message)
{:ok, decoded} = SnmpLib.PDU.decode_message(encoded)

decoded_varbind = hd(decoded.pdu.varbinds)
IO.puts("Decoded varbind:  #{inspect(decoded_varbind)}")

{_oid, _type, original_value} = hd(original_varbinds)
{_oid, _type, decoded_value} = decoded_varbind

IO.puts("\nValue comparison:")
IO.puts("  Original value: #{inspect(original_value)}")
IO.puts("  Decoded value:  #{inspect(decoded_value)}")

if original_value == decoded_value do
  IO.puts("  ✓ Values match")
else
  IO.puts("  ✗ BUG: Object identifier value became :null!")
end

IO.puts("\n=== Root Cause Analysis ===")
IO.puts("The issue is in SnmpLib.PDU encoding/decoding:")
IO.puts("1. Object identifier VALUES are not being properly encoded as ASN.1 OBJECT IDENTIFIER type")
IO.puts("2. Instead they are being encoded as ASN.1 NULL type") 
IO.puts("3. During decoding, NULL values are converted to :null")
IO.puts("4. This causes {:object_identifier, \"1.3.6.1.2.1.1.1.0\"} to become :null")

IO.puts("\n=== Impact ===")
IO.puts("This bug affects SNMP responses where:")
IO.puts("- The value of an OID is supposed to be another OID")
IO.puts("- Common in MIB tables and object references")
IO.puts("- Results in loss of data in SNMP simulator responses")

IO.puts("\n=== Fix Required ===") 
IO.puts("SnmpLib.PDU needs to properly encode object identifier values as ASN.1 type 0x06")
IO.puts("instead of encoding them as ASN.1 NULL type (0x05)")