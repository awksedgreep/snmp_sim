#!/usr/bin/env elixir

# Debug script to test SharedProfiles
Mix.install([])

Code.compile_file("lib/snmp_sim_ex/walk_parser.ex")
Code.compile_file("lib/snmp_sim_ex/mib/shared_profiles.ex")
Code.compile_file("lib/snmp_sim_ex/value_simulator.ex")

# Test loading walk file directly
IO.puts("=== Testing Walk Parser ===")
case SnmpSim.WalkParser.parse_walk_file("priv/walks/cable_modem.walk") do
  {:ok, oid_map} ->
    IO.puts("Successfully parsed walk file")
    IO.puts("Total OIDs: #{map_size(oid_map)}")
    
    # Show the first few entries
    oid_map
    |> Enum.take(5)
    |> Enum.each(fn {oid, data} ->
      IO.puts("OID: #{oid} -> #{inspect(data)}")
    end)
    
    # Check specifically for sysDescr
    case Map.get(oid_map, "1.3.6.1.2.1.1.1.0") do
      nil ->
        IO.puts("\n❌ sysDescr (1.3.6.1.2.1.1.1.0) NOT FOUND in walk file")
      data ->
        IO.puts("\n✅ sysDescr found: #{inspect(data)}")
    end
    
  {:error, reason} ->
    IO.puts("❌ Failed to parse walk file: #{inspect(reason)}")
end

IO.puts("\n=== Testing SharedProfiles (if running) ===")

try do
  # Check if SharedProfiles is running
  case GenServer.whereis(SnmpSim.MIB.SharedProfiles) do
    nil ->
      IO.puts("SharedProfiles not running - this is expected in script mode")
    pid ->
      IO.puts("SharedProfiles is running at #{inspect(pid)}")
      
      # Try to get a value
      device_state = %{device_id: "test", uptime: 3600}
      case SnmpSim.MIB.SharedProfiles.get_oid_value(:cable_modem, "1.3.6.1.2.1.1.1.0", device_state) do
        {:ok, value} ->
          IO.puts("✅ Got value from SharedProfiles: #{inspect(value)}")
        {:error, reason} ->
          IO.puts("❌ Error from SharedProfiles: #{inspect(reason)}")
      end
  end
rescue
  e ->
    IO.puts("Error testing SharedProfiles: #{inspect(e)}")
end