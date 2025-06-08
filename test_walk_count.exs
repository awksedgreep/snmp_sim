#!/usr/bin/env elixir

# Test script to verify walk returns all OIDs from walk file

# Start the application
Application.ensure_all_started(:snmp_sim)

# Allow time for startup
Process.sleep(1000)

IO.puts("🧪 Testing SNMP Walk OID Count")
IO.puts("==============================")

# Clean up any existing devices
IO.puts("\n1. Cleaning up existing devices...")
try do
  SnmpSim.DeviceRegistry.stop_all_devices()
  Process.sleep(500)
rescue
  _ -> :ok
end
IO.puts("✅ Cleanup complete")

# Load the walk profile
IO.puts("\n2. Loading walk profile...")
device_type = :walk_cable_modem_oids
walk_path = Path.join([File.cwd!(), "priv", "walks", "cable_modem_oids.walk"])

case SnmpSim.MIB.SharedProfiles.load_walk_profile(device_type, walk_path) do
  :ok ->
    IO.puts("✅ Walk profile loaded: #{device_type}")
  {:error, reason} ->
    IO.puts("❌ Failed to load walk profile: #{inspect(reason)}")
    System.halt(1)
end

# Create device with walk profile
IO.puts("\n3. Creating device with walk profile...")
device_config = %{
  device_id: "walk_count_test",
  port: 9004,
  device_type: device_type,
  community: "public"
}

case SnmpSim.Device.start_link(device_config) do
  {:ok, device_pid} ->
    IO.puts("✅ Device created successfully")
    
    # Test the walk count
    IO.puts("\n4. Testing walk from root OID...")
    case SnmpSim.Device.walk(device_pid, "1.3.6.1.2.1") do
      {:ok, oids} ->
        count = length(oids)
        IO.puts("✅ Walk returned #{count} OIDs")
        
        if count >= 40 do
          IO.puts("🎉 SUCCESS: Walk returned #{count} OIDs (expected ~49)")
          
          # Show first few and last few OIDs
          IO.puts("\nFirst 5 OIDs:")
          oids |> Enum.take(5) |> Enum.each(fn {oid, value} ->
            IO.puts("  #{oid} -> #{inspect(value)}")
          end)
          
          IO.puts("\nLast 5 OIDs:")
          oids |> Enum.take(-5) |> Enum.each(fn {oid, value} ->
            IO.puts("  #{oid} -> #{inspect(value)}")
          end)
        else
          IO.puts("❌ FAILURE: Walk only returned #{count} OIDs, expected ~49")
          IO.puts("\nAll returned OIDs:")
          oids |> Enum.each(fn {oid, value} ->
            IO.puts("  #{oid} -> #{inspect(value)}")
          end)
        end
        
      {:error, reason} ->
        IO.puts("❌ Walk failed: #{inspect(reason)}")
    end
    
    # Test walk from more specific OID
    IO.puts("\n5. Testing walk from interface table...")
    case SnmpSim.Device.walk(device_pid, "1.3.6.1.2.1.2.2.1") do
      {:ok, oids} ->
        count = length(oids)
        IO.puts("✅ Interface table walk returned #{count} OIDs")
        
        if count > 0 do
          IO.puts("Interface table OIDs:")
          oids |> Enum.each(fn {oid, value} ->
            IO.puts("  #{oid} -> #{inspect(value)}")
          end)
        end
        
      {:error, reason} ->
        IO.puts("❌ Interface table walk failed: #{inspect(reason)}")
    end
    
  {:error, reason} ->
    IO.puts("❌ Failed to create device: #{inspect(reason)}")
    System.halt(1)
end

IO.puts("\n✅ Walk count test complete")
