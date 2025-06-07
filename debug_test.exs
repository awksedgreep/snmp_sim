# Debug script to isolate the :badarg issue in multi_device_startup_test.exs

# Simulate the exact test setup
alias SnmpSim.{MultiDeviceStartup, LazyDevicePool, DeviceDistribution}
alias SnmpSim.TestHelpers.PortHelper

# Helper function to get unique port range for each test using PortHelper
get_port_range = fn test_name, size ->
  # Convert atom test name to string for deterministic hashing
  test_name_str = if is_atom(test_name), do: Atom.to_string(test_name), else: test_name
  PortHelper.get_port_range(test_name_str, size)
end

# Simulate test setup
test_name = "test startup status and monitoring provides startup status information"

IO.puts("=== Starting test setup ===")

# Ensure clean state for each test
if Process.whereis(LazyDevicePool) do
  IO.puts("LazyDevicePool already running, shutting down devices...")
  LazyDevicePool.shutdown_all_devices()
else
  IO.puts("Starting LazyDevicePool...")
  {:ok, _} = LazyDevicePool.start_link()
end

# Reset to default port assignments - use the correct module
IO.puts("Getting default assignments...")
default_assignments = DeviceDistribution.default_port_assignments()
IO.inspect(default_assignments, label: "Default assignments")

IO.puts("Configuring port assignments...")
LazyDevicePool.configure_port_assignments(default_assignments)

# Provide unique port range for this test
IO.puts("Getting port range...")
port_range = get_port_range.(test_name, 20)
IO.inspect(port_range, label: "Port range")

IO.puts("=== Test setup complete ===")

# Now simulate the actual test
IO.puts("=== Starting test ===")

# Start some devices first
device_specs = [
  {:cable_modem, 2}
]

IO.puts("Calling start_device_population...")
result = MultiDeviceStartup.start_device_population(
  device_specs,
  port_range: port_range
)

IO.inspect(result, label: "start_device_population result")

case result do
  {:ok, _} ->
    IO.puts("start_device_population succeeded, calling get_startup_status...")
    status = MultiDeviceStartup.get_startup_status()
    IO.inspect(status, label: "Startup status")
    
  {:error, reason} ->
    IO.puts("start_device_population failed: #{inspect(reason)}")
end

IO.puts("=== Test complete ===")
