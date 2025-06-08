#!/usr/bin/env elixir

# Debug script to test value simulation for specific OIDs that return NULL

# Start the application to load modules
Application.ensure_all_started(:snmp_sim)

# Test specific OID that should return Counter32: 0
test_oid = "1.3.6.1.2.1.2.2.1.13.1"  # This should be Counter32: 0 from walk file

# Create test profile data as it would be parsed from walk file
profile_data = %{
  type: "Counter32",
  value: 0
}

# Test static value behavior (no simulation)
static_behavior = {:static_value, %{}}

# Test device state
device_state = %{
  device_id: "test_cm_001",
  uptime: 3600,
  interface_utilization: 0.3
}

IO.puts("=== Testing Value Simulation ===")
IO.puts("OID: #{test_oid}")
IO.puts("Profile Data: #{inspect(profile_data)}")
IO.puts("Behavior: #{inspect(static_behavior)}")
IO.puts("")

# Test the ValueSimulator directly
result = SnmpSim.ValueSimulator.simulate_value(profile_data, static_behavior, device_state)
IO.puts("ValueSimulator result: #{inspect(result)}")

# Test type conversion
atom_type = case profile_data.type do
  type when is_binary(type) ->
    case String.upcase(type) do
      "COUNTER32" -> :counter32
      "COUNTER64" -> :counter64
      "GAUGE32" -> :gauge32
      "STRING" -> :octet_string
      "INTEGER" -> :integer
      _ -> String.to_atom(String.downcase(type))
    end
  type when is_atom(type) -> type
end

IO.puts("Converted type: #{inspect(atom_type)}")
IO.puts("Expected final result: #{inspect({atom_type, result})}")
IO.puts("")

# Test with different values to see the pattern
test_cases = [
  %{type: "Counter32", value: 0},
  %{type: "Counter32", value: 1234567890},
  %{type: "Gauge32", value: 0},
  %{type: "Gauge32", value: 1000000000},
  %{type: "STRING", value: "test string"},
  %{type: "INTEGER", value: 42}
]

IO.puts("=== Testing Multiple Cases ===")
for test_case <- test_cases do
  result = SnmpSim.ValueSimulator.simulate_value(test_case, static_behavior, device_state)
  IO.puts("#{test_case.type}:#{test_case.value} -> #{inspect(result)}")
end
