#!/usr/bin/env elixir

# Test script to debug SharedProfiles lookup
Application.ensure_all_started(:snmp_sim)
Process.sleep(1000)

IO.puts("🔍 Testing SharedProfiles Lookup")
IO.puts("=================================")

# Load the walk profile
device_type = :walk_cable_modem_oids
walk_path = Path.join([File.cwd!(), "priv", "walks", "cable_modem_oids.walk"])

IO.puts("\n1. Loading walk profile...")
case SnmpSim.MIB.SharedProfiles.load_walk_profile(device_type, walk_path) do
  :ok ->
    IO.puts("✅ Walk profile loaded: #{device_type}")
  {:error, reason} ->
    IO.puts("❌ Failed to load walk profile: #{inspect(reason)}")
    System.halt(1)
end

# Test direct SharedProfiles lookup
IO.puts("\n2. Testing direct SharedProfiles lookup...")

# Create a minimal device state
device_state = %{
  device_id: "test",
  device_type: device_type,
  port: 9999,
  counters: %{},
  gauges: %{},
  status_vars: %{}
}

# Test getting next OID from SharedProfiles
test_oids = [
  "1.3.6.1.2.1",
  "1.3.6.1.2.1.1",
  "1.3.6.1.2.1.2.2.1.10.1"
]

Enum.each(test_oids, fn oid ->
  IO.puts("\nTesting OID: #{oid}")
  
  case SnmpSim.MIB.SharedProfiles.get_next_oid(device_type, oid) do
    {:ok, next_oid} ->
      IO.puts("  ✅ Next OID: #{inspect(next_oid)}")
      
      # Try to get the value
      case SnmpSim.MIB.SharedProfiles.get_oid_value(device_type, next_oid, device_state) do
        {:ok, {type, value}} ->
          IO.puts("  ✅ Value: {#{type}, #{inspect(value)}}")
        {:ok, value} ->
          IO.puts("  ✅ Value (legacy): #{inspect(value)}")
        {:error, reason} ->
          IO.puts("  ❌ Value error: #{inspect(reason)}")
      end
      
    {:error, reason} ->
      IO.puts("  ❌ Next OID error: #{inspect(reason)}")
  end
end)

# Test getting all available profiles
IO.puts("\n3. Testing list_profiles...")
case SnmpSim.MIB.SharedProfiles.list_profiles() do
  profiles when is_list(profiles) ->
    IO.puts("✅ Found #{length(profiles)} profiles in SharedProfiles:")
    Enum.each(profiles, fn profile ->
      IO.puts("  - #{inspect(profile)}")
    end)
  {:error, reason} ->
    IO.puts("❌ list_profiles failed: #{inspect(reason)}")
  other ->
    IO.puts("❌ list_profiles returned unexpected: #{inspect(other)}")
end

IO.puts("\n✅ SharedProfiles test complete")
