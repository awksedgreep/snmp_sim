#!/usr/bin/env elixir

# Test script to create a real SNMP device and test the end-of-MIB fix

# Start the application
Application.ensure_all_started(:snmp_sim)

# Load a profile
profile_path = "priv/walks/cable_modem_oids.walk"
{:ok, profile_data, behavior_data} = SnmpSim.ProfileLoader.load_profile(:cable_modem, {:walk_file, profile_path})

# Store the profile
device_type = "cable_modem"
:ok = SnmpSim.MIB.SharedProfiles.store_profile(device_type, profile_data, behavior_data)

IO.puts("Profile loaded with #{length(profile_data)} OIDs")

# Create device configuration
port = 30123  # Use a unique port
config = %{
  device_type: device_type,
  port: port,
  community: "public",
  ip: "127.0.0.1"
}

IO.puts("\n=== Creating SNMP device on port #{port} ===")

# Create the device
case DynamicSupervisor.start_child(SnmpSim.DeviceSupervisor, {SnmpSim.Device, config}) do
  {:ok, device_pid} ->
    IO.puts("✅ Device created successfully with PID: #{inspect(device_pid)}")
    
    # Wait for device to initialize
    Process.sleep(1000)
    
    IO.puts("\n=== Device is ready for testing ===")
    IO.puts("You can now test with SNMP clients:")
    IO.puts("")
    IO.puts("# Test GETBULK near end of MIB (should terminate properly):")
    IO.puts("snmpbulkwalk -v2c -c public 127.0.0.1:#{port} 1.3.6.1.2.1.2.2.1.20")
    IO.puts("")
    IO.puts("# Test full walk (should not hang):")
    IO.puts("snmpwalk -v2c -c public 127.0.0.1:#{port} 1.3.6.1.2.1")
    IO.puts("")
    IO.puts("# Test GETBULK from root (should terminate at end):")
    IO.puts("snmpbulkwalk -v2c -c public 127.0.0.1:#{port} 1.3.6.1")
    IO.puts("")
    IO.puts("Press Ctrl+C to stop the device and exit")
    
    # Keep the script running
    Process.sleep(:infinity)
    
  {:error, reason} ->
    IO.puts("❌ Failed to create device: #{inspect(reason)}")
    
    # Check if port is in use
    case System.cmd("lsof", ["-i", ":#{port}"], stderr_to_stdout: true) do
      {output, 0} ->
        IO.puts("Port #{port} is in use:")
        IO.puts(output)
      {_, _} ->
        IO.puts("Port #{port} appears to be free")
    end
end
