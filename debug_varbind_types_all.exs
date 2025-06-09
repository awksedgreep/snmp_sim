# Debug script to test different varbind types

test_varbinds = [
  {[1, 3, 6, 1, 2, 1, 1, 1, 0], :octet_string, "Test String"},
  {[1, 3, 6, 1, 2, 1, 1, 2, 0], :object_identifier, "SNMPv2-SMI::enterprises.4491.2.4.1"},
  {[1, 3, 6, 1, 2, 1, 1, 3, 0], :timeticks, 12345},
  {[1, 3, 6, 1, 2, 1, 1, 7, 0], :integer, 42},
  {[1, 3, 6, 1, 2, 1, 2, 1, 0], :gauge32, 1000},
  {[1, 3, 6, 1, 2, 1, 2, 2, 0], :counter32, 5000},
  {[1, 3, 6, 1, 2, 1, 99, 99, 0], :end_of_mib_view, {:end_of_mib_view, nil}}
]

IO.puts("Testing different varbind types:\n")

Enum.each(test_varbinds, fn {oid, type, value} ->
  IO.puts("Testing: OID=#{inspect(oid)}, Type=#{inspect(type)}, Value=#{inspect(value)}")
  
  pdu = %{
    type: :get_response,
    version: 2,
    request_id: 12345,
    varbinds: [{oid, type, value}],
    community: "public",
    error_status: 0,
    error_index: 0
  }
  
  message = SnmpLib.PDU.build_message(pdu, "public", :v2c)
  
  case SnmpLib.PDU.encode_message(message) do
    {:ok, encoded} ->
      case SnmpLib.PDU.decode_message(encoded) do
        {:ok, decoded} ->
          [{decoded_oid, decoded_type, decoded_value}] = decoded.pdu.varbinds
          IO.puts("  Result: OID=#{inspect(decoded_oid)}, Type=#{inspect(decoded_type)}, Value=#{inspect(decoded_value)}")
          
          if decoded_type != type or decoded_value != value do
            IO.puts("  *** MISMATCH! Expected type=#{inspect(type)}, value=#{inspect(value)}")
          else
            IO.puts("  ✓ OK")
          end
          
        {:error, reason} ->
          IO.puts("  *** DECODE ERROR: #{inspect(reason)}")
      end
      
    {:error, reason} ->
      IO.puts("  *** ENCODE ERROR: #{inspect(reason)}")
  end
  
  IO.puts("")
end)
