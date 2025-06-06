#!/usr/bin/env elixir

# Start and keep SNMP simulator running
IO.puts "🚀 Starting SNMP Simulator..."

# Start the application
Application.ensure_all_started(:snmp_sim)

# Wait for startup
Process.sleep(2000)

# Verify devices are running
devices = DynamicSupervisor.which_children(SnmpSim.DeviceSupervisor)
IO.puts "✅ Started #{length(devices)} devices"

# List active ports
Enum.each(devices, fn {_, pid, _, _} ->
  if Process.alive?(pid) do
    try do
      info = GenServer.call(pid, :get_info)
      IO.puts "  📡 Device #{info.device_id} listening on port #{info.port}"
    rescue
      _ -> IO.puts "  📡 Device PID #{inspect(pid)} (info unavailable)"
    end
  end
end)

IO.puts "\n🎯 SNMP Simulator is ready for manual testing!"
IO.puts "   Use Ctrl+C to stop the services"

# Keep the process alive indefinitely
receive do
  _ -> :ok
after
  :infinity -> :ok
end
