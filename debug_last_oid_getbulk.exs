#!/usr/bin/env elixir

# Debug GETBULK from the last OID specifically

# Start the application
Application.ensure_all_started(:snmp_sim)

# Load a profile
profile_path = "priv/walks/cable_modem_oids.walk"
{:ok, profile_data, behavior_data} = SnmpSim.ProfileLoader.load_profile(:cable_modem, {:walk_file, profile_path})

# Store the profile
device_type = "cable_modem"
:ok = SnmpSim.MIB.SharedProfiles.store_profile(device_type, profile_data, behavior_data)

# Get the actual last OID
all_oids = Enum.map(profile_data, fn {oid, _data} -> oid end) 
  |> Enum.sort(&SnmpSim.MIB.SharedProfiles.compare_oids_lexicographically/2)

last_oid = List.last(all_oids)
IO.puts("Last OID in walk file: #{last_oid}")

# Test get_next_oid on the last OID
IO.puts("\n=== Testing get_next_oid on last OID ===")
result = SnmpSim.MIB.SharedProfiles.get_next_oid(device_type, last_oid)
IO.puts("get_next_oid(\"#{last_oid}\") = #{inspect(result)}")

# Test GETBULK from the last OID
IO.puts("\n=== Testing GETBULK from last OID ===")
bulk_result = SnmpSim.MIB.SharedProfiles.get_bulk_oids(device_type, last_oid, 5)
IO.puts("get_bulk_oids(\"#{last_oid}\", 5) = #{inspect(bulk_result)}")

case bulk_result do
  {:ok, bulk_oids} ->
    IO.puts("GETBULK returned #{length(bulk_oids)} OIDs:")
    Enum.each(bulk_oids, fn {oid, type, value} ->
      IO.puts("  #{oid} (#{type}) = #{inspect(value)}")
    end)
  {:error, reason} ->
    IO.puts("GETBULK returned error: #{inspect(reason)}")
end

# Test GETBULK from second-to-last OID
if length(all_oids) > 1 do
  second_last_oid = Enum.at(all_oids, -2)
  IO.puts("\n=== Testing GETBULK from second-to-last OID ===")
  IO.puts("Second-to-last OID: #{second_last_oid}")
  
  bulk_result2 = SnmpSim.MIB.SharedProfiles.get_bulk_oids(device_type, second_last_oid, 5)
  IO.puts("get_bulk_oids(\"#{second_last_oid}\", 5) = #{inspect(bulk_result2)}")
  
  case bulk_result2 do
    {:ok, bulk_oids} ->
      IO.puts("GETBULK returned #{length(bulk_oids)} OIDs:")
      Enum.each(bulk_oids, fn {oid, type, value} ->
        IO.puts("  #{oid} (#{type}) = #{inspect(value)}")
      end)
    {:error, reason} ->
      IO.puts("GETBULK returned error: #{inspect(reason)}")
  end
end
