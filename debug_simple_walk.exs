# Simple debug to test walk issue
alias SnmpSim.Device.OidHandler

# Test the problematic function directly
oid = [1, 3, 6, 1, 2, 1, 1, 1, 0]  # sysDescr.0
device_type = :cable_modem

# Create a minimal state with walk data
{:ok, oid_map} = SnmpSim.WalkParser.parse_walk_file("priv/walks/cable_modem.walk")
state = %{
  device_type: device_type,
  oid_map: oid_map,
  last_access: System.monotonic_time(:millisecond)
}

IO.puts("Testing get_next_oid_value...")
IO.puts("Input OID: #{inspect(oid)}")
IO.puts("Device type: #{inspect(device_type)}")

# Debug the known OIDs
known_oids = OidHandler.get_known_oids(device_type)
IO.puts("Known OIDs count: #{length(known_oids)}")
IO.puts("First few known OIDs: #{inspect(Enum.take(known_oids, 5))}")

# Test find_next_oid directly
oid_strings = Enum.map(known_oids, &OidHandler.oid_to_string/1)
current_oid_string = OidHandler.oid_to_string(oid)
IO.puts("Current OID string: #{current_oid_string}")

# Test the function
result = OidHandler.get_next_oid_value(device_type, oid, state)
IO.puts("Result: #{inspect(result)}")

case result do
  {:ok, {next_oid, type, value}} ->
    IO.puts("\nDebugging result:")
    IO.puts("next_oid: #{inspect(next_oid)} (is_list: #{is_list(next_oid)})")
    IO.puts("type: #{inspect(type)}")
    IO.puts("value: #{inspect(value)}")
    
  other ->
    IO.puts("Unexpected result: #{inspect(other)}")
end
