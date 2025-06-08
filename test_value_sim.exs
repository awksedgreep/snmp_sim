#!/usr/bin/env elixir

# Simple test to check ValueSimulator module availability
Mix.install([])

# Change to the project directory
File.cd!("/Users/mcotner/Documents/elixir/snmp_sim")

# Load the project
Code.append_path("_build/dev/lib/snmp_sim/ebin")

# Try to load the module
try do
  Code.ensure_loaded(SnmpSim.ValueSimulator)
  IO.puts("✅ SnmpSim.ValueSimulator module loaded successfully")
  
  # Test the function
  profile_data = %{type: "Counter32", value: 0}
  behavior = {:static_value, %{}}
  device_state = %{}
  
  result = SnmpSim.ValueSimulator.simulate_value(profile_data, behavior, device_state)
  IO.puts("Result: #{inspect(result)}")
  
rescue
  error ->
    IO.puts("❌ Error loading module: #{inspect(error)}")
end
