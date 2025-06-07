#!/usr/bin/env elixir

# Simple test to reproduce the EXACT bulk walk problem with a single device
Application.ensure_all_started(:snmp_sim)

# Start a single device directly
device_config = %{
  device_id: "test_device",
  device_type: :cable_modem,
  port: 10001,
  community: "public",
  walk_file: "priv/walks/cable_modem.walk"
}

IO.puts("=== Starting single device on port 10001 ===")
{:ok, device_pid} = SnmpSim.Device.start_link(device_config)
IO.puts("✅ Device started: #{inspect(device_pid)}")

# Wait for device to initialize
Process.sleep(3000)

IO.puts("\n=== Testing SNMP bulk walk - the EXACT failing command ===")
IO.puts("Command: snmpbulkwalk -v2c -c public localhost:10001 1.3.6.1")

{output, exit_code} = System.cmd("snmpbulkwalk", ["-v2c", "-c", "public", "localhost:10001", "1.3.6.1"], stderr_to_stdout: true)

IO.puts("Exit code: #{exit_code}")
IO.puts("Output:")
IO.puts(String.trim(output))

cond do
  String.contains?(output, "No more variables left in this MIB View") ->
    IO.puts("\n❌ PROBLEM REPRODUCED! The bulk walk is failing!")
    IO.puts("This is the exact issue you reported!")
  String.contains?(output, "Timeout") or String.contains?(output, "No response") ->
    IO.puts("\n⚠️  Device not responding")
  true ->
    IO.puts("\n✅ Bulk walk working correctly")
end

# Also test a simple GET to make sure the device is responding
IO.puts("\n=== Testing simple SNMP GET ===")
{get_output, get_exit} = System.cmd("snmpget", ["-v2c", "-c", "public", "localhost:10001", "1.3.6.1.2.1.1.1.0"], stderr_to_stdout: true)
IO.puts("GET Exit code: #{get_exit}")
IO.puts("GET Output: #{String.trim(get_output)}")

# Clean up
SnmpSim.Device.stop(device_pid)
IO.puts("\n✅ Device stopped")
