# Test the live device to see what OIDs are available and test GETBULK

IO.puts("=== Testing Live Device ===")

# Find the device we created
devices = DynamicSupervisor.which_children(SnmpSim.DeviceSupervisor)
|> Enum.map(fn {_, pid, _, _} ->
  if Process.alive?(pid) do
    case SnmpSim.Device.get_info(pid) do
      {:ok, info} -> {pid, info}
      _ -> nil
    end
  else
    nil
  end
end)
|> Enum.filter(& &1)

case devices do
  [] ->
    IO.puts("❌ No devices found")
    
  [{device_pid, device_info} | _] ->
    IO.puts("✅ Found device: #{inspect(device_info)}")
    
    # Test some basic OIDs
    test_oids = [
      "1.3.6.1.2.1.1.1.0",     # sysDescr
      "1.3.6.1.2.1.1.3.0",     # sysUpTime
      "1.3.6.1.2.1.2.1.0",     # ifNumber
      "1.3.6.1.2.1.2.2.1.1.1", # ifIndex.1
      "1.3.6.1.2.1.2.2.1.13.1" # ifInDiscards.1
    ]
    
    IO.puts("\n=== Testing Individual OID Gets ===")
    Enum.each(test_oids, fn oid ->
      case SnmpSim.Device.get(device_pid, oid) do
        {:ok, {returned_oid, type, value}} ->
          IO.puts("✅ #{oid} -> #{returned_oid}: #{type} = #{inspect(value)}")
        {:error, reason} ->
          IO.puts("❌ #{oid}: #{inspect(reason)}")
      end
    end)
    
    IO.puts("\n=== Testing GETBULK on ifInDiscards ===")
    case SnmpSim.Device.get_bulk(device_pid, "1.3.6.1.2.1.2.2.1.13", 5) do
      {:ok, results} ->
        IO.puts("✅ GETBULK returned #{length(results)} results:")
        Enum.each(results, fn {oid, type, value} ->
          IO.puts("  #{oid}: #{type} = #{inspect(value)}")
        end)
      {:error, reason} ->
        IO.puts("❌ GETBULK failed: #{inspect(reason)}")
    end
    
    IO.puts("\n=== Testing Walk ===")
    case SnmpSim.Device.walk(device_pid, "1.3.6.1.2.1.2.2.1.13") do
      {:ok, results} ->
        IO.puts("✅ Walk returned #{length(results)} results:")
        Enum.take(results, 10) |> Enum.each(fn {oid, type, value} ->
          IO.puts("  #{oid}: #{type} = #{inspect(value)}")
        end)
        if length(results) > 10 do
          IO.puts("  ... and #{length(results) - 10} more")
        end
      {:error, reason} ->
        IO.puts("❌ Walk failed: #{inspect(reason)}")
    end
end
