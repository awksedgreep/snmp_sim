#!/usr/bin/env elixir

# Debug script to understand why broad walks hang

# Start the application
Application.ensure_all_started(:snmp_sim)

# Load a profile
profile_path = "priv/walks/cable_modem_oids.walk"
{:ok, profile_data, behavior_data} = SnmpSim.ProfileLoader.load_profile(:cable_modem, {:walk_file, profile_path})

# Store the profile
device_type = "cable_modem"
:ok = SnmpSim.MIB.SharedProfiles.store_profile(device_type, profile_data, behavior_data)

IO.puts("Profile loaded with #{length(profile_data)} OIDs")

# Test what happens when we walk from broad OIDs
test_oids = [
  "1.3.6.1",           # Very broad - this hangs
  "1.3.6.1.2",         # Still broad
  "1.3.6.1.2.1",       # More specific
  "1.3.6.1.2.1.1",     # System group
  "1.3.6.1.2.1.2",     # Interface group
]

IO.puts("\n=== Testing get_next_oid from broad OIDs ===")
for oid <- test_oids do
  IO.puts("\nTesting from OID: #{oid}")
  
  # Test the first few next OIDs to see the progression
  Enum.reduce_while(1..5, oid, fn i, current_oid ->
    case SnmpSim.MIB.SharedProfiles.get_next_oid(device_type, current_oid) do
      {:ok, next_oid} -> 
        IO.puts("  #{i}. #{current_oid} -> #{next_oid}")
        {:cont, next_oid}
      :end_of_mib -> 
        IO.puts("  #{i}. #{current_oid} -> END_OF_MIB")
        {:halt, current_oid}
      {:error, reason} -> 
        IO.puts("  #{i}. #{current_oid} -> ERROR: #{reason}")
        {:halt, current_oid}
    end
  end)
end

IO.puts("\n=== Testing GETBULK from broad OID (limited) ===")
start_oid = "1.3.6.1"
max_repetitions = 10  # Limit to avoid hanging

case SnmpSim.MIB.SharedProfiles.get_bulk_oids(device_type, start_oid, max_repetitions) do
  {:ok, varbinds} ->
    IO.puts("GETBULK from #{start_oid} returned #{length(varbinds)} varbinds:")
    Enum.each(varbinds, fn {oid, type, value} ->
      IO.puts("  #{oid} = #{type}: #{inspect(value)}")
    end)
  {:error, reason} ->
    IO.puts("GETBULK failed: #{reason}")
end

IO.puts("\n=== Check what OIDs are actually in the profile ===")
# Get first and last few OIDs from the profile
sorted_oids = profile_data
  |> Enum.map(fn {oid, _data} -> oid end)
  |> Enum.sort()

IO.puts("First 5 OIDs in profile:")
Enum.take(sorted_oids, 5) |> Enum.each(&IO.puts("  #{&1}"))

IO.puts("Last 5 OIDs in profile:")
Enum.take(sorted_oids, -5) |> Enum.each(&IO.puts("  #{&1}"))

IO.puts("Total OIDs in profile: #{length(sorted_oids)}")
