#!/usr/bin/env elixir

# Quick test script to verify walk file functionality and type fidelity

# Start the application
{:ok, _} = Application.ensure_all_started(:snmp_sim)

# Wait a moment for services to start
Process.sleep(1000)

IO.puts "🧪 Testing Walk File Functionality"
IO.puts "=================================="

# Clean up any existing devices
IO.puts "\n1. Cleaning up existing devices..."
try do
  DynamicSupervisor.which_children(SnmpSim.DeviceSupervisor)
  |> Enum.each(fn {_, pid, _, _} ->
    if Process.alive?(pid) do
      DynamicSupervisor.terminate_child(SnmpSim.DeviceSupervisor, pid)
    end
  end)
  IO.puts "✅ Cleanup complete"
rescue
  e -> IO.puts "⚠️  Cleanup error: #{inspect(e)}"
end

# Test 1: Load walk profile
IO.puts "\n2. Loading walk profile..."
device_type = :walk_cable_modem_oids
walk_path = Path.join([File.cwd!(), "priv", "walks", "cable_modem_oids.walk"])

case SnmpSim.MIB.SharedProfiles.load_walk_profile(device_type, walk_path) do
  :ok ->
    IO.puts "✅ Walk profile loaded successfully"
    
    # Test 2: Create device with walk profile
    IO.puts "\n3. Creating device with walk profile..."
    config = %{
      port: 9003,
      device_type: device_type,
      device_id: "walk_test_device"
    }
    
    case DynamicSupervisor.start_child(SnmpSim.DeviceSupervisor, {SnmpSim.Device, config}) do
      {:ok, pid} ->
        IO.puts "✅ Device created successfully"
        
        # Test 3: Test type fidelity
        IO.puts "\n4. Testing type fidelity..."
        Process.sleep(500)  # Give device time to initialize
        
        test_oids = [
          "1.3.6.1.2.1.2.2.1.10.1",  # Counter32: ifInOctets
          "1.3.6.1.2.1.2.2.1.21.1",  # Gauge32: ifInNUcastPkts  
          "1.3.6.1.2.1.2.2.1.6.1",   # STRING: ifPhysAddress
          "1.3.6.1.2.1.2.2.1.9.1"    # Timeticks: ifLastChange
        ]
        
        Enum.each(test_oids, fn oid ->
          case SnmpSim.Device.get(pid, oid) do
            {:ok, {type, value}} ->
              IO.puts "✅ #{oid} -> {#{type}, #{inspect(value)}}"
              
            {:ok, value} ->
              IO.puts "⚠️  #{oid} -> #{inspect(value)} (no type info)"
              
            {:error, reason} ->
              IO.puts "❌ #{oid} -> ERROR: #{inspect(reason)}"
          end
        end)
        
        IO.puts "\n🎯 Type fidelity test complete!"
        
      {:error, reason} ->
        IO.puts "❌ Failed to create device: #{inspect(reason)}"
    end
    
  {:error, reason} ->
    IO.puts "❌ Failed to load walk profile: #{inspect(reason)}"
end

IO.puts "\n✅ Test script complete"
