#!/usr/bin/env elixir

# Debug the last OID issue

# Start the application
Application.ensure_all_started(:snmp_sim)

# Load a profile
profile_path = "priv/walks/cable_modem_oids.walk"
{:ok, profile_data, behavior_data} = SnmpSim.ProfileLoader.load_profile(:cable_modem, {:walk_file, profile_path})

# Store the profile
device_type = "cable_modem"
:ok = SnmpSim.MIB.SharedProfiles.store_profile(device_type, profile_data, behavior_data)

IO.puts("Profile loaded with #{length(profile_data)} OIDs")

# Get all OIDs and sort them
all_oids = Enum.map(profile_data, fn {oid, _data} -> oid end) |> Enum.sort(&SnmpSim.MIB.SharedProfiles.compare_oids_lexicographically/2)

IO.puts("First 5 OIDs:")
Enum.take(all_oids, 5) |> Enum.each(&IO.puts("  #{&1}"))

IO.puts("Last 5 OIDs:")
Enum.take(all_oids, -5) |> Enum.each(&IO.puts("  #{&1}"))

last_oid = List.last(all_oids)
IO.puts("\nLast OID in walk file: #{last_oid}")

# Test get_next_oid on the last OID
IO.puts("\n=== Testing get_next_oid on last OID ===")
result = SnmpSim.MIB.SharedProfiles.get_next_oid(device_type, last_oid)
IO.puts("get_next_oid(\"#{last_oid}\") = #{inspect(result)}")

# Test get_next_oid on the second-to-last OID
if length(all_oids) > 1 do
  second_last_oid = Enum.at(all_oids, -2)
  IO.puts("\nSecond-to-last OID: #{second_last_oid}")
  result2 = SnmpSim.MIB.SharedProfiles.get_next_oid(device_type, second_last_oid)
  IO.puts("get_next_oid(\"#{second_last_oid}\") = #{inspect(result2)}")
end

# Find the problematic OID "21.1"
problematic_oid = "21.1"
IO.puts("\n=== Testing problematic OID: #{problematic_oid} ===")

# Check if it exists in the profile
if problematic_oid in all_oids do
  IO.puts("✅ #{problematic_oid} exists in walk file")
  
  # Find its position
  index = Enum.find_index(all_oids, &(&1 == problematic_oid))
  IO.puts("Position: #{index + 1} of #{length(all_oids)}")
  
  # Test get_next_oid on it
  result3 = SnmpSim.MIB.SharedProfiles.get_next_oid(device_type, problematic_oid)
  IO.puts("get_next_oid(\"#{problematic_oid}\") = #{inspect(result3)}")
  
  # Check what comes after it
  if index < length(all_oids) - 1 do
    next_in_list = Enum.at(all_oids, index + 1)
    IO.puts("Next OID in sorted list: #{next_in_list}")
  else
    IO.puts("This is the last OID in the sorted list")
  end
else
  IO.puts("❌ #{problematic_oid} does NOT exist in walk file")
  
  # Check if there's a similar OID
  similar_oids = Enum.filter(all_oids, &String.contains?(&1, "21.1"))
  IO.puts("Similar OIDs containing '21.1':")
  Enum.each(similar_oids, &IO.puts("  #{&1}"))
end
