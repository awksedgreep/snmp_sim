#!/usr/bin/env elixir

# Debug SNMP protocol handling to see why bulkwalk hangs

# Start the application
Application.ensure_all_started(:snmp_sim)

# Load a profile
profile_path = "priv/walks/cable_modem_oids.walk"
{:ok, profile_data, behavior_data} = SnmpSim.ProfileLoader.load_profile(:cable_modem, {:walk_file, profile_path})

# Store the profile
device_type = "cable_modem"
:ok = SnmpSim.MIB.SharedProfiles.store_profile(device_type, profile_data, behavior_data)

IO.puts("Profile loaded with #{length(profile_data)} OIDs")

# Simulate what snmpbulkwalk does
# It starts with GETBULK from 1.3.6.1, then continues from the last OID in each response

current_oid = "1.3.6.1"
max_repetitions = 10
iteration = 1

IO.puts("\n=== Simulating SNMP GETBULK walk ===")

# Simulate multiple GETBULK requests like snmpbulkwalk does
Enum.reduce_while(1..100, current_oid, fn i, current_oid ->
  IO.puts("\n--- GETBULK Request #{i} from #{current_oid} ---")
  
  case SnmpSim.MIB.SharedProfiles.get_bulk_oids(device_type, current_oid, max_repetitions) do
    {:ok, bulk_oids} when length(bulk_oids) > 0 ->
      IO.puts("Got #{length(bulk_oids)} OIDs:")
      
      # Show first and last OIDs in this batch
      {first_oid, _, _} = List.first(bulk_oids)
      {last_oid, _, _} = List.last(bulk_oids)
      IO.puts("  First: #{first_oid}")
      IO.puts("  Last:  #{last_oid}")
      
      # Check if we're making progress
      if last_oid == current_oid do
        IO.puts("❌ NO PROGRESS: Last OID same as current OID - this would cause infinite loop!")
        {:halt, current_oid}
      else
        # Continue from the last OID (this is what snmpbulkwalk does)
        {:cont, last_oid}
      end
      
    {:ok, []} ->
      IO.puts("✅ Empty response - end of walk")
      {:halt, current_oid}
      
    {:error, :end_of_mib} ->
      IO.puts("✅ End of MIB reached")
      {:halt, current_oid}
      
    {:error, reason} ->
      IO.puts("❌ Error: #{inspect(reason)}")
      {:halt, current_oid}
  end
end)

IO.puts("\n=== Testing edge case: GETBULK from last few OIDs ===")

# Get the last few OIDs to test edge cases
all_oids = Enum.map(profile_data, fn {oid, _data} -> oid end) 
  |> Enum.sort(&SnmpSim.MIB.SharedProfiles.compare_oids_lexicographically/2)

last_few_oids = Enum.take(all_oids, -5)
IO.puts("Last 5 OIDs in walk file:")
Enum.each(last_few_oids, &IO.puts("  #{&1}"))

# Test GETBULK from each of the last few OIDs
Enum.each(last_few_oids, fn oid ->
  IO.puts("\nGETBULK from #{oid}:")
  case SnmpSim.MIB.SharedProfiles.get_bulk_oids(device_type, oid, 5) do
    {:ok, bulk_oids} ->
      IO.puts("  Got #{length(bulk_oids)} OIDs")
      if length(bulk_oids) > 0 do
        Enum.each(bulk_oids, fn {bulk_oid, _, _} ->
          IO.puts("    #{bulk_oid}")
        end)
      end
    {:error, reason} ->
      IO.puts("  Error: #{inspect(reason)}")
  end
end)
