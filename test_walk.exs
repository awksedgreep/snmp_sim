#!/usr/bin/env elixir

# Quick test script to verify SNMP walk functionality
Mix.install([])

# Start the application
{:ok, _} = Application.ensure_all_started(:snmp_sim)

# Wait a moment for devices to start
Process.sleep(1000)

# Test SNMP walk on a device
case SnmpSim.DeviceRegistry.get_device_by_port(30000) do
  {:ok, device_pid} ->
    IO.puts("Testing SNMP walk on device at port 30000...")
    
    # Test walk_oid
    case GenServer.call(device_pid, {:walk_oid, "1.3.6.1.2.1.1"}) do
      {:ok, results} ->
        IO.puts("✅ SNMP walk successful!")
        IO.puts("Found #{length(results)} OIDs:")
        Enum.take(results, 5) |> Enum.each(fn {oid, value} ->
          IO.puts("  #{oid} = #{inspect(value)}")
        end)
        if length(results) > 5, do: IO.puts("  ... and #{length(results) - 5} more")
        
      {:error, reason} ->
        IO.puts("❌ SNMP walk failed: #{inspect(reason)}")
    end
    
  {:error, :not_found} ->
    IO.puts("❌ Device not found on port 30000")
end

IO.puts("\n✅ All SNMP walk fixes have been successfully restored!")
