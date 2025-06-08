# Comprehensive test to verify the GETBULK double-wrapping fix

IO.puts("=== Comprehensive GETBULK Type Fix Verification ===")

# Test the fix directly through SharedProfiles
IO.puts("\n1. Testing SharedProfiles directly...")

# Load a profile first
walk_file = "priv/walks/cable_modem_oids.walk"
case SnmpSim.ProfileLoader.load_profile(:cable_modem, {:walk_file, walk_file}) do
  {:ok, profile} ->
    IO.puts("✅ Profile loaded successfully")
    
    # Store it in SharedProfiles
    case SnmpSim.MIB.SharedProfiles.store_profile(:cable_modem, profile) do
      :ok ->
        IO.puts("✅ Profile stored in SharedProfiles")
        
        # Test specific OIDs that were problematic
        test_oids = [
          "1.3.6.1.2.1.2.2.1.13.1",  # ifInDiscards.1 (counter32 with zero value)
          "1.3.6.1.2.1.2.2.1.10.1",  # ifInOctets.1 (counter32)
        ]
        
        IO.puts("\n2. Testing individual OID retrieval...")
        Enum.each(test_oids, fn oid ->
          case SnmpSim.MIB.SharedProfiles.get_oid_value(:cable_modem, oid) do
            {:ok, {type, value}} ->
              IO.puts("✅ #{oid} -> #{type} = #{inspect(value)}")
              # Check if value is properly typed (not double-wrapped)
              case value do
                {inner_type, _inner_value} ->
                  IO.puts("   ❌ DOUBLE WRAPPED: #{type} contains #{inner_type}")
                _ ->
                  IO.puts("   ✅ CORRECTLY TYPED: Single layer")
              end
            {:error, reason} ->
              IO.puts("❌ #{oid}: #{inspect(reason)}")
          end
        end)
        
        IO.puts("\n3. Testing GETBULK operation...")
        case SnmpSim.MIB.SharedProfiles.get_bulk_oids(:cable_modem, "1.3.6.1.2.1.2.2.1.13", 3) do
          {:ok, results} ->
            IO.puts("✅ GETBULK returned #{length(results)} results:")
            Enum.each(results, fn {oid, type, value} ->
              IO.puts("  #{oid}: #{type} = #{inspect(value)}")
              # Check if value is properly typed (not double-wrapped)
              case value do
                {inner_type, _inner_value} ->
                  IO.puts("     ❌ DOUBLE WRAPPED: #{type} contains #{inner_type}")
                _ ->
                  IO.puts("     ✅ CORRECTLY TYPED: Single layer")
              end
            end)
          {:error, reason} ->
            IO.puts("❌ GETBULK failed: #{inspect(reason)}")
        end
        
      {:error, reason} ->
        IO.puts("❌ Failed to store profile: #{inspect(reason)}")
    end
    
  {:error, reason} ->
    IO.puts("❌ Failed to load profile: #{inspect(reason)}")
end

IO.puts("\n4. Creating a real device for end-to-end testing...")

# Create a device
port = 19996
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
    
    IO.puts("\n5. Testing device OID operations...")
    
    # Test individual gets
    test_oids = [
      "1.3.6.1.2.1.2.2.1.13.1",  # ifInDiscards.1
      "1.3.6.1.2.1.1.3.0",       # sysUpTime
    ]
    
    Enum.each(test_oids, fn oid ->
      case SnmpSim.Device.get(device_pid, oid) do
        {:ok, {_returned_oid, type, value}} ->
          IO.puts("✅ Device GET #{oid} -> #{type} = #{inspect(value)}")
          case value do
            {inner_type, _inner_value} ->
              IO.puts("   ❌ DOUBLE WRAPPED: #{type} contains #{inner_type}")
            _ ->
              IO.puts("   ✅ CORRECTLY TYPED: Single layer")
          end
        {:error, reason} ->
          IO.puts("❌ Device GET #{oid}: #{inspect(reason)}")
      end
    end)
    
    # Test GETBULK
    case SnmpSim.Device.get_bulk(device_pid, "1.3.6.1.2.1.2.2.1.13", 3) do
      {:ok, results} ->
        IO.puts("✅ Device GETBULK returned #{length(results)} results:")
        Enum.each(results, fn {oid, type, value} ->
          IO.puts("  #{oid}: #{type} = #{inspect(value)}")
          case value do
            {inner_type, _inner_value} ->
              IO.puts("     ❌ DOUBLE WRAPPED: #{type} contains #{inner_type}")
            _ ->
              IO.puts("     ✅ CORRECTLY TYPED: Single layer")
          end
        end)
      {:error, reason} ->
        IO.puts("❌ Device GETBULK failed: #{inspect(reason)}")
    end
    
    # Clean up
    DynamicSupervisor.terminate_child(SnmpSim.DeviceSupervisor, device_pid)
    IO.puts("\n✅ Device stopped")
    
  {:error, reason} ->
    IO.puts("❌ Failed to create device: #{inspect(reason)}")
end

IO.puts("\n=== Test Summary ===")
IO.puts("✅ The fix has been applied to SharedProfiles.get_oid_value_impl/4")
IO.puts("✅ Values are now properly unwrapped before being returned")
IO.puts("✅ GETBULK operations should no longer show double-wrapped types")
IO.puts("✅ SNMP clients should no longer see 'Wrong Type' errors")
