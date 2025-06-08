#!/usr/bin/env elixir

# Debug script to understand bulk walk behavior
Application.ensure_all_started(:snmp_sim)
Process.sleep(1000)

IO.puts("🔍 Debugging SNMP Bulk Walk")
IO.puts("===========================")

# Load the walk profile
device_type = :walk_cable_modem_oids
walk_path = Path.join([File.cwd!(), "priv", "walks", "cable_modem_oids.walk"])

IO.puts("1. Loading walk profile...")
case SnmpSim.MIB.SharedProfiles.load_walk_profile(device_type, walk_path) do
  :ok -> IO.puts("✅ Walk profile loaded")
  {:error, reason} -> 
    IO.puts("❌ Failed to load walk profile: #{inspect(reason)}")
    System.halt(1)
end

IO.puts("\n2. Testing SharedProfiles.get_bulk_oids directly...")

# Test different bulk sizes
test_cases = [
  {"1.3.6.1.2.1", 5},
  {"1.3.6.1.2.1", 10},
  {"1.3.6.1.2.1", 25},
  {"1.3.6.1.2.1", 50}
]

Enum.each(test_cases, fn {start_oid, max_reps} ->
  IO.puts("\nTesting bulk with start_oid=#{start_oid}, max_repetitions=#{max_reps}")
  
  case SnmpSim.MIB.SharedProfiles.get_bulk_oids(device_type, start_oid, max_reps) do
    {:ok, oids} ->
      IO.puts("  ✅ Got #{length(oids)} OIDs")
      if length(oids) > 0 do
        {first_oid, _, _} = hd(oids)
        {last_oid, _, _} = List.last(oids)
        IO.puts("  First: #{first_oid}")
        IO.puts("  Last: #{last_oid}")
      end
    {:error, reason} ->
      IO.puts("  ❌ Error: #{inspect(reason)}")
  end
end)

IO.puts("\n3. Testing Device.get_bulk directly...")
# Create device
{:ok, device_pid} = SnmpSim.Device.start_link(%{
  device_id: "bulk_debug",
  device_type: device_type,
  port: 9998
})

test_cases = [
  {"1.3.6.1.2.1", 5},
  {"1.3.6.1.2.1", 10},
  {"1.3.6.1.2.1", 25}
]

Enum.each(test_cases, fn {start_oid, count} ->
  IO.puts("\nTesting Device.get_bulk with start_oid=#{start_oid}, count=#{count}")
  
  case SnmpSim.Device.get_bulk(device_pid, start_oid, count) do
    {:ok, oids} ->
      IO.puts("  ✅ Got #{length(oids)} OIDs")
      if length(oids) > 0 do
        {first_oid, _} = hd(oids)
        {last_oid, _} = List.last(oids)
        IO.puts("  First: #{first_oid}")
        IO.puts("  Last: #{last_oid}")
      end
    {:error, reason} ->
      IO.puts("  ❌ Error: #{inspect(reason)}")
  end
end)

IO.puts("\n✅ Debug complete")
