#!/usr/bin/env elixir

# Quick test to create device on port 9999 and exit
Application.ensure_all_started(:snmp_sim)
Process.sleep(1000)

IO.puts("🔍 Quick Test Port 9999")
IO.puts("========================")

# Load the walk profile
device_type = :walk_cable_modem_oids
walk_path = Path.join([File.cwd!(), "priv", "walks", "cable_modem_oids.walk"])

IO.puts("1. Loading walk profile...")
case SnmpSim.MIB.SharedProfiles.load_walk_profile(device_type, walk_path) do
  :ok -> IO.puts("✅ Walk profile loaded")
  {:error, reason} -> 
    IO.puts("❌ Failed to load walk profile: #{inspect(reason)}")
    System.halt(1)
end

IO.puts("\n2. Creating device on port 9999...")
case SnmpSim.Device.start_link(%{
  device_id: "walk_device_9999",
  device_type: device_type,
  port: 9999
}) do
  {:ok, device_pid} ->
    IO.puts("✅ Device created on port 9999")
    
    # Quick test of get_next
    IO.puts("\n3. Testing get_next on 1.3.6.1.2.1.1.7.0...")
    case SnmpSim.Device.get_next(device_pid, "1.3.6.1.2.1.1.7.0") do
      {:ok, {oid, type, value}} -> 
        IO.puts("✅ get_next returned: #{oid} (#{type}) = #{inspect(value)}")
      {:error, reason} -> 
        IO.puts("❌ get_next failed: #{inspect(reason)}")
    end
    
    IO.puts("\n✅ Device ready for SNMP testing on port 9999")
    IO.puts("   You can now run: snmpbulkwalk -v2c -c public 127.0.0.1:9999")
    
  {:error, reason} ->
    IO.puts("❌ Failed to create device: #{inspect(reason)}")
    System.halt(1)
end

# Don't exit - keep the device running
Process.sleep(:infinity)
