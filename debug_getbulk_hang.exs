#!/usr/bin/env elixir

# Debug why GETBULK from 1.3.6.1 still hangs

# Start the application
Application.ensure_all_started(:snmp_sim)

# Load a profile
profile_path = "priv/walks/cable_modem_oids.walk"
{:ok, profile_data, behavior_data} = SnmpSim.ProfileLoader.load_profile(:cable_modem, {:walk_file, profile_path})

# Store the profile
device_type = "cable_modem"
:ok = SnmpSim.MIB.SharedProfiles.store_profile(device_type, profile_data, behavior_data)

IO.puts("Profile loaded with #{length(profile_data)} OIDs")

# Test GETBULK collection step by step
test_oid = "1.3.6.1"
max_repetitions = 10

IO.puts("\n=== Testing GETBULK collection from #{test_oid} ===")

result = SnmpSim.MIB.SharedProfiles.get_bulk_oids(device_type, test_oid, max_repetitions)
IO.puts("get_bulk_oids result: #{inspect(result)}")

case result do
  {:ok, bulk_oids} ->
    IO.puts("✅ Got #{length(bulk_oids)} OIDs from GETBULK")
    
    # Show the first few OIDs
    IO.puts("First 5 OIDs:")
    Enum.take(bulk_oids, 5) |> Enum.with_index() |> Enum.each(fn {{oid, type, value}, index} ->
      IO.puts("  #{index + 1}. #{oid} (#{type}) = #{inspect(value)}")
    end)
    
    # Check if any OIDs are problematic
    problematic_oids = Enum.filter(bulk_oids, fn {oid, _type, _value} ->
      # Check if OID exists in original profile
      not Enum.any?(profile_data, fn {profile_oid, _data} -> profile_oid == oid end)
    end)
    
    if length(problematic_oids) > 0 do
      IO.puts("\n❌ Found #{length(problematic_oids)} OIDs NOT in walk file:")
      Enum.each(problematic_oids, fn {oid, type, value} ->
        IO.puts("  #{oid} (#{type}) = #{inspect(value)}")
      end)
    else
      IO.puts("\n✅ All OIDs exist in walk file")
    end
    
  {:error, reason} ->
    IO.puts("❌ GETBULK failed: #{inspect(reason)}")
end

# Test individual get_next_oid calls to see where it might loop
IO.puts("\n=== Testing sequential get_next_oid calls ===")

current_oid = test_oid
seen_oids = MapSet.new()

Enum.reduce_while(1..20, {current_oid, seen_oids}, fn i, {current_oid, seen_oids} ->
  case SnmpSim.MIB.SharedProfiles.get_next_oid(device_type, current_oid) do
    {:ok, next_oid} ->
      if MapSet.member?(seen_oids, next_oid) do
        IO.puts("#{i}. #{current_oid} -> #{next_oid} ❌ LOOP DETECTED!")
        {:halt, {next_oid, seen_oids}}
      else
        IO.puts("#{i}. #{current_oid} -> #{next_oid}")
        new_seen_oids = MapSet.put(seen_oids, next_oid)
        {:cont, {next_oid, new_seen_oids}}
      end
      
    :end_of_mib ->
      IO.puts("#{i}. #{current_oid} -> :end_of_mib ✅ PROPER TERMINATION")
      {:halt, {current_oid, seen_oids}}
      
    {:error, reason} ->
      IO.puts("#{i}. #{current_oid} -> {:error, #{inspect(reason)}}")
      {:halt, {current_oid, seen_oids}}
  end
end)
