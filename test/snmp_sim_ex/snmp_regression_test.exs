defmodule SNMPSimEx.SNMPRegressionTest do
  @moduledoc """
  Regression tests for specific SNMP issues that were discovered during testing.
  
  This test suite focuses on preventing regressions of critical bugs,
  particularly the "Wrong Type (should be OCTET STRING): NULL" issue
  that was found during container testing with snmpwalk.
  """
  
  use ExUnit.Case, async: false
  
  alias SNMPSimEx.Core.{PDU, Server}
  alias SNMPSimEx.Device
  
  @test_port 19163
  @test_community "public"
  
  describe "Regression: Wrong Type NULL issue" do
    setup do
      device_config = %{
        port: @test_port,
        device_type: :cable_modem,
        device_id: "regression_test_device",
        community: @test_community
      }
      
      {:ok, device_pid} = Device.start_link(device_config)
      
      on_exit(fn ->
        if Process.alive?(device_pid) do
          Device.stop(device_pid)
        end
      end)
      
      Process.sleep(100)
      
      %{device: device_pid}
    end
    
    test "system OIDs return proper SNMP types (not NULL)", %{device: device} do
      # These are the exact OIDs that were returning "Wrong Type: NULL" 
      # when tested with snmpwalk
      critical_oids = [
        {"1.3.6.1.2.1.1.1.0", "sysDescr", :string},
        {"1.3.6.1.2.1.1.2.0", "sysObjectID", :object_identifier},
        {"1.3.6.1.2.1.1.4.0", "sysContact", :string},
        {"1.3.6.1.2.1.1.5.0", "sysName", :string},
        {"1.3.6.1.2.1.1.6.0", "sysLocation", :string},
        {"1.3.6.1.2.1.1.7.0", "sysServices", :integer}
      ]
      
      for {oid, name, expected_type} <- critical_oids do
        {:ok, value} = Device.get(device, oid)
        
        # These assertions specifically check for the "Wrong Type: NULL" issue
        refute value == nil, "#{name} (#{oid}) should not return nil (this causes 'Wrong Type: NULL')"
        refute value == {:null, nil}, "#{name} (#{oid}) should not return null tuple"
        
        # Verify correct SNMP type
        case expected_type do
          :string ->
            assert is_binary(value), "#{name} (#{oid}) should return string, got: #{inspect(value)}"
            assert value != "", "#{name} (#{oid}) should not return empty string"
            
          :object_identifier ->
            assert match?({:object_identifier, _}, value), 
              "#{name} (#{oid}) should return object_identifier tuple, got: #{inspect(value)}"
            {:object_identifier, oid_value} = value
            assert is_binary(oid_value), "Object identifier value should be string"
            assert String.contains?(oid_value, "."), "Object identifier should contain dots"
            
          :integer ->
            assert is_integer(value), "#{name} (#{oid}) should return integer, got: #{inspect(value)}"
        end
      end
    end
    
    test "SNMP walk simulation returns no NULL values", %{device: device} do
      # Simulate the exact operations that snmpwalk performs
      walk_operations = [
        "1.3.6.1.2.1.1",        # Starting point
        "1.3.6.1.2.1.1.1.0",   # sysDescr
        "1.3.6.1.2.1.1.2.0",   # sysObjectID
        "1.3.6.1.2.1.1.3.0",   # sysUpTime  
        "1.3.6.1.2.1.1.4.0",   # sysContact
        "1.3.6.1.2.1.1.5.0",   # sysName
        "1.3.6.1.2.1.1.6.0",   # sysLocation
        "1.3.6.1.2.1.1.7.0"    # sysServices
      ]
      
      for oid <- walk_operations do
        case Device.get(device, oid) do
          {:ok, value} ->
            # Critical: ensure no NULL values that cause "Wrong Type" errors
            assert value != nil, "OID #{oid} returned nil (causes 'Wrong Type: NULL' in SNMP tools)"
            assert value != {:null, nil}, "OID #{oid} returned null tuple"
            
            # Ensure value can be encoded in a PDU without becoming NULL
            pdu = create_test_response_pdu(oid, value)
            {:ok, encoded} = PDU.encode(pdu)
            {:ok, decoded} = PDU.decode(encoded)
            
            [{_decoded_oid, decoded_value}] = decoded.variable_bindings
            assert decoded_value == value, 
              "Value for #{oid} changed during PDU encode/decode: #{inspect(value)} -> #{inspect(decoded_value)}"
              
          {:error, :no_such_name} ->
            # This is acceptable for some OIDs
            :ok
        end
      end
    end
    
    test "PDU encoding preserves all SNMP data types correctly", %{device: device} do
      # Get values from device and verify they encode/decode correctly
      system_oids = [
        "1.3.6.1.2.1.1.1.0",  # sysDescr
        "1.3.6.1.2.1.1.2.0",  # sysObjectID
        "1.3.6.1.2.1.1.3.0",  # sysUpTime
        "1.3.6.1.2.1.1.4.0",  # sysContact
        "1.3.6.1.2.1.1.5.0",  # sysName
        "1.3.6.1.2.1.1.6.0",  # sysLocation
        "1.3.6.1.2.1.1.7.0"   # sysServices
      ]
      
      # Collect all values
      oid_values = Enum.map(system_oids, fn oid ->
        case Device.get(device, oid) do
          {:ok, value} -> {oid, value}
          {:error, _} -> {oid, {:no_such_object, nil}}
        end
      end)
      
      # Create a response PDU with all values
      response_pdu = %PDU{
        version: 1,
        community: @test_community,
        pdu_type: 0xA2,  # GET_RESPONSE
        request_id: 99999,
        error_status: 0,
        error_index: 0,
        variable_bindings: oid_values
      }
      
      # Encode and decode the PDU
      {:ok, encoded} = PDU.encode(response_pdu)
      {:ok, decoded} = PDU.decode(encoded)
      
      # Verify all values were preserved
      assert length(decoded.variable_bindings) == length(oid_values)
      
      # Convert to maps for easier comparison (order may change during encoding)
      # Handle the case where decoded OIDs might be object_identifier tuples
      normalize_oid = fn
        {:object_identifier, oid_string} -> oid_string
        oid_string when is_binary(oid_string) -> oid_string
      end
      
      original_map = Enum.into(oid_values, %{})
      decoded_normalized = Enum.map(decoded.variable_bindings, fn {oid, value} ->
        {normalize_oid.(oid), value}
      end)
      decoded_map = Enum.into(decoded_normalized, %{})
      
      # Verify all original OIDs are present with correct values
      for {original_oid, original_value} <- oid_values do
        case Map.get(decoded_map, original_oid) do
          nil ->
            flunk("OID #{original_oid} missing from decoded PDU. Available OIDs: #{inspect(Map.keys(decoded_map))}")
          decoded_value ->
            assert decoded_value == original_value, 
              "Value mismatch for #{original_oid}: #{inspect(original_value)} -> #{inspect(decoded_value)}"
        end
      end
    end
    
    test "interface table OIDs return proper types (not NULL)", %{device: device} do
      # Interface table OIDs that could potentially return NULL
      interface_oids = [
        {"1.3.6.1.2.1.2.2.1.1.1", "ifIndex"},
        {"1.3.6.1.2.1.2.2.1.2.1", "ifDescr"},
        {"1.3.6.1.2.1.2.2.1.3.1", "ifType"},
        {"1.3.6.1.2.1.2.2.1.4.1", "ifMtu"},
        {"1.3.6.1.2.1.2.2.1.5.1", "ifSpeed"},
        {"1.3.6.1.2.1.2.2.1.7.1", "ifAdminStatus"},
        {"1.3.6.1.2.1.2.2.1.8.1", "ifOperStatus"}
      ]
      
      for {oid, name} <- interface_oids do
        case Device.get(device, oid) do
          {:ok, value} ->
            # Ensure not NULL
            refute value == nil, "#{name} (#{oid}) should not return nil"
            refute value == {:null, nil}, "#{name} (#{oid}) should not return null tuple"
            
            # Ensure it's a valid SNMP type
            assert is_valid_snmp_type(value), "#{name} (#{oid}) returned invalid SNMP type: #{inspect(value)}"
            
          {:error, :no_such_name} ->
            # Some interface OIDs might not be implemented
            :ok
        end
      end
    end
    
    test "device type-specific descriptions are correct", %{device: _device} do
      # Test different device types to ensure they return proper descriptions
      device_types = [
        {:cable_modem, ~r/cable.*modem/i},
        {:switch, ~r/switch|simulator/i},
        {:router, ~r/router/i}
      ]
      
      for {device_type, expected_pattern} <- device_types do
        device_config = %{
          port: @test_port + 100 + Enum.find_index(device_types, fn {dt, _} -> dt == device_type end),
          device_type: device_type,
          device_id: "type_test_#{device_type}",
          community: @test_community
        }
        
        {:ok, device_pid} = Device.start_link(device_config)
        Process.sleep(50)
        
        try do
          {:ok, sys_descr} = Device.get(device_pid, "1.3.6.1.2.1.1.1.0")
          
          # Should not be NULL
          assert is_binary(sys_descr), "sysDescr should be string for #{device_type}, got: #{inspect(sys_descr)}"
          assert sys_descr != "", "sysDescr should not be empty for #{device_type}"
          
          # Should match expected pattern
          assert sys_descr =~ expected_pattern, 
            "sysDescr for #{device_type} should match #{inspect(expected_pattern)}, got: '#{sys_descr}'"
            
        after
          Device.stop(device_pid)
        end
      end
    end
    
    test "error conditions don't return NULL values", %{device: device} do
      # Test that error conditions return proper SNMP error types, not NULL
      error_test_oids = [
        "1.3.6.1.99.99.99.0",      # Non-existent enterprise OID
        "1.3.6.1.2.1.1.99.0",     # Non-existent system OID
        "999.999.999.999.0"       # Completely invalid OID
      ]
      
      for oid <- error_test_oids do
        case Device.get(device, oid) do
          {:ok, {:no_such_object, nil}} ->
            # This is correct SNMP error handling
            :ok
            
          {:ok, {:no_such_instance, nil}} ->
            # This is also correct
            :ok
            
          {:error, :no_such_name} ->
            # This is correct for SNMPv1
            :ok
            
          {:ok, nil} ->
            flunk("Device returned nil for non-existent OID #{oid} (should return proper SNMP error)")
            
          {:ok, {:null, nil}} ->
            flunk("Device returned null tuple for non-existent OID #{oid} (should return proper SNMP error)")
            
          {:ok, other_value} ->
            flunk("Device returned unexpected value for non-existent OID #{oid}: #{inspect(other_value)}")
            
          {:error, _reason} ->
            # Other error types are acceptable
            :ok
        end
      end
    end
  end
  
  describe "Regression: PDU encoding edge cases" do
    test "all SNMP data types encode without becoming NULL" do
      # Test all the SNMP data types that should never become NULL
      test_values = [
        {"empty string", ""},
        {"normal string", "test value"},
        {"zero integer", 0},
        {"positive integer", 42},
        {"negative integer", -1},
        {"object identifier", {:object_identifier, "1.3.6.1.2.1.1.1.0"}},
        {"counter32 zero", {:counter32, 0}},
        {"counter32 value", {:counter32, 12345}},
        {"gauge32 zero", {:gauge32, 0}},
        {"gauge32 value", {:gauge32, 67890}},
        {"timeticks zero", {:timeticks, 0}},
        {"timeticks value", {:timeticks, 54321}},
        {"counter64 value", {:counter64, 9876543210}}
      ]
      
      for {description, value} <- test_values do
        pdu = create_test_response_pdu("1.3.6.1.2.1.1.1.0", value)
        
        # Encode and decode
        {:ok, encoded} = PDU.encode(pdu)
        {:ok, decoded} = PDU.decode(encoded)
        
        [{_oid, decoded_value}] = decoded.variable_bindings
        
        # Value should be preserved exactly
        assert decoded_value == value, 
          "#{description} was not preserved through PDU encoding: #{inspect(value)} -> #{inspect(decoded_value)}"
          
        # Should never become nil or null
        refute decoded_value == nil, "#{description} became nil during PDU encoding"
        refute decoded_value == {:null, nil}, "#{description} became null tuple during PDU encoding"
      end
    end
    
    test "malformed values fallback to NULL correctly" do
      # Test that truly invalid values fallback to NULL (not crash)
      invalid_values = [
        {:unknown_type, "value"},
        {:invalid_tuple, 123, "extra"},
        %{invalid: "map"},
        ["invalid", "list"]
      ]
      
      for invalid_value <- invalid_values do
        pdu = create_test_response_pdu("1.3.6.1.2.1.1.1.0", invalid_value)
        
        # Should encode without crashing
        {:ok, encoded} = PDU.encode(pdu)
        {:ok, decoded} = PDU.decode(encoded)
        
        [{_oid, decoded_value}] = decoded.variable_bindings
        
        # Invalid values should become nil (NULL in SNMP)
        assert decoded_value == nil, 
          "Invalid value #{inspect(invalid_value)} should become nil, got: #{inspect(decoded_value)}"
      end
    end
  end
  
  # Helper functions
  
  defp create_test_response_pdu(oid, value) do
    %PDU{
      version: 1,
      community: @test_community,
      pdu_type: 0xA2,  # GET_RESPONSE
      request_id: 12345,
      error_status: 0,
      error_index: 0,
      variable_bindings: [{oid, value}]
    }
  end
  
  defp is_valid_snmp_type(value) do
    case value do
      # Valid SNMP types
      s when is_binary(s) -> true
      i when is_integer(i) -> true
      {:counter32, v} when is_integer(v) -> true
      {:gauge32, v} when is_integer(v) -> true
      {:timeticks, v} when is_integer(v) -> true
      {:object_identifier, v} when is_binary(v) -> true
      {:counter64, v} when is_integer(v) -> true
      {:no_such_object, nil} -> true
      {:no_such_instance, nil} -> true
      {:end_of_mib_view, nil} -> true
      
      # Invalid types that would cause issues
      nil -> false
      {:null, nil} -> false
      _ -> false
    end
  end
end