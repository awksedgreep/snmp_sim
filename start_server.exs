#!/usr/bin/env elixir

# Start the SNMP simulator and keep it running
Application.ensure_all_started(:snmp_sim)

# Wait for startup
Process.sleep(2000)

# Check running devices
devices = DynamicSupervisor.which_children(SnmpSim.DeviceSupervisor)
IO.puts "✅ Started #{length(devices)} devices"

# List the devices and their ports
Enum.each(devices, fn {_, pid, _, _} ->
  if Process.alive?(pid) do
    try do
      info = GenServer.call(pid, :get_info)
      IO.puts "  - Device #{info.device_id} on port #{info.port}"
    rescue
      _ -> IO.puts "  - Device PID #{inspect(pid)} (info unavailable)"
    end
  end
end)

# Test a device
IO.puts "\n🧪 Testing SNMP communication..."
case System.cmd("snmpget", ["-v1", "-c", "public", "127.0.0.1:30000", "1.3.6.1.2.1.1.1.0"], stderr_to_stdout: true) do
  {output, 0} ->
    IO.puts "✅ SNMP GET successful: #{String.trim(output)}"
  {output, _} ->
    IO.puts "❌ SNMP GET failed: #{String.trim(output)}"
end

IO.puts "\n🚀 SNMP Simulator is running. Press Ctrl+C to stop."

# Keep the process alive
:timer.sleep(:infinity)
