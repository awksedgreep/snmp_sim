#!/usr/bin/env elixir

# Test script to debug end-of-MIB detection in GETBULK operations

# Start the application
Application.ensure_all_started(:snmp_sim)

# Load a profile
profile_path = "priv/walks/cable_modem_oids.walk"
{:ok, profile_data, behavior_data} = SnmpSim.ProfileLoader.load_profile(:cable_modem, {:walk_file, profile_path})

# Store the profile
device_type = "cable_modem"
:ok = SnmpSim.MIB.SharedProfiles.store_profile(device_type, profile_data, behavior_data)

IO.puts("Profile loaded with #{length(profile_data)} OIDs")

# Test the last few OIDs in the walk
test_oids = [
  "1.3.6.1.2.1.2.2.1.20.2",  # This should be the last OID in the walk
  "1.3.6.1.2.1.2.2.1.21.1",  # This is missing from the walk
  "1.3.6.1.2.1.2.2.1.21.2",  # This should be the actual last OID
  "1.3.6.1.2.1.2.2.1.21.3",  # This should be beyond end of MIB
  "1.3.6.1.2.1.2.2.1.22.1"   # This should definitely be beyond end of MIB
]

IO.puts("\n=== Testing get_next_oid for end-of-MIB detection ===")
for oid <- test_oids do
  case SnmpSim.MIB.SharedProfiles.get_next_oid(device_type, oid) do
    {:ok, next_oid} -> 
      IO.puts("#{oid} -> #{next_oid}")
    :end_of_mib -> 
      IO.puts("#{oid} -> END_OF_MIB")
    {:error, reason} -> 
      IO.puts("#{oid} -> ERROR: #{reason}")
  end
end

IO.puts("\n=== Testing GETBULK from near end of MIB ===")
start_oid = "1.3.6.1.2.1.2.2.1.20.1"
max_repetitions = 10

case SnmpSim.MIB.SharedProfiles.get_bulk_oids(device_type, start_oid, max_repetitions) do
  {:ok, varbinds} ->
    IO.puts("GETBULK from #{start_oid} returned #{length(varbinds)} varbinds:")
    Enum.each(varbinds, fn {oid, type, value} ->
      IO.puts("  #{oid} = #{type}: #{inspect(value)}")
    end)
  {:error, reason} ->
    IO.puts("GETBULK failed: #{reason}")
end

IO.puts("\n=== Testing GETBULK from actual last OID ===")
start_oid = "1.3.6.1.2.1.2.2.1.21.2"

case SnmpSim.MIB.SharedProfiles.get_bulk_oids(device_type, start_oid, max_repetitions) do
  {:ok, varbinds} ->
    IO.puts("GETBULK from #{start_oid} returned #{length(varbinds)} varbinds:")
    Enum.each(varbinds, fn {oid, type, value} ->
      IO.puts("  #{oid} = #{type}: #{inspect(value)}")
    end)
  {:error, reason} ->
    IO.puts("GETBULK failed: #{reason}")
end
