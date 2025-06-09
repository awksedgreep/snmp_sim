# Debug get_oid_value to see what it returns
alias SnmpSim.Device.OidHandler

# Create a minimal state with walk data
{:ok, oid_map} = SnmpSim.WalkParser.parse_walk_file("priv/walks/cable_modem.walk")
state = %{
  device_type: :cable_modem,
  oid_map: oid_map,
  last_access: System.monotonic_time(:millisecond)
}

# Test a specific OID from the walk file
test_oid = [1, 3, 6, 1, 2, 1, 1, 1, 0]  # sysDescr.0

IO.puts("Testing get_oid_value...")
IO.puts("Input OID: #{inspect(test_oid)}")
IO.puts("OID as string: #{OidHandler.oid_to_string(test_oid)}")

result = OidHandler.get_oid_value(test_oid, state)
IO.puts("get_oid_value result: #{inspect(result)}")

# Also test with a few OIDs from the map
IO.puts("\nFirst few OIDs in oid_map:")
oid_map
|> Enum.take(5)
|> Enum.each(fn {oid, value} ->
  IO.puts("OID: #{inspect(oid)} -> Value: #{inspect(value)}")
  
  # Test get_oid_value on this OID (as string)
  result = OidHandler.get_oid_value(oid, state)
  IO.puts("  get_oid_value(string) result: #{inspect(result)}")
  
  # Test get_oid_value on this OID (as list)
  oid_list = OidHandler.string_to_oid_list(oid)
  result2 = OidHandler.get_oid_value(oid_list, state)
  IO.puts("  get_oid_value(list) result: #{inspect(result2)}")
  IO.puts("  OID list: #{inspect(oid_list)}")
  IO.puts("  OID list as string: #{OidHandler.oid_to_string(oid_list)}")
end)
