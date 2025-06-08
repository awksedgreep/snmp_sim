#!/usr/bin/env elixir

# Simple script to start a test device

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
port = 30124  # Use a different port
config = %{
  device_type: device_type,
  port: port,
  community: "public",
  ip: "127.0.0.1"
}

IO.puts("Creating SNMP device on port #{port}...")

# Create the device
case DynamicSupervisor.start_child(SnmpSim.DeviceSupervisor, {SnmpSim.Device, config}) do
  {:ok, device_pid} ->
    IO.puts("✅ Device created successfully with PID: #{inspect(device_pid)}")
    
    # Wait for device to initialize
    Process.sleep(2000)
    
    IO.puts("Device is ready for testing on port #{port}")
    
    # Keep the script running
    Process.sleep(:infinity)
    
  {:error, reason} ->
    IO.puts("❌ Failed to create device: #{inspect(reason)}")
end
