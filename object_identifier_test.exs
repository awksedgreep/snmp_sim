# Object Identifier Test Case for SnmpLib Development
# Run with: mix run object_identifier_test.exs

IO.puts("=== Object Identifier Encoding/Decoding Test ===")
IO.puts("")

# Test the failing case
test_value = {:object_identifier, "1.3.6.1.2.1.1.1.0"}
IO.puts("Original value: #{inspect(test_value)}")
IO.puts("")

# Create a PDU with the object identifier
pdu = SnmpLib.PDU.build_response(12345, 0, 0, [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :auto, test_value}])
IO.puts("PDU created: #{inspect(pdu)}")
IO.puts("")

# Create message
message = SnmpLib.PDU.build_message(pdu, "public", :v2c)
IO.puts("Message created: #{inspect(message)}")
IO.puts("")

# Encode the message
case SnmpLib.PDU.encode_message(message) do
  {:ok, encoded} ->
    IO.puts("✓ Encoding successful (#{byte_size(encoded)} bytes)")
    IO.puts("Encoded bytes: #{inspect(encoded, limit: :infinity)}")
    IO.puts("")
    
    # Decode the message
    case SnmpLib.PDU.decode_message(encoded) do
      {:ok, decoded} ->
        IO.puts("✓ Decoding successful")
        IO.puts("Decoded message: #{inspect(decoded, limit: :infinity)}")
        IO.puts("")
        
        # Extract the value from varbinds
        [{_oid, _type, decoded_value}] = decoded.pdu.varbinds
        IO.puts("Extracted value: #{inspect(decoded_value)}")
        IO.puts("")
        
        # Check if it matches
        if decoded_value == test_value do
          IO.puts("✅ SUCCESS: Value preserved correctly!")
        else
          IO.puts("❌ FAILURE: Value changed")
          IO.puts("  Original: #{inspect(test_value)}")
          IO.puts("  Decoded:  #{inspect(decoded_value)}")
          IO.puts("")
          IO.puts("🔍 ANALYSIS:")
          IO.puts("  - The object_identifier value becomes :null during decoding")
          IO.puts("  - This suggests an issue in the ASN.1 BER decoding path")
          IO.puts("  - The encoding appears to work (no errors)")
          IO.puts("  - The problem is in the decode_message -> parse_value path")
        end
        
      {:error, reason} ->
        IO.puts("❌ Decode failed: #{inspect(reason)}")
    end
    
  {:error, reason} ->
    IO.puts("❌ Encode failed: #{inspect(reason)}")
end

IO.puts("")
IO.puts("=== Additional Test Cases ===")

# Test other object identifier formats
test_cases = [
  {:object_identifier, "1.3.6.1.2.1.1.1.0"},
  {:object_identifier, "1.3.6.1.2.1.1.2.0"},
  {:object_identifier, "1.3.6.1.4.1.12345.1.1.0"},
  {:object_identifier, [1, 3, 6, 1, 2, 1, 1, 1, 0]}  # List format
]

for {idx, test_val} <- Enum.with_index(test_cases, 1) do
  IO.puts("Test #{idx}: #{inspect(test_val)}")
  
  pdu = SnmpLib.PDU.build_response(12345 + idx, 0, 0, [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :auto, test_val}])
  message = SnmpLib.PDU.build_message(pdu, "public", :v2c)
  
  case SnmpLib.PDU.encode_message(message) do
    {:ok, encoded} ->
      case SnmpLib.PDU.decode_message(encoded) do
        {:ok, decoded} ->
          [{_oid, _type, decoded_value}] = decoded.pdu.varbinds
          if decoded_value == test_val do
            IO.puts("  ✅ PASS")
          else
            IO.puts("  ❌ FAIL: #{inspect(test_val)} → #{inspect(decoded_value)}")
          end
        {:error, reason} ->
          IO.puts("  ❌ DECODE ERROR: #{inspect(reason)}")
      end
    {:error, reason} ->
      IO.puts("  ❌ ENCODE ERROR: #{inspect(reason)}")
  end
end

IO.puts("")
IO.puts("=== Debugging Information ===")
IO.puts("SnmpLib version: 0.1.3")
IO.puts("Issue: object_identifier values become :null during decoding")
IO.puts("Working types: counter32, gauge32, timeticks, counter64, strings, integers")
IO.puts("Failing type: object_identifier")
IO.puts("")
IO.puts("Likely cause:")
IO.puts("- The PDU decode path in SnmpLib.PDU.parse_value/1")
IO.puts("- ASN.1 BER object identifier decoding logic")
IO.puts("- Missing or incorrect pattern matching for OID tag (@object_identifier = 0x06)")