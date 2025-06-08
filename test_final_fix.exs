# Final test to verify the GETBULK type fix

IO.puts("=== Final GETBULK Type Fix Test ===")

# Load the walk file and create a device with real data
walk_file = "priv/walks/cable_modem_oids.walk"

# First, load the profile into SharedProfiles
case SnmpSim.MIB.ProfileLoader.load_profile(:cable_modem, walk_file) do
  {:ok, _profile} ->
    IO.puts("✅ Profile loaded successfully")
    
    # Create a device
    port = 19998
    config = %{
      port: port,
      device_type: :cable_modem,
      device_id: "test_cm_#{port}",
      community: "public"
    }
    
    case DynamicSupervisor.start_child(SnmpSim.DeviceSupervisor, {SnmpSim.Device, config}) do
      {:ok, device_pid} ->
        IO.puts("✅ Device created successfully on port #{port}")
        
        # Wait for device to initialize
        Process.sleep(1000)
        
        # Test the problematic OIDs that were causing double-wrapping
        test_oids = [
          "1.3.6.1.2.1.2.2.1.13.1",  # ifInDiscards.1 (counter32)
          "1.3.6.1.2.1.2.2.1.13.2",  # ifInDiscards.2 (counter32)
          "1.3.6.1.2.1.2.2.1.10.1",  # ifInOctets.1 (counter32)
        ]
        
        IO.puts("\n=== Testing Individual OID Gets (should show single-layer types) ===")
        Enum.each(test_oids, fn oid ->
          case SnmpSim.Device.get(device_pid, oid) do
            {:ok, {returned_oid, type, value}} ->
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
        case SnmpSim.Device.get_bulk(device_pid, "1.3.6.1.2.1.2.2.1.13", 5) do
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
        
        # Test with real SNMP client
        IO.puts("\n=== Testing with real SNMP client ===")
        IO.puts("Running: snmpbulkwalk -v2c -c public localhost:#{port} 1.3.6.1.2.1.2.2.1.13")
        
        case System.cmd("snmpbulkwalk", ["-v2c", "-c", "public", "localhost:#{port}", "1.3.6.1.2.1.2.2.1.13"], stderr_to_stdout: true) do
          {output, 0} ->
            IO.puts("✅ SNMP client output:")
            IO.puts(output)
          {output, _exit_code} ->
            IO.puts("❌ SNMP client failed:")
            IO.puts(output)
        end
        
        # Clean up
        DynamicSupervisor.terminate_child(SnmpSim.DeviceSupervisor, device_pid)
        IO.puts("\n✅ Device stopped")
        
      {:error, reason} ->
        IO.puts("❌ Failed to create device: #{inspect(reason)}")
    end
    
  {:error, reason} ->
    IO.puts("❌ Failed to load profile: #{inspect(reason)}")
end
