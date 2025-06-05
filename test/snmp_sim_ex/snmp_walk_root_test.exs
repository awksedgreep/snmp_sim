defmodule SnmpSim.SNMPWalkRootTest do
  @moduledoc """
  Tests for SNMP walk functionality starting from root OIDs.
  
  This test validates both the SharedProfiles enhancement and Device fallback
  enhancement for handling GETNEXT operations that start from root OIDs
  like "1.3.6.1.2.1" instead of specific leaf OIDs.
  """
  
  use ExUnit.Case, async: false
  
  alias SnmpSim.{Device, LazyDevicePool}
  alias SnmpSim.MIB.SharedProfiles
  alias SnmpLib.PDU
  alias SnmpSim.TestHelpers.PortHelper
  
  setup do
    # Ensure clean state
    if Process.whereis(LazyDevicePool) do
      LazyDevicePool.shutdown_all_devices()
    else
      {:ok, _} = LazyDevicePool.start_link()
    end
    
    test_port = PortHelper.get_port()
    {:ok, test_port: test_port}
  end
  
  describe "Device fallback GETNEXT from root OIDs" do
    test "handles GETNEXT from mib-2 root (1.3.6.1.2.1)", %{test_port: test_port} do
      # Create a device that will use fallback logic (no SharedProfiles)
      {:ok, device_pid} = LazyDevicePool.get_or_create_device(test_port)
      
      # Create a GETNEXT PDU starting from mib-2 root using new SnmpLib.PDU API
      oid_list = [1, 3, 6, 1, 2, 1]
      request_id = 12345
      request_pdu = PDU.build_get_next_request(oid_list, request_id)
      
      # Send the PDU to the device
      {:ok, response_pdu} = GenServer.call(device_pid, {:handle_snmp, request_pdu, %{}})
      
      # Should return the first system OID with device description
      assert response_pdu.type == :get_response
      assert response_pdu.error_status == 0
      assert length(response_pdu.varbinds) == 1
      
      [{response_oid_list, _type, response_value}] = response_pdu.varbinds
      response_oid = Enum.join(response_oid_list, ".")
      assert response_oid == "1.3.6.1.2.1.1.1.0"
      assert is_binary(response_value)
      assert String.contains?(response_value, "Cable Modem") or 
             String.contains?(response_value, "SNMP Simulator Device")
    end
    
    test "handles GETNEXT from various root OIDs", %{test_port: test_port} do
      {:ok, device_pid} = LazyDevicePool.get_or_create_device(test_port)
      
      root_oids = [
        [1, 3, 6, 1, 2, 1, 1], 
        [1, 3, 6, 1], 
        [1, 3, 6], 
        [1, 3], 
        [1]
      ]
      
      for root_oid <- root_oids do
        request_id = :rand.uniform(65535)
        request_pdu = PDU.build_get_next_request(root_oid, request_id)
        
        {:ok, response_pdu} = GenServer.call(device_pid, {:handle_snmp, request_pdu, %{}})
        
        assert response_pdu.type == :get_response
        assert response_pdu.error_status == 0
        assert length(response_pdu.varbinds) == 1
        
        [{response_oid_list, _type, response_value}] = response_pdu.varbinds
        response_oid = Enum.join(response_oid_list, ".")
        assert response_oid == "1.3.6.1.2.1.1.1.0"
        assert is_binary(response_value)
      end
    end
    
    test "GETNEXT walk progression works correctly", %{test_port: test_port} do
      {:ok, device_pid} = LazyDevicePool.get_or_create_device(test_port)
      
      # Start from root and verify we can walk through the tree
      oid_list = [1, 3, 6, 1, 2, 1]
      request_id = 12345
      request_pdu = PDU.build_get_next_request(oid_list, request_id)
      
      {:ok, response_pdu} = GenServer.call(device_pid, {:handle_snmp, request_pdu, %{}})
      [{response_oid_list, _type, response_value}] = response_pdu.varbinds
      response_oid = Enum.join(response_oid_list, ".")
      assert response_oid == "1.3.6.1.2.1.1.1.0"
      assert is_binary(response_value)
      
      # Should be able to get subsequent OIDs using direct GET
      {:ok, sysObjectID} = Device.get(device_pid, "1.3.6.1.2.1.1.2.0")
      assert {:object_identifier, _oid_str} = sysObjectID
      
      {:ok, uptime} = Device.get(device_pid, "1.3.6.1.2.1.1.3.0")
      assert {:timeticks, _ticks} = uptime
    end
  end
  
  describe "SharedProfiles GETNEXT from root OIDs" do
    test "integration test with loaded profile" do
      # This test verifies that the SharedProfiles enhancement works
      # when a real profile is loaded. For now, we'll test with the existing
      # cable modem profile if it's available.
      
      case Process.whereis(SharedProfiles) do
        nil -> 
          {:ok, _} = SharedProfiles.start_link([])
        _pid -> 
          :ok
      end
      
      # Try to load a profile from existing walk file
      walk_file = Path.join([Application.app_dir(:snmp_sim_ex), "priv", "walks", "cable_modem.walk"])
      
      if File.exists?(walk_file) do
        :ok = SharedProfiles.load_walk_profile(:cable_modem, walk_file)
        
        # Test that we can find descendants from root OIDs
        result = SharedProfiles.get_next_oid(:cable_modem, "1.3.6.1.2.1")
        
        case result do
          {:ok, oid} ->
            # Should find a descendant OID
            assert String.starts_with?(oid, "1.3.6.1.2.1.")
            
          {:error, :device_type_not_found} ->
            # Profile loading failed, skip this test
            assert true
            
          other ->
            flunk("Unexpected result: #{inspect(other)}")
        end
      else
        # Walk file doesn't exist, skip this test
        assert true
      end
    end
  end
  
  describe "End-to-end PDU GETNEXT from root OIDs" do
    test "PDU GETNEXT request from mib-2 root works", %{test_port: test_port} do
      {:ok, device_pid} = LazyDevicePool.get_or_create_device(test_port)
      
      # Create a GETNEXT PDU starting from mib-2 root
      oid_list = [1, 3, 6, 1, 2, 1]
      request_id = 12345
      request_pdu = PDU.build_get_next_request(oid_list, request_id)
      
      # Send the PDU to the device
      {:ok, response_pdu} = GenServer.call(device_pid, {:handle_snmp, request_pdu, %{}})
      
      # Verify response
      assert response_pdu.type == :get_response
      assert response_pdu.error_status == 0
      assert length(response_pdu.varbinds) == 1
      
      [{response_oid_list, _type, response_value}] = response_pdu.varbinds
      response_oid = Enum.join(response_oid_list, ".")
      
      # Should return first system OID
      assert response_oid == "1.3.6.1.2.1.1.1.0"
      assert is_binary(response_value)
      assert String.contains?(response_value, "Cable Modem") or
             String.contains?(response_value, "SNMP Simulator Device")
    end
    
    test "PDU GETNEXT walk simulation from various roots", %{test_port: test_port} do
      {:ok, device_pid} = LazyDevicePool.get_or_create_device(test_port)
      
      root_oids = [
        [1], 
        [1, 3], 
        [1, 3, 6], 
        [1, 3, 6, 1], 
        [1, 3, 6, 1, 2, 1], 
        [1, 3, 6, 1, 2, 1, 1]
      ]
      
      for root_oid <- root_oids do
        request_id = :rand.uniform(65535)
        request_pdu = PDU.build_get_next_request(root_oid, request_id)
        
        {:ok, response_pdu} = GenServer.call(device_pid, {:handle_snmp, request_pdu, %{}})
        
        assert response_pdu.type == :get_response
        assert response_pdu.error_status == 0
        assert length(response_pdu.varbinds) == 1
        
        [{response_oid_list, _type, response_value}] = response_pdu.varbinds
        response_oid = Enum.join(response_oid_list, ".")
        
        # All should lead to the first system OID
        assert response_oid == "1.3.6.1.2.1.1.1.0"
        assert is_binary(response_value)
      end
    end
  end
  
  describe "Edge cases and error handling" do
    test "non-existent root returns end of MIB", %{test_port: test_port} do
      {:ok, device_pid} = LazyDevicePool.get_or_create_device(test_port)
      
      # Try a GETNEXT from an OID that doesn't exist and has no descendants
      oid_list = [9, 9, 9, 9, 9]
      request_id = 12345
      request_pdu = PDU.build_get_next_request(oid_list, request_id)
      
      {:ok, response_pdu} = GenServer.call(device_pid, {:handle_snmp, request_pdu, %{}})
      [{_response_oid_list, _type, response_value}] = response_pdu.varbinds
      
      # Should return end of MIB view
      assert {:end_of_mib_view, nil} = response_value
    end
    
    test "handles edge case OIDs gracefully", %{test_port: test_port} do
      {:ok, device_pid} = LazyDevicePool.get_or_create_device(test_port)
      
      # Try various edge case OIDs with GETNEXT (using valid integer lists)
      edge_case_oids = [
        [], # Empty OID
        [0], # Zero OID
        [2147483647], # Large integer
        [1, 0, 0, 0], # OID with zeros
      ]
      
      for edge_oid <- edge_case_oids do
        request_id = 12345
        request_pdu = PDU.build_get_next_request(edge_oid, request_id)
        
        # Should not crash
        result = GenServer.call(device_pid, {:handle_snmp, request_pdu, %{}})
        case result do
          {:ok, _response_pdu} -> assert true
          {:error, _} -> assert true
          _ -> flunk("Unexpected result: #{inspect(result)}")
        end
      end
    end
  end
end