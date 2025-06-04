#!/usr/bin/env elixir

# Debug script to understand the object identifier encoding issue

alias SnmpLib.PDU

# Test the specific failing case
test_value = {:object_identifier, "1.3.6.1.2.1.1.1.0"}

IO.puts("=== Testing PDU encoding issue ===")
IO.puts("Original value: #{inspect(test_value)}")

# Create a simple PDU with the test value
pdu = %PDU{
  version: 1,
  community: "public",
  pdu_type: 0xA2,  # GET_RESPONSE
  request_id: 12345,
  error_status: 0,
  error_index: 0,
  variable_bindings: [{"1.3.6.1.2.1.1.2.0", test_value}]
}

IO.puts("PDU variable_bindings: #{inspect(pdu.variable_bindings)}")

# Try to encode it
case PDU.encode(pdu) do
  {:ok, encoded} ->
    IO.puts("Encoding successful, size: #{byte_size(encoded)} bytes")
    
    # Try to decode it back
    case PDU.decode(encoded) do
      {:ok, decoded} ->
        IO.puts("Decoding successful")
        IO.puts("Decoded variable_bindings: #{inspect(decoded.variable_bindings)}")
        
        # Check if the value was preserved
        [{_oid, decoded_value}] = decoded.variable_bindings
        IO.puts("Original: #{inspect(test_value)}")
        IO.puts("Decoded:  #{inspect(decoded_value)}")
        
        if decoded_value == test_value do
          IO.puts("✅ Value preserved correctly!")
        else
          IO.puts("❌ Value was NOT preserved")
          IO.puts("   Expected: #{inspect(test_value)}")
          IO.puts("   Got:      #{inspect(decoded_value)}")
        end
        
      {:error, decode_error} ->
        IO.puts("❌ Decode failed: #{inspect(decode_error)}")
    end
    
  {:error, encode_error} ->
    IO.puts("❌ Encode failed: #{inspect(encode_error)}")
end

IO.puts("\n=== Testing other SNMP types ===")

# Test other types that should work
other_test_values = [
  {"string", "test string"},
  {"integer", 42},
  {"counter32", {:counter32, 123}},
  {"gauge32", {:gauge32, 456}},
  {"timeticks", {:timeticks, 789}}
]

for {description, value} <- other_test_values do
  pdu = %PDU{
    version: 1,
    community: "public",
    pdu_type: 0xA2,
    request_id: 12345,
    error_status: 0,
    error_index: 0,
    variable_bindings: [{"1.3.6.1.2.1.1.1.0", value}]
  }
  
  case PDU.encode(pdu) do
    {:ok, encoded} ->
      case PDU.decode(encoded) do
        {:ok, decoded} ->
          [{_oid, decoded_value}] = decoded.variable_bindings
          if decoded_value == value do
            IO.puts("✅ #{description}: preserved correctly")
          else
            IO.puts("❌ #{description}: #{inspect(value)} -> #{inspect(decoded_value)}")
          end
        {:error, _} ->
          IO.puts("❌ #{description}: decode failed")
      end
    {:error, _} ->
      IO.puts("❌ #{description}: encode failed")
  end
end