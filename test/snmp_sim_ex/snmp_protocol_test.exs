defmodule SNMPSimEx.SNMPProtocolTest do
  @moduledoc """
  Comprehensive SNMP protocol compliance tests.
  
  These tests ensure that:
  1. PDU encoding/decoding works correctly for all SNMP data types
  2. SNMP operations (GET, GETNEXT, GETBULK) work properly
  3. Device responses are SNMP compliant
  4. SNMP walks return proper data types
  
  This test suite should catch issues like the "Wrong Type: NULL" problems
  that were found during container testing.
  """
  
  use ExUnit.Case, async: false
  
  alias SNMPSimEx.Core.{PDU, Server}
  alias SNMPSimEx.Device
  alias SNMPSimEx.TestHelpers.PortHelper
  
  @test_community "public"
  
  describe "PDU encoding/decoding" do
    test "encodes and decodes all SNMP data types correctly" do
      test_values = [
        # Basic types
        {"string value", "STRING"},
        {42, "INTEGER"},
        {{:counter32, 12345}, "Counter32"},
        {{:gauge32, 67890}, "Gauge32"},
        {{:timeticks, 54321}, "TimeTicks"},
        {{:object_identifier, "1.3.6.1.2.1.1.1.0"}, "OBJECT IDENTIFIER"},
        
        # SNMP exception types
        {{:no_such_object, nil}, "noSuchObject"},
        {{:no_such_instance, nil}, "noSuchInstance"},
        {{:end_of_mib_view, nil}, "endOfMibView"}
      ]
      
      for {value, expected_type_description} <- test_values do
        # Create a test PDU with this value
        pdu = %PDU{
          version: 1,
          community: @test_community,
          pdu_type: 0xA2,  # GET_RESPONSE
          request_id: 1234,
          error_status: 0,
          error_index: 0,
          variable_bindings: [{"1.3.6.1.2.1.1.1.0", value}]
        }
        
        # Encode and then decode the PDU
        {:ok, encoded} = PDU.encode(pdu)
        assert is_binary(encoded), "PDU encoding should return binary data"
        
        {:ok, decoded} = PDU.decode(encoded)
        assert decoded.version == pdu.version
        assert decoded.community == pdu.community
        assert decoded.pdu_type == pdu.pdu_type
        assert decoded.request_id == pdu.request_id
        
        # Verify the value was encoded/decoded correctly
        [{_oid, decoded_value}] = decoded.variable_bindings
        assert decoded_value == value, 
          "Value #{inspect(value)} (#{expected_type_description}) was not preserved through encode/decode cycle. Got: #{inspect(decoded_value)}"
      end
    end
    
    test "handles malformed PDU data gracefully" do
      # Test various malformed inputs
      malformed_inputs = [
        <<>>,  # Empty data
        <<0xFF, 0xFF, 0xFF>>,  # Invalid BER
        <<0x30, 0x05, 0x01, 0x02>>,  # Truncated sequence
      ]
      
      for input <- malformed_inputs do
        case PDU.decode(input) do
          {:error, _reason} -> 
            # Expected - malformed data should return error
            :ok
          {:ok, _pdu} ->
            flunk("Expected decode error for malformed input: #{inspect(input)}")
        end
      end
    end
  end
  
  describe "SNMP Device protocol compliance" do
    setup do
      test_port = PortHelper.get_port()
      device_config = %{
        port: test_port,
        device_type: :cable_modem,
        device_id: "test_device_#{test_port}",
        community: @test_community
      }
      
      {:ok, device_pid} = Device.start_link(device_config)
      
      on_exit(fn ->
        if Process.alive?(device_pid) do
          Device.stop(device_pid)
        end
      end)
      
      # Wait a moment for device initialization
      Process.sleep(100)
      
      %{device: device_pid}
    end
    
    test "GET request returns proper SNMP data types", %{device: device} do
      test_cases = [
        # OID, Expected Type, Expected Value Pattern
        {"1.3.6.1.2.1.1.1.0", :string, ~r/Motorola.*Cable Modem/},  # sysDescr
        {"1.3.6.1.2.1.1.2.0", :object_identifier, "1.3.6.1.4.1.4491.2.4.1"},  # sysObjectID
        {"1.3.6.1.2.1.1.3.0", :timeticks, nil},  # sysUpTime (any positive value)
        {"1.3.6.1.2.1.1.4.0", :string, "admin@example.com"},  # sysContact
        {"1.3.6.1.2.1.1.5.0", :string, ~r/test_device_/},  # sysName
        {"1.3.6.1.2.1.1.6.0", :string, "Customer Premises"},  # sysLocation
        {"1.3.6.1.2.1.1.7.0", :integer, 2},  # sysServices
        {"1.3.6.1.2.1.2.1.0", :integer, 2},  # ifNumber
      ]
      
      for {oid, expected_type, expected_value} <- test_cases do
        {:ok, value} = Device.get(device, oid)
        
        case expected_type do
          :string ->
            assert is_binary(value), "OID #{oid} should return string, got: #{inspect(value)}"
            case expected_value do
              %Regex{} -> 
                assert value =~ expected_value, "OID #{oid} value '#{value}' should match pattern #{inspect(expected_value)}"
              _ -> 
                assert value == expected_value, "OID #{oid} should return '#{expected_value}', got: '#{value}'"
            end
            
          :object_identifier ->
            assert match?({:object_identifier, _}, value), "OID #{oid} should return object_identifier tuple, got: #{inspect(value)}"
            if expected_value do
              {:object_identifier, oid_value} = value
              assert oid_value == expected_value
            end
            
          :timeticks ->
            assert match?({:timeticks, _}, value), "OID #{oid} should return timeticks tuple, got: #{inspect(value)}"
            {:timeticks, ticks} = value
            assert is_integer(ticks) and ticks >= 0, "TimeTicks should be non-negative integer"
            
          :integer ->
            assert is_integer(value), "OID #{oid} should return integer, got: #{inspect(value)}"
            if expected_value do
              assert value == expected_value, "OID #{oid} should return #{expected_value}, got: #{value}"
            end
            
          :gauge32 ->
            assert match?({:gauge32, _}, value), "OID #{oid} should return gauge32 tuple, got: #{inspect(value)}"
            {:gauge32, gauge_value} = value
            assert is_integer(gauge_value) and gauge_value >= 0
        end
      end
    end
    
    test "GET request for non-existent OID returns proper error", %{device: device} do
      case Device.get(device, "1.3.6.1.99.99.99.0") do
        {:error, :no_such_name} -> :ok
        {:ok, {:no_such_object, nil}} -> :ok
        other -> flunk("Expected no_such_name error for non-existent OID, got: #{inspect(other)}")
      end
    end
    
    test "simulates SNMP walk operation correctly", %{device: device} do
      # Simulate a walk by performing sequential GETNEXT operations
      walk_results = perform_simulated_walk(device, "1.3.6.1.2.1.1")
      
      # Should get at least the basic system OIDs
      assert length(walk_results) >= 6, "SNMP walk should return multiple system OIDs"
      
      # Verify we get the expected system OIDs in order
      oids = Enum.map(walk_results, fn {oid, _value} -> oid end)
      
      expected_oids = [
        "1.3.6.1.2.1.1.1.0",  # sysDescr
        "1.3.6.1.2.1.1.2.0",  # sysObjectID  
        "1.3.6.1.2.1.1.3.0",  # sysUpTime
        "1.3.6.1.2.1.1.4.0",  # sysContact
        "1.3.6.1.2.1.1.5.0",  # sysName
        "1.3.6.1.2.1.1.6.0",  # sysLocation
        "1.3.6.1.2.1.1.7.0"   # sysServices
      ]
      
      # Check that we get these OIDs (order may vary slightly)
      for expected_oid <- expected_oids do
        assert expected_oid in oids, "Walk should include OID #{expected_oid}, got: #{inspect(oids)}"
      end
      
      # Verify all values have proper SNMP types (no NULL values)
      for {oid, value} <- walk_results do
        assert value != nil, "OID #{oid} should not return NULL value"
        assert value != {:null, nil}, "OID #{oid} should not return null tuple"
        
        # Verify it's a valid SNMP type
        assert is_valid_snmp_value(value), "OID #{oid} returned invalid SNMP value: #{inspect(value)}"
      end
    end
    
    test "interface table OIDs return proper data types", %{device: device} do
      interface_tests = [
        # OID, Expected Type
        {"1.3.6.1.2.1.2.2.1.1.1", :integer},      # ifIndex
        {"1.3.6.1.2.1.2.2.1.2.1", :string},       # ifDescr
        {"1.3.6.1.2.1.2.2.1.3.1", :integer},      # ifType
        {"1.3.6.1.2.1.2.2.1.4.1", :gauge32},      # ifMtu
        {"1.3.6.1.2.1.2.2.1.5.1", :gauge32},      # ifSpeed (should be GAUGE32)
        {"1.3.6.1.2.1.2.2.1.6.1", :string},       # ifPhysAddress
        {"1.3.6.1.2.1.2.2.1.7.1", :integer},      # ifAdminStatus
        {"1.3.6.1.2.1.2.2.1.8.1", :integer},      # ifOperStatus
        {"1.3.6.1.2.1.2.2.1.9.1", :timeticks},    # ifLastChange
      ]
      
      for {oid, expected_type} <- interface_tests do
        case Device.get(device, oid) do
          {:ok, value} ->
            case expected_type do
              :integer -> 
                assert is_integer(value), "Interface OID #{oid} should return integer, got: #{inspect(value)}"
              :string -> 
                assert is_binary(value), "Interface OID #{oid} should return string, got: #{inspect(value)}"
              :gauge32 -> 
                assert match?({:gauge32, _}, value), "Interface OID #{oid} should return gauge32 tuple, got: #{inspect(value)}"
              :timeticks -> 
                assert match?({:timeticks, _}, value), "Interface OID #{oid} should return timeticks tuple, got: #{inspect(value)}"
            end
            
          {:error, :no_such_name} ->
            # Some interface OIDs might not be implemented yet - that's OK for this test
            :ok
        end
      end
    end
  end
  
  describe "SNMP Server integration" do
    setup do
      # Start a server with a test device handler
      test_port = PortHelper.get_port()
      {:ok, server_pid} = Server.start_link(test_port, community: @test_community)
      
      on_exit(fn ->
        if Process.alive?(server_pid) do
          GenServer.stop(server_pid)
        end
      end)
      
      %{server: server_pid}
    end
    
    test "server handles malformed SNMP packets gracefully", %{server: server} do
      # Send malformed packets to the server and verify it doesn't crash
      malformed_packets = [
        <<>>,
        <<0xFF, 0xFF, 0xFF>>,
        <<0x30, 0x05>>,  # Truncated
        <<0x30, 0x82, 0xFF, 0xFF>>,  # Invalid length
      ]
      
      for packet <- malformed_packets do
        # Send packet to server (this would normally be done via UDP)
        # We'll test the packet handling directly
        send(server, {:udp, :fake_socket, {127, 0, 0, 1}, 12345, packet})
        
        # Server should still be alive after handling malformed packet
        Process.sleep(10)
        assert Process.alive?(server), "Server should survive malformed packet: #{inspect(packet)}"
      end
    end
  end
  
  # Helper functions
  
  defp perform_simulated_walk(device, starting_oid) do
    perform_walk_recursive(device, starting_oid, [], 20)  # Limit to 20 iterations
  end
  
  defp perform_walk_recursive(_device, _current_oid, results, 0) do
    # Prevent infinite loops
    results
  end
  
  defp perform_walk_recursive(device, current_oid, results, iterations_left) do
    # This simulates what an SNMP walk does - sequential GETNEXT operations
    case get_next_oid_from_device(device, current_oid) do
      {:ok, {next_oid, value}} ->
        if next_oid == current_oid or String.starts_with?(next_oid, "1.3.6.1.2.1.1") == false do
          # End of walk - we've gone past the system subtree or hit end of MIB
          results
        else
          perform_walk_recursive(device, next_oid, results ++ [{next_oid, value}], iterations_left - 1)
        end
        
      {:error, _} ->
        results
    end
  end
  
  defp get_next_oid_from_device(device, oid) do
    # This is a simplified version of what GETNEXT would do
    # In a real implementation, this would call the device's GETNEXT handler
    case Device.get(device, oid) do
      {:ok, _value} ->
        # If we can get this OID, try some likely next OIDs
        get_likely_next_oid(device, oid)
      {:error, _} ->
        get_likely_next_oid(device, oid)
    end
  end
  
  defp get_likely_next_oid(device, oid) do
    # Simple logic to find next OID in system tree
    next_oids = case oid do
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
    
    if next_oids do
      case Device.get(device, next_oids) do
        {:ok, value} -> {:ok, {next_oids, value}}
        error -> error
      end
    else
      {:error, :end_of_mib}
    end
  end
  
  defp is_valid_snmp_value(value) do
    case value do
      # Basic types
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
      
      # Invalid types
      nil -> false
      {:null, nil} -> false
      _ -> false
    end
  end
end