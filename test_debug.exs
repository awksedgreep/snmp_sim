#!/usr/bin/env elixir

# Debug script to test MultiDeviceStartup functionality
Mix.install([])

Code.require_file("test/test_helper.exs")

alias SnmpSim.{MultiDeviceStartup, LazyDevicePool}
alias SnmpSim.TestHelpers.PortHelper

# Start the application
{:ok, _} = Application.ensure_all_started(:snmp_sim)

# Ensure LazyDevicePool is running
if Process.whereis(LazyDevicePool) do
  LazyDevicePool.shutdown_all_devices()
else
  {:ok, _} = LazyDevicePool.start_link()
end

# Test the port helper
IO.puts("Testing PortHelper...")
port_range = PortHelper.get_port_range("test_tracks_startup_progress_with_callback", 20)
IO.inspect(port_range, label: "Port range")

# Test basic MultiDeviceStartup without Task.async
IO.puts("\nTesting MultiDeviceStartup directly...")
device_specs = [{:cable_modem, 3}]

try do
  result = MultiDeviceStartup.start_device_population(
    device_specs,
    port_range: port_range
  )
  IO.inspect(result, label: "Direct result")
rescue
  e -> 
    IO.inspect(e, label: "Direct error")
    IO.inspect(__STACKTRACE__, label: "Direct stacktrace")
end

# Test with progress callback
IO.puts("\nTesting with progress callback...")
test_pid = self()
progress_callback = fn progress ->
  send(test_pid, {:progress, progress})
end

try do
  result = MultiDeviceStartup.start_device_population(
    device_specs,
    port_range: port_range,
    progress_callback: progress_callback
  )
  IO.inspect(result, label: "With callback result")
rescue
  e -> 
    IO.inspect(e, label: "With callback error")
    IO.inspect(__STACKTRACE__, label: "With callback stacktrace")
end

# Test with Task.async
IO.puts("\nTesting with Task.async...")
try do
  task = Task.async(fn ->
    MultiDeviceStartup.start_device_population(
      device_specs,
      port_range: port_range,
      progress_callback: progress_callback
    )
  end)
  
  result = Task.await(task, 10_000)
  IO.inspect(result, label: "Task result")
rescue
  e -> 
    IO.inspect(e, label: "Task error")
    IO.inspect(__STACKTRACE__, label: "Task stacktrace")
end

IO.puts("\nDebug complete.")
