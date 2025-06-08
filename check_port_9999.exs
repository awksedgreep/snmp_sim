#!/usr/bin/env elixir

# Check what's running on port 9999
Application.ensure_all_started(:snmp_sim)
Process.sleep(1000)

IO.puts("🔍 Checking Port 9999")
IO.puts("====================")

# Try to create a device with walk file on port 9999
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
    IO.puts("✅ Device created successfully on port 9999")
    IO.puts("Device PID: #{inspect(device_pid)}")
    
    # Test a quick walk to see how many OIDs we get
    IO.puts("\n3. Testing walk from device...")
    case SnmpSim.Device.walk(device_pid, "1.3.6.1.2.1") do
      {:ok, results} ->
        IO.puts("✅ Walk returned #{length(results)} OIDs")
        if length(results) > 10 do
          IO.puts("First 5 OIDs:")
          results |> Enum.take(5) |> Enum.each(fn {oid, value} ->
            IO.puts("  #{oid} -> #{inspect(value)}")
          end)
          IO.puts("Last 5 OIDs:")
          results |> Enum.take(-5) |> Enum.each(fn {oid, value} ->
            IO.puts("  #{oid} -> #{inspect(value)}")
          end)
        else
          IO.puts("All OIDs:")
          Enum.each(results, fn {oid, value} ->
            IO.puts("  #{oid} -> #{inspect(value)}")
          end)
        end
      {:error, reason} ->
        IO.puts("❌ Walk failed: #{inspect(reason)}")
    end
    
    IO.puts("\n✅ Device is ready for SNMP testing on port 9999")
    IO.puts("You can now run: snmpbulkwalk -v2c -c public 127.0.0.1:9999")
    
    # Keep the process alive
    Process.sleep(:infinity)
    
  {:error, reason} ->
    IO.puts("❌ Failed to create device: #{inspect(reason)}")
end
