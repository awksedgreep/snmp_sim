#!/usr/bin/env elixir

# Simple debug script to test SharedProfiles and Device behavior

IO.puts("=== Simple Debug Script ===")

# Start applications
Application.ensure_all_started(:snmp_sim)
Process.sleep(200)

IO.puts("1. Testing SharedProfiles...")

# Load walk profile
result = SnmpSim.MIB.SharedProfiles.load_walk_profile(:cable_modem, "priv/walks/cable_modem.walk")
IO.puts("Walk profile load result: #{inspect(result)}")

# Test getting an OID value
test_oid = "1.3.6.1.2.1.1.1.0"
device_state = %{device_id: "test", device_type: :cable_modem}
value_result = SnmpSim.MIB.SharedProfiles.get_oid_value(:cable_modem, test_oid, device_state)
IO.puts("SharedProfiles OID value for #{test_oid}: #{inspect(value_result)}")

IO.puts("\n2. Testing Device module...")

# Create device
device_config = %{
  port: 19998,
  device_type: :cable_modem,
  device_id: "debug_device",
  community: "public"
}

{:ok, device_pid} = SnmpSim.Device.start_link(device_config)
Process.sleep(100)

# Test Device.get directly
device_get_result = SnmpSim.Device.get(device_pid, test_oid)
IO.puts("Device.get result for #{test_oid}: #{inspect(device_get_result)}")

# Cleanup
SnmpSim.Device.stop(device_pid)

IO.puts("=== Debug Complete ===")