# Simple test to verify the GETBULK type fix using the .iex.exs helper

IO.puts("=== Simple GETBULK Type Fix Test ===")

# Use the Sim helper to create a cable modem
port = 19997

case Sim.create_cable_modem(port) do
  {device_pid, :ok} ->
    IO.puts("✅ Device created successfully on port #{port}")
    
    # Wait for device to initialize
    Process.sleep(1000)
    
    # Test the problematic OIDs that were causing double-wrapping
    test_oids = [
      "1.3.6.1.2.1.2.2.1.13.1",  # ifInDiscards.1 (counter32)
      "1.3.6.1.2.1.2.2.1.10.1",  # ifInOctets.1 (counter32)
      "1.3.6.1.2.1.1.3.0",       # sysUpTime (timeticks)
    ]
    
    IO.puts("\n=== Testing Individual OID Gets (should show single-layer types) ===")
    Enum.each(test_oids, fn oid ->
      case SnmpSim.Device.get(device_pid, oid) do
        {:ok, {_returned_oid, type, value}} ->
          IO.puts("✅ #{oid} -> #{type} = #{inspect(value)}")
          # Check if value is properly typed (not double-wrapped)
          case value do
            {inner_type, _inner_value} ->
              IO.puts("   ⚠️  DOUBLE WRAPPED: #{type} contains #{inner_type}")
            _ ->
              IO.puts("   ✅ CORRECTLY TYPED: Single layer")
          end
        {:error, reason} ->
          IO.puts("❌ #{oid}: #{inspect(reason)}")
      end
    end)
    
    IO.puts("\n=== Testing GETBULK (should show single-layer types) ===")
    case SnmpSim.Device.get_bulk(device_pid, "1.3.6.1.2.1.2.2.1.13", 3) do
      {:ok, results} ->
        IO.puts("✅ GETBULK returned #{length(results)} results:")
        Enum.each(results, fn {oid, type, value} ->
          IO.puts("  #{oid}: #{type} = #{inspect(value)}")
          # Check if value is properly typed (not double-wrapped)
          case value do
            {inner_type, _inner_value} ->
              IO.puts("     ⚠️  DOUBLE WRAPPED: #{type} contains #{inner_type}")
            _ ->
              IO.puts("     ✅ CORRECTLY TYPED: Single layer")
          end
        end)
      {:error, reason} ->
        IO.puts("❌ GETBULK failed: #{inspect(reason)}")
    end
    
    # Test with real SNMP client if available
    IO.puts("\n=== Testing with real SNMP client ===")
    IO.puts("Running: snmpget -v2c -c public localhost:#{port} 1.3.6.1.2.1.2.2.1.13.1")
    
    case System.cmd("snmpget", ["-v2c", "-c", "public", "localhost:#{port}", "1.3.6.1.2.1.2.2.1.13.1"], stderr_to_stdout: true) do
      {output, 0} ->
        IO.puts("✅ SNMP GET output:")
        IO.puts(output)
        if String.contains?(output, "Wrong Type") do
          IO.puts("❌ Still seeing 'Wrong Type' errors!")
        else
          IO.puts("✅ No 'Wrong Type' errors detected")
        end
      {output, _exit_code} ->
        IO.puts("❌ SNMP GET failed:")
        IO.puts(output)
    end
    
    # Clean up
    DynamicSupervisor.terminate_child(SnmpSim.DeviceSupervisor, device_pid)
    IO.puts("\n✅ Device stopped")
    
  {nil, {:error, reason}} ->
    IO.puts("❌ Failed to create device: #{inspect(reason)}")
end
