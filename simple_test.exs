#!/usr/bin/env elixir

# Simple test to reproduce the EXACT problem
Application.ensure_all_started(:snmp_sim)

# Wait for LazyDevicePool to start
Process.sleep(3000)

# Check if LazyDevicePool is running
case Process.whereis(SnmpSim.LazyDevicePool) do
  nil -> 
    IO.puts("❌ LazyDevicePool is not running!")
    System.halt(1)
  pid -> 
    IO.puts("✅ LazyDevicePool is running: #{inspect(pid)}")
end

# Start a device on port 30001 (known working range)
{:ok, _device_pid} = SnmpSim.LazyDevicePool.get_or_create_device(30001)
Process.sleep(2000)

IO.puts("=== Testing SNMP bulk walk on port 30001 ===")
{output, exit_code} = System.cmd("snmpbulkwalk", ["-v2c", "-c", "public", "localhost:30001", "1.3.6.1"], stderr_to_stdout: true)
IO.puts("Exit code: #{exit_code}")
IO.puts("Output:")
IO.puts(String.trim(output))

if String.contains?(output, "No more variables left in this MIB View") do
  IO.puts("\n❌ PROBLEM REPRODUCED! The bulk walk is failing!")
else
  IO.puts("\n✅ Bulk walk working correctly")
end

SnmpSim.LazyDevicePool.stop_device(30001)
