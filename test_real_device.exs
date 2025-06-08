# Test with a real SNMP device to verify the fix

IO.puts("=== Creating Test SNMP Device ===")

# Create a cable modem device on a unique port
port = 19999
config = %{
  port: port,
  device_type: :cable_modem,
  device_id: "test_cm_#{port}",
  community: "public"
}

case DynamicSupervisor.start_child(SnmpSim.DeviceSupervisor, {SnmpSim.Device, config}) do
  {:ok, device_pid} ->
    IO.puts("✅ Device created successfully on port #{port}")
    IO.puts("Device PID: #{inspect(device_pid)}")
    
    # Wait for device to fully initialize
    Process.sleep(2000)
    
    IO.puts("\n=== Device is ready for SNMP queries ===")
    IO.puts("You can now test with:")
    IO.puts("snmpwalk -v2c -c public localhost:#{port} 1.3.6.1.2.1.2.2.1.13")
    IO.puts("snmpbulkwalk -v2c -c public localhost:#{port} 1.3.6.1.2.1.2.2.1.13")
    
    # Keep the device running for testing
    IO.puts("\nDevice will run for 30 seconds for testing...")
    Process.sleep(30_000)
    
    # Clean up
    DynamicSupervisor.terminate_child(SnmpSim.DeviceSupervisor, device_pid)
    IO.puts("✅ Device stopped")
    
  {:error, reason} ->
    IO.puts("❌ Failed to create device: #{inspect(reason)}")
end
