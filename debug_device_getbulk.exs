#!/usr/bin/env elixir

# Debug the actual device GETBULK behavior

# Start the application
Application.ensure_all_started(:snmp_sim)

# Load a profile
profile_path = "priv/walks/cable_modem_oids.walk"
{:ok, profile_data, behavior_data} = SnmpSim.ProfileLoader.load_profile(:cable_modem, {:walk_file, profile_path})

# Store the profile
device_type = "cable_modem"
:ok = SnmpSim.MIB.SharedProfiles.store_profile(device_type, profile_data, behavior_data)

IO.puts("Profile loaded with #{length(profile_data)} OIDs")

# Start a device
port = 30125
{:ok, device_pid} = SnmpSim.Device.start_link(
  device_type: device_type,
  udp_port: port,
  device_state: %{}
)

IO.puts("Device started on port #{port}")

# Wait a moment for device to initialize
Process.sleep(1000)

# Test if the device type is found in SharedProfiles
IO.puts("\n=== Testing SharedProfiles directly ===")
last_oid = "1.3.6.1.4.1.4491.2.1.30.1.1.1.1.3.1"

case SnmpSim.MIB.SharedProfiles.get_bulk_oids(device_type, last_oid, 5) do
  {:ok, bulk_oids} ->
    IO.puts("✅ SharedProfiles.get_bulk_oids works: #{length(bulk_oids)} OIDs")
  {:error, :device_type_not_found} ->
    IO.puts("❌ Device type not found in SharedProfiles!")
  {:error, reason} ->
    IO.puts("❌ SharedProfiles error: #{inspect(reason)}")
end

# Test a few SNMP requests to see what the device actually returns
IO.puts("\n=== Testing actual SNMP requests ===")

# Test SNMP GET first
IO.puts("Testing SNMP GET...")
get_result = System.cmd("snmpget", ["-v2c", "-c", "public", "127.0.0.1:#{port}", "1.3.6.1.2.1.1.1.0"], stderr_to_stdout: true)
IO.puts("GET result: #{inspect(get_result)}")

# Test SNMP GETNEXT
IO.puts("\nTesting SNMP GETNEXT...")
getnext_result = System.cmd("snmpgetnext", ["-v2c", "-c", "public", "127.0.0.1:#{port}", "1.3.6.1"], stderr_to_stdout: true)
IO.puts("GETNEXT result: #{inspect(getnext_result)}")

# Test SNMP GETBULK with small max-repetitions
IO.puts("\nTesting SNMP GETBULK (small)...")
getbulk_result = System.cmd("snmpbulkget", ["-v2c", "-c", "public", "127.0.0.1:#{port}", "-Cn0", "-Cr2", "1.3.6.1"], stderr_to_stdout: true)
IO.puts("GETBULK result: #{inspect(getbulk_result)}")

# Test SNMP GETBULK from the last OID
IO.puts("\nTesting SNMP GETBULK from last OID...")
getbulk_last_result = System.cmd("snmpbulkget", ["-v2c", "-c", "public", "127.0.0.1:#{port}", "-Cn0", "-Cr2", last_oid], stderr_to_stdout: true)
IO.puts("GETBULK from last OID result: #{inspect(getbulk_last_result)}")

# Clean up
GenServer.stop(device_pid)
IO.puts("\nDevice stopped")
