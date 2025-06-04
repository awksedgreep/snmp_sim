#!/usr/bin/env elixir

# Test script to verify SnmpLib PDU encoding is now working correctly

IO.puts("=== SnmpLib PDU Encoding Fix Verification ===")
IO.puts("")

# Test all complex SNMP types that should now work
test_cases = [
  {"object identifier", {:object_identifier, "1.3.6.1.2.1.1.1.0"}},
  {"counter32", {:counter32, 12345}},
  {"gauge32", {:gauge32, 67890}},
  {"timeticks", {:timeticks, 54321}},
  {"counter64", {:counter64, 9876543210}},
  {"simple string", "Simple String"},
  {"integer", 42}
]

test_results = Enum.map(test_cases, fn {description, test_value} ->
  IO.puts("Testing #{description}:")
  IO.puts("   Original: #{inspect(test_value)}")
  
  # Create a message using the new SnmpLib API
  pdu = SnmpLib.PDU.build_response(12345, 0, 0, [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :auto, test_value}])
  message = SnmpLib.PDU.build_message(pdu, "public", :v2c)
  
  case SnmpLib.PDU.encode_message(message) do
    {:ok, encoded} ->
      IO.puts("   ✓ Encoding successful (#{byte_size(encoded)} bytes)")
      case SnmpLib.PDU.decode_message(encoded) do
        {:ok, decoded} ->
          [{_oid, _type, decoded_value}] = decoded.pdu.varbinds
          IO.puts("   Decoded:  #{inspect(decoded_value)}")
          if decoded_value == test_value do
            IO.puts("   ✅ Value preserved correctly!")
            {description, :success}
          else
            IO.puts("   ❌ Value changed: #{inspect(test_value)} → #{inspect(decoded_value)}")
            {description, :changed}
          end
        {:error, reason} ->
          IO.puts("   ❌ Decode failed: #{inspect(reason)}")
          {description, :decode_failed}
      end
    {:error, reason} ->
      IO.puts("   ❌ Encode failed: #{inspect(reason)}")
      {description, :encode_failed}
  end
end)

IO.puts("")
IO.puts("=== Test Results Summary ===")

successes = Enum.count(test_results, fn {_, result} -> result == :success end)
total = length(test_results)

IO.puts("#{successes}/#{total} tests passed")

if successes == total do
  IO.puts("🎉 ALL TESTS PASSED! SnmpLib PDU encoding is working correctly.")
else
  IO.puts("❌ Some tests failed:")
  Enum.each(test_results, fn 
    {description, :success} -> 
      IO.puts("  ✅ #{description}")
    {description, result} -> 
      IO.puts("  ❌ #{description}: #{result}")
  end)
end