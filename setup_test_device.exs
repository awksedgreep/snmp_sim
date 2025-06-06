# Stop all existing devices first
Sim.stop_all()

# Wait a moment for cleanup
Process.sleep(1000)

# Create a simple cable modem on port 10001  
{:ok, device_pid} = Sim.create_cable_modem(10001)

# Show what devices we have
IO.puts("\n=== Current Devices ===")
Sim.list_devices()

IO.puts("\n✅ Test device ready!")
IO.puts("Port: 10001")
IO.puts("Community: public")
IO.puts("Device PID: #{inspect(device_pid)}")
IO.puts("\nTest commands:")
IO.puts("  snmpbulkwalk -v2c -c public localhost:10001 1.3.6.1")
IO.puts("  snmpwalk -v1 -c public localhost:10001 1.3.6.1.2.1.1")
IO.puts("  snmpget -v1 -c public localhost:10001 1.3.6.1.2.1.1.1.0")
