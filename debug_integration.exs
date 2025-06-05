#!/usr/bin/env elixir

# Debug integration test issue
Mix.install([])

Application.put_env(:snmp_sim_ex, :application, [])
Application.put_env(:snmp_lib, :application, [])

# Start the applications
Application.ensure_all_started(:snmp_lib)
Application.ensure_all_started(:snmp_sim_ex)

# Initialize SharedProfiles
IO.puts("=== Starting SharedProfiles ===")
{:ok, _} = SnmpSim.MIB.SharedProfiles.start_link()
:ok = SnmpSim.MIB.SharedProfiles.init_profiles()

IO.puts("=== Loading walk profile ===")
case SnmpSim.MIB.SharedProfiles.load_walk_profile(
  :cable_modem,
  "priv/walks/cable_modem.walk"
) do
  :ok ->
    IO.puts("✅ Walk profile loaded successfully")
  {:error, reason} ->
    IO.puts("❌ Failed to load walk profile: #{inspect(reason)}")
    exit(:failed)
end

IO.puts("=== Testing SharedProfiles.get_oid_value ===")
device_state = %{device_id: "test", uptime: 3600}
test_oid = "1.3.6.1.2.1.1.1.0"

case SnmpSim.MIB.SharedProfiles.get_oid_value(:cable_modem, test_oid, device_state) do
  {:ok, value} ->
    IO.puts("✅ Got value from SharedProfiles: #{inspect(value)}")
  {:error, reason} ->
    IO.puts("❌ Error from SharedProfiles: #{inspect(reason)}")
end

IO.puts("=== Checking profiles list ===")
profiles = SnmpSim.MIB.SharedProfiles.list_profiles()
IO.puts("Available profiles: #{inspect(profiles)}")

IO.puts("=== Testing with device type not found ===")
case SnmpSim.MIB.SharedProfiles.get_oid_value(:nonexistent, test_oid, device_state) do
  {:ok, value} ->
    IO.puts("Unexpected success: #{inspect(value)}")
  {:error, reason} ->
    IO.puts("Expected error for nonexistent device type: #{inspect(reason)}")
end

IO.puts("=== Testing with invalid OID ===")
case SnmpSim.MIB.SharedProfiles.get_oid_value(:cable_modem, "9.9.9.9.9.9", device_state) do
  {:ok, value} ->
    IO.puts("Unexpected success for invalid OID: #{inspect(value)}")
  {:error, reason} ->
    IO.puts("Expected error for invalid OID: #{inspect(reason)}")
end