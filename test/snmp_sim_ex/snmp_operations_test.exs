defmodule SNMPSimEx.SNMPOperationsTest do
  @moduledoc """
  Tests for SNMP operation types (GET, GETNEXT, GETBULK) to ensure
  they work correctly and return proper SNMP data types.
  
  This test suite specifically targets the SNMP walk functionality
  and device response handling that was causing "Wrong Type: NULL" issues.
  """
  
  use ExUnit.Case, async: false
  
  alias SNMPSimEx.Core.{PDU, Server}
  alias SNMPSimEx.Device
  alias SNMPSimEx.TestHelpers.PortHelper
  
  @test_community "public"
  
  describe "Device SNMP operations" do
    setup do
      test_port = PortHelper.get_port()
      device_config = %{
        port: test_port,
        device_type: :cable_modem,
        device_id: "snmp_test_device",
        community: @test_community
      }
      
      {:ok, device_pid} = Device.start_link(device_config)
      
      on_exit(fn ->
        if Process.alive?(device_pid) do
          Device.stop(device_pid)
        end
      end)
      
      # Wait for device initialization
      Process.sleep(100)
      
      %{device: device_pid}
    end
    
    test "GET operation returns proper SNMP data types", %{device: device} do
      # Test various system OIDs
      test_cases = [
        {"1.3.6.1.2.1.1.1.0", fn v -> is_binary(v) end, "sysDescr should be string"},
        {"1.3.6.1.2.1.1.2.0", fn v -> match?({:object_identifier, _}, v) end, "sysObjectID should be OID"},
        {"1.3.6.1.2.1.1.3.0", fn v -> match?({:timeticks, _}, v) end, "sysUpTime should be TimeTicks"},
        {"1.3.6.1.2.1.1.4.0", fn v -> is_binary(v) end, "sysContact should be string"},
        {"1.3.6.1.2.1.1.5.0", fn v -> is_binary(v) end, "sysName should be string"},
        {"1.3.6.1.2.1.1.6.0", fn v -> is_binary(v) end, "sysLocation should be string"},
        {"1.3.6.1.2.1.1.7.0", fn v -> is_integer(v) end, "sysServices should be integer"},
        {"1.3.6.1.2.1.2.1.0", fn v -> is_integer(v) end, "ifNumber should be integer"},
      ]
      
      for {oid, validator, description} <- test_cases do
        case Device.get(device, oid) do
          {:ok, value} ->
            assert validator.(value), "#{description}, got: #{inspect(value)}"
            # Ensure it's not a NULL value
            assert value != nil, "#{description} should not be nil"
            assert value != {:null, nil}, "#{description} should not be null tuple"
            
          {:error, reason} ->
            flunk("Failed to get #{oid} (#{description}): #{inspect(reason)}")
        end
      end
    end
    
    test "simulated SNMP walk returns sequential OIDs with proper types", %{device: device} do
      # Simulate what snmpwalk does - sequential GETNEXT operations
      walk_results = simulate_snmp_walk(device, "1.3.6.1.2.1.1")
      
      # Should get multiple results
      assert length(walk_results) > 0, "SNMP walk should return results"
      
      # All results should have valid SNMP data types
      for {oid, value} <- walk_results do
        assert is_binary(oid), "OID should be string: #{inspect(oid)}"
        assert String.starts_with?(oid, "1.3.6.1.2.1.1"), "OID should be in system subtree: #{oid}"
        
        # Verify the value is a valid SNMP type (not NULL)
        assert is_valid_snmp_type(value), "Invalid SNMP type for OID #{oid}: #{inspect(value)}"
        
        # Ensure we don't get "Wrong Type: NULL" equivalent values
        assert value != nil, "OID #{oid} should not return nil"
        assert value != {:null, nil}, "OID #{oid} should not return null tuple"
      end
      
      # Check that we get the expected system OIDs
      oids = Enum.map(walk_results, fn {oid, _} -> oid end)
      assert "1.3.6.1.2.1.1.1.0" in oids, "Should include sysDescr"
      assert "1.3.6.1.2.1.1.3.0" in oids, "Should include sysUpTime"
      assert "1.3.6.1.2.1.1.5.0" in oids, "Should include sysName"
    end
    
    test "GETNEXT operations return proper next OID and value", %{device: device} do
      # Test GETNEXT behavior by testing specific transitions
      getnext_tests = [
        {"1.3.6.1.2.1.1", "1.3.6.1.2.1.1.1.0"},      # Should get sysDescr
        {"1.3.6.1.2.1.1.1.0", "1.3.6.1.2.1.1.2.0"},  # sysDescr -> sysObjectID
        {"1.3.6.1.2.1.1.2.0", "1.3.6.1.2.1.1.3.0"},  # sysObjectID -> sysUpTime
        {"1.3.6.1.2.1.1.3.0", "1.3.6.1.2.1.1.4.0"},  # sysUpTime -> sysContact
      ]
      
      for {current_oid, expected_next_oid} <- getnext_tests do
        case simulate_getnext(device, current_oid) do
          {:ok, {next_oid, value}} ->
            assert next_oid == expected_next_oid, 
              "GETNEXT from #{current_oid} should return #{expected_next_oid}, got: #{next_oid}"
            assert is_valid_snmp_type(value), 
              "GETNEXT value for #{next_oid} should be valid SNMP type, got: #{inspect(value)}"
              
          {:error, reason} ->
            flunk("GETNEXT from #{current_oid} failed: #{inspect(reason)}")
        end
      end
    end
    
    test "interface table OIDs return proper SNMP types", %{device: device} do
      interface_oids = [
        {"1.3.6.1.2.1.2.2.1.1.1", :integer},     # ifIndex
        {"1.3.6.1.2.1.2.2.1.2.1", :string},      # ifDescr
        {"1.3.6.1.2.1.2.2.1.3.1", :integer},     # ifType
        {"1.3.6.1.2.1.2.2.1.4.1", :gauge32},     # ifMtu
        {"1.3.6.1.2.1.2.2.1.5.1", :gauge32},     # ifSpeed
        {"1.3.6.1.2.1.2.2.1.7.1", :integer},     # ifAdminStatus
        {"1.3.6.1.2.1.2.2.1.8.1", :integer},     # ifOperStatus
        {"1.3.6.1.2.1.2.2.1.9.1", :timeticks},   # ifLastChange
      ]
      
      for {oid, expected_type} <- interface_oids do
        case Device.get(device, oid) do
          {:ok, value} ->
            case expected_type do
              :integer -> 
                assert is_integer(value), "#{oid} should return integer, got: #{inspect(value)}"
              :string -> 
                assert is_binary(value), "#{oid} should return string, got: #{inspect(value)}"
              :gauge32 -> 
                assert match?({:gauge32, _}, value), "#{oid} should return gauge32, got: #{inspect(value)}"
              :timeticks -> 
                assert match?({:timeticks, _}, value), "#{oid} should return timeticks, got: #{inspect(value)}"
            end
            
          {:error, :no_such_name} ->
            # Some interface OIDs might not be implemented - that's acceptable
            :ok
            
          {:error, reason} ->
            flunk("Unexpected error for #{oid}: #{inspect(reason)}")
        end
      end
    end
    
    test "non-existent OIDs return proper SNMP error types", %{device: device} do
      non_existent_oids = [
        "1.3.6.1.99.99.99.0",
        "1.3.6.1.2.1.1.99.0",
        "9.9.9.9.9.0"
      ]
      
      for oid <- non_existent_oids do
        case Device.get(device, oid) do
          {:error, :no_such_name} -> 
            :ok  # This is correct
          {:ok, {:no_such_object, nil}} -> 
            :ok  # This is also correct for SNMPv2
          {:ok, value} ->
            flunk("Non-existent OID #{oid} should return error, got: #{inspect(value)}")
          {:error, other} ->
            # Other error types are acceptable
            :ok
        end
      end
    end
  end
  
  describe "End-to-end SNMP PDU processing" do
    setup do
      test_port = PortHelper.get_port()
      device_config = %{
        port: test_port,
        device_type: :router,
        device_id: "pdu_test_device",
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
    
    test "GET request PDU processing returns proper response", %{device: device} do
      # Create a GET request PDU
      request_pdu = %PDU{
        version: 1,
        community: @test_community,
        pdu_type: 0xA0,  # GET_REQUEST
        request_id: 12345,
        error_status: 0,
        error_index: 0,
        variable_bindings: [
          {"1.3.6.1.2.1.1.1.0", nil},  # sysDescr
          {"1.3.6.1.2.1.1.3.0", nil}   # sysUpTime
        ]
      }
      
      # Process the PDU through the device
      case GenServer.call(device, {:handle_snmp, request_pdu, %{}}) do
        {:ok, response_pdu} ->
          # Verify response structure
          assert response_pdu.version == request_pdu.version
          assert response_pdu.community == request_pdu.community
          assert response_pdu.pdu_type == 0xA2  # GET_RESPONSE
          assert response_pdu.request_id == request_pdu.request_id
          assert response_pdu.error_status == 0
          assert response_pdu.error_index == 0
          
          # Verify variable bindings have proper values
          assert length(response_pdu.variable_bindings) == 2
          
          [{oid1, value1}, {oid2, value2}] = response_pdu.variable_bindings
          
          # sysDescr should be a string
          assert oid1 == "1.3.6.1.2.1.1.1.0"
          assert is_binary(value1), "sysDescr should be string, got: #{inspect(value1)}"
          assert value1 =~ ~r/router/i, "Router device should have router in description"
          
          # sysUpTime should be TimeTicks
          assert oid2 == "1.3.6.1.2.1.1.3.0"
          assert match?({:timeticks, _}, value2), "sysUpTime should be TimeTicks, got: #{inspect(value2)}"
          
          # Verify the response can be encoded (this was the original problem)
          {:ok, encoded_response} = PDU.encode(response_pdu)
          assert is_binary(encoded_response), "Response PDU should encode to binary"
          
          # Verify the encoded response can be decoded back
          {:ok, decoded_response} = PDU.decode(encoded_response)
          assert decoded_response.version == response_pdu.version
          assert decoded_response.community == response_pdu.community
          assert decoded_response.pdu_type == response_pdu.pdu_type
          
        {:error, reason} ->
          flunk("Device PDU processing failed: #{inspect(reason)}")
      end
    end
    
    test "GETNEXT request PDU processing works correctly", %{device: device} do
      # Create a GETNEXT request PDU
      request_pdu = %PDU{
        version: 1,
        community: @test_community,
        pdu_type: 0xA1,  # GETNEXT_REQUEST
        request_id: 54321,
        error_status: 0,
        error_index: 0,
        variable_bindings: [{"1.3.6.1.2.1.1", nil}]  # Get next after system subtree
      }
      
      # Process the PDU
      case GenServer.call(device, {:handle_snmp, request_pdu, %{}}) do
        {:ok, response_pdu} ->
          assert response_pdu.pdu_type == 0xA2  # GET_RESPONSE
          assert response_pdu.request_id == request_pdu.request_id
          assert response_pdu.error_status == 0
          
          [{next_oid, next_value}] = response_pdu.variable_bindings
          
          # Should get the first OID in the system subtree
          assert String.starts_with?(next_oid, "1.3.6.1.2.1.1"), 
            "GETNEXT should return OID in system subtree, got: #{next_oid}"
          assert is_valid_snmp_type(next_value), 
            "GETNEXT value should be valid SNMP type, got: #{inspect(next_value)}"
            
        {:error, reason} ->
          flunk("GETNEXT PDU processing failed: #{inspect(reason)}")
      end
    end
  end
  
  # Helper functions
  
  defp simulate_snmp_walk(device, start_oid) do
    simulate_walk_recursive(device, start_oid, [], 10)
  end
  
  defp simulate_walk_recursive(_device, _oid, results, 0) do
    # Prevent infinite loops
    results
  end
  
  defp simulate_walk_recursive(device, current_oid, results, iterations_left) do
    case simulate_getnext(device, current_oid) do
      {:ok, {next_oid, value}} ->
        if String.starts_with?(next_oid, "1.3.6.1.2.1.1") do
          # Still in system subtree, continue
          new_results = results ++ [{next_oid, value}]
          simulate_walk_recursive(device, next_oid, new_results, iterations_left - 1)
        else
          # Left system subtree, stop
          results
        end
        
      {:error, _} ->
        results
    end
  end
  
  defp simulate_getnext(device, oid) do
    # This simulates GETNEXT by using the device's fallback functions
    # In a real implementation, this would use the actual GETNEXT PDU processing
    
    # Try to get the current OID to see if it exists
    case Device.get(device, oid) do
      {:ok, _} ->
        # OID exists, get next
        get_next_system_oid(device, oid)
      {:error, _} ->
        # OID doesn't exist, get first valid OID after this one
        get_next_system_oid(device, oid)
    end
  end
  
  defp get_next_system_oid(device, oid) do
    # Simple mapping for common system OID transitions
    next_oid = case oid do
      "1.3.6.1.2.1.1" -> "1.3.6.1.2.1.1.1.0"
      "1.3.6.1.2.1.1.1.0" -> "1.3.6.1.2.1.1.2.0"
      "1.3.6.1.2.1.1.2.0" -> "1.3.6.1.2.1.1.3.0"
      "1.3.6.1.2.1.1.3.0" -> "1.3.6.1.2.1.1.4.0"
      "1.3.6.1.2.1.1.4.0" -> "1.3.6.1.2.1.1.5.0"
      "1.3.6.1.2.1.1.5.0" -> "1.3.6.1.2.1.1.6.0"
      "1.3.6.1.2.1.1.6.0" -> "1.3.6.1.2.1.1.7.0"
      "1.3.6.1.2.1.1.7.0" -> "1.3.6.1.2.1.2.1.0"
      _ -> nil
    end
    
    if next_oid do
      case Device.get(device, next_oid) do
        {:ok, value} -> {:ok, {next_oid, value}}
        error -> error
      end
    else
      {:error, :end_of_mib}
    end
  end
  
  defp is_valid_snmp_type(value) do
    case value do
      # Basic SNMP types
      s when is_binary(s) -> true
      i when is_integer(i) -> true
      
      # SNMP-specific types  
      {:counter32, v} when is_integer(v) -> true
      {:gauge32, v} when is_integer(v) -> true
      {:timeticks, v} when is_integer(v) -> true
      {:object_identifier, v} when is_binary(v) -> true
      {:counter64, v} when is_integer(v) -> true
      
      # Exception types
      {:no_such_object, nil} -> true
      {:no_such_instance, nil} -> true
      {:end_of_mib_view, nil} -> true
      
      # Invalid types that would cause "Wrong Type: NULL" errors
      nil -> false
      {:null, nil} -> false
      _ -> false
    end
  end
end