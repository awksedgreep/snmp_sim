#!/usr/bin/env elixir

# Quick test script to verify SNMP walk functionality

# Start the application
{:ok, _} = Application.ensure_all_started(:snmp_sim)

# Wait a moment for devices to start
Process.sleep(1000)

# Start a device directly for testing
device_config = %{
  device_id: "test_device_30000",
  device_type: :cable_modem,
  port: 30000,
  community: "public",
  ip: "127.0.0.1"
}

case SnmpSim.Device.start_link(device_config) do
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
    
    # Test individual OID get_next
    IO.puts("\nTesting individual get_next operations...")
    
    # Test get_next_oid
    case GenServer.call(device_pid, {:get_next_oid, "1.3.6.1.2.1.2.2.1.10.1"}) do
      {:ok, {next_oid, value}} ->
        IO.puts("✅ get_next_oid successful!")
        IO.puts("  Next OID: #{next_oid} = #{inspect(value)}")
        
      {:error, reason} ->
        IO.puts("❌ get_next_oid failed: #{inspect(reason)}")
    end
    
    # Stop the device
    GenServer.stop(device_pid)
    
  {:error, reason} ->
    IO.puts("❌ Failed to start device: #{inspect(reason)}")
end

IO.puts("\n🎯 Walk functionality test completed!")
