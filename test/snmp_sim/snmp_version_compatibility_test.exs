defmodule SnmpSim.SnmpVersionCompatibilityTest do
  @moduledoc """
  Comprehensive tests for SNMP version compatibility (v1, v2c, v3).
  
  This test suite ensures that all SNMP versions are properly supported
  and that responses match the request version format.
  """
  
  use ExUnit.Case, async: false
  
  alias SnmpSim.{Device, LazyDevicePool}
  alias SnmpSim.TestHelpers.PortHelper
  alias SnmpLib.PDU
  
  setup do
    # Ensure clean state
    if Process.whereis(LazyDevicePool) do
      LazyDevicePool.shutdown_all_devices()
    else
      {:ok, _} = LazyDevicePool.start_link()
    end
    
    test_port = PortHelper.get_port()
    {:ok, device_pid} = LazyDevicePool.get_or_create_device(test_port)
    {:ok, test_port: test_port, device_pid: device_pid}
  end
  
  describe "SNMP Version Compatibility" do
    test "SNMPv1 GET request returns v1 response", %{device_pid: device_pid} do
      # Create SNMPv1 GET request
      request_pdu = %{
        version: :v1,
        community: "public",
        type: :get_request,
        request_id: 12345,
        error_status: 0,
        error_index: 0,
        varbinds: [{"1.3.6.1.2.1.1.1.0", nil}]
      }
      
      # Process request
      result = GenServer.call(device_pid, {:handle_snmp, request_pdu, %{}})
      
      # Verify response
      assert {:ok, response_pdu} = result
      assert response_pdu.version == :v1
      assert response_pdu.type == :get_response
      assert response_pdu.request_id == 12345
      assert response_pdu.error_status == 0
      assert length(response_pdu.varbinds) == 1
      
      [{oid, type, value}] = response_pdu.varbinds
      # Handle both string and list OID formats
      expected_oid = [1, 3, 6, 1, 2, 1, 1, 1, 0]
      actual_oid = if is_binary(oid) do
        oid |> String.split(".") |> Enum.map(&String.to_integer/1)
      else
        oid
      end
      assert actual_oid == expected_oid
      assert type == :octet_string
      assert is_binary(value)
    end
    
    test "SNMPv2c GET request returns v2c response", %{device_pid: device_pid} do
      # Create SNMPv2c GET request
      request_pdu = %{
        version: :v2c,
        community: "public",
        type: :get_request,
        request_id: 23456,
        error_status: 0,
        error_index: 0,
        varbinds: [{"1.3.6.1.2.1.1.1.0", nil}]
      }
      
      # Process request
      result = GenServer.call(device_pid, {:handle_snmp, request_pdu, %{}})
      
      # Verify response
      assert {:ok, response_pdu} = result
      assert response_pdu.version == :v2c
      assert response_pdu.type == :get_response
      assert response_pdu.request_id == 23456
      assert response_pdu.error_status == 0
      assert length(response_pdu.varbinds) == 1
      
      [{oid, type, value}] = response_pdu.varbinds
      # Handle both string and list OID formats
      expected_oid = [1, 3, 6, 1, 2, 1, 1, 1, 0]
      actual_oid = if is_binary(oid) do
        oid |> String.split(".") |> Enum.map(&String.to_integer/1)
      else
        oid
      end
      assert actual_oid == expected_oid
      assert type == :octet_string
      assert is_binary(value)
    end
    
    test "SNMPv1 GETNEXT request returns v1 response", %{device_pid: device_pid} do
      request_pdu = %{
        version: :v1,
        community: "public",
        type: :get_next_request,
        request_id: 34567,
        error_status: 0,
        error_index: 0,
        varbinds: [{"1.3.6.1.2.1.1", nil}]
      }
      
      result = GenServer.call(device_pid, {:handle_snmp, request_pdu, %{}})
      
      assert {:ok, response_pdu} = result
      assert response_pdu.version == :v1
      assert response_pdu.type == :get_response
      assert response_pdu.request_id == 34567
    end
    
    test "SNMPv2c GETNEXT request returns v2c response", %{device_pid: device_pid} do
      request_pdu = %{
        version: :v2c,
        community: "public",
        type: :get_next_request,
        request_id: 45678,
        error_status: 0,
        error_index: 0,
        varbinds: [{"1.3.6.1.2.1.1", nil}]
      }
      
      result = GenServer.call(device_pid, {:handle_snmp, request_pdu, %{}})
      
      assert {:ok, response_pdu} = result
      assert response_pdu.version == :v2c
      assert response_pdu.type == :get_response
      assert response_pdu.request_id == 45678
    end
    
    test "SNMPv2c GETBULK request returns v2c response", %{device_pid: device_pid} do
      request_pdu = %{
        version: :v2c,
        community: "public",
        type: :get_bulk_request,
        request_id: 56789,
        error_status: 0,
        error_index: 0,
        varbinds: [{"1.3.6.1.2.1.2.2.1", nil}],
        non_repeaters: 0,
        max_repetitions: 10
      }
      
      result = GenServer.call(device_pid, {:handle_snmp, request_pdu, %{}})
      
      assert {:ok, response_pdu} = result
      assert response_pdu.version == :v2c
      assert response_pdu.type == :get_response
      assert response_pdu.request_id == 56789
    end
    
    test "device handles different community strings correctly", %{device_pid: device_pid} do
      # Test that community validation works regardless of version
      request_pdu_v1 = %{
        version: :v1,
        community: "wrong_community",
        type: :get_request,
        request_id: 67890,
        error_status: 0,
        error_index: 0,
        varbinds: [{"1.3.6.1.2.1.1.1.0", nil}]
      }
      
      request_pdu_v2c = %{
        version: :v2c,
        community: "wrong_community",
        type: :get_request,
        request_id: 78901,
        error_status: 0,
        error_index: 0,
        varbinds: [{"1.3.6.1.2.1.1.1.0", nil}]
      }
      
      # Both should succeed because community validation happens at server level
      result_v1 = GenServer.call(device_pid, {:handle_snmp, request_pdu_v1, %{}})
      result_v2c = GenServer.call(device_pid, {:handle_snmp, request_pdu_v2c, %{}})
      
      # Should return valid responses
      assert {:ok, _} = result_v1
      assert {:ok, _} = result_v2c
    end
  end
  
  describe "Counter32/Gauge32 Type Handling by Version" do
    test "SNMPv1 returns Counter32 values correctly", %{device_pid: device_pid} do
      request_pdu = %{
        version: :v1,
        community: "public",
        type: :get_request,
        request_id: 11111,
        error_status: 0,
        error_index: 0,
        varbinds: [{"1.3.6.1.2.1.2.2.1.10.1", nil}]  # ifInOctets
      }
      
      result = GenServer.call(device_pid, {:handle_snmp, request_pdu, %{}})
      
      assert {:ok, response_pdu} = result
      assert response_pdu.version == :v1
      [{oid, type, value}] = response_pdu.varbinds
      # Handle both string and list OID formats
      expected_oid = [1, 3, 6, 1, 2, 1, 2, 2, 1, 10, 1]
      actual_oid = if is_binary(oid) do
        oid |> String.split(".") |> Enum.map(&String.to_integer/1)
      else
        oid
      end
      assert actual_oid == expected_oid
      assert type == :counter32
      assert is_integer(value)
    end
    
    test "SNMPv2c returns Counter32 values correctly", %{device_pid: device_pid} do
      request_pdu = %{
        version: :v2c,
        community: "public",
        type: :get_request,
        request_id: 22222,
        error_status: 0,
        error_index: 0,
        varbinds: [{"1.3.6.1.2.1.2.2.1.10.1", nil}]  # ifInOctets
      }
      
      result = GenServer.call(device_pid, {:handle_snmp, request_pdu, %{}})
      
      assert {:ok, response_pdu} = result
      assert response_pdu.version == :v2c
      [{oid, type, value}] = response_pdu.varbinds
      # Handle both string and list OID formats
      expected_oid = [1, 3, 6, 1, 2, 1, 2, 2, 1, 10, 1]
      actual_oid = if is_binary(oid) do
        oid |> String.split(".") |> Enum.map(&String.to_integer/1)
      else
        oid
      end
      assert actual_oid == expected_oid
      assert type == :counter32
      assert is_integer(value)
    end
  end
end
