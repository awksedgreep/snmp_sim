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

      verify_response_data(response_pdu, "1.3.6.1.2.1.1.1.0")
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

      verify_response_data(response_pdu, "1.3.6.1.2.1.1.1.0")
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

      verify_getnext_response(response_pdu, "1.3.6.1.2.1.1", "1.3.6.1.2.1.1.1.0")
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

      verify_getnext_response(response_pdu, "1.3.6.1.2.1.1", "1.3.6.1.2.1.1.1.0")
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
        # ifInOctets
        varbinds: [{"1.3.6.1.2.1.2.2.1.10.1", nil}]
      }

      result = GenServer.call(device_pid, {:handle_snmp, request_pdu, %{}})

      assert {:ok, response_pdu} = result
      assert response_pdu.version == :v1
      verify_counter32_response(response_pdu, "1.3.6.1.2.1.2.2.1.10.1")
    end

    test "SNMPv2c returns Counter32 values correctly", %{device_pid: device_pid} do
      request_pdu = %{
        version: :v2c,
        community: "public",
        type: :get_request,
        request_id: 22222,
        error_status: 0,
        error_index: 0,
        # ifInOctets
        varbinds: [{"1.3.6.1.2.1.2.2.1.10.1", nil}]
      }

      result = GenServer.call(device_pid, {:handle_snmp, request_pdu, %{}})

      assert {:ok, response_pdu} = result
      assert response_pdu.version == :v2c
      verify_counter32_response(response_pdu, "1.3.6.1.2.1.2.2.1.10.1")
    end
  end

  defp verify_response_data(pdu, expected_oid_str) do
    assert length(pdu.varbinds) == 1, "Response should have exactly 1 varbind"
    
    {oid, _type, value} = List.first(pdu.varbinds)
    oid_str = case oid do
      oid_list when is_list(oid_list) -> Enum.join(oid_list, ".")
      oid_str when is_binary(oid_str) -> oid_str
    end
    assert oid_str == expected_oid_str, "Response OID should match request"
    assert is_binary(value), "sysDescr value should be a string"
    assert String.length(value) > 0, "sysDescr value should not be empty"
  end
  
  defp verify_getnext_response(pdu, requested_oid_str, expected_next_oid_str) do
    assert length(pdu.varbinds) == 1, "Response should have exactly 1 varbind"
    
    {oid, _type, value} = List.first(pdu.varbinds)
    oid_str = case oid do
      oid_list when is_list(oid_list) -> Enum.join(oid_list, ".")
      oid_str when is_binary(oid_str) -> oid_str
    end
    assert oid_str == expected_next_oid_str, "GETNEXT should return next OID: expected #{expected_next_oid_str}, got #{oid_str}"
    assert String.starts_with?(oid_str, requested_oid_str), "Next OID should be lexicographically after requested OID"
    assert value != nil, "Value should not be nil"
    
    case oid_str do
      "1.3.6.1.2.1.1.2.0" ->
        assert is_binary(value), "sysObjectID value should be a string"
      "1.3.6.1.2.1.1.3.0" ->
        assert is_integer(value) or match?({:timeticks, _}, value), "sysUpTime value should be integer or timeticks"
      _ ->
        assert value != nil, "Value for OID #{oid_str} should not be nil"
    end
  end

  defp verify_counter32_response(pdu, expected_oid_str) do
    assert length(pdu.varbinds) == 1, "Response should have exactly 1 varbind"
    
    {oid, _type, value} = List.first(pdu.varbinds)
    oid_str = case oid do
      oid_list when is_list(oid_list) -> Enum.join(oid_list, ".")
      oid_str when is_binary(oid_str) -> oid_str
    end
    assert oid_str == expected_oid_str, "Response OID should match request"
    assert is_integer(value), "Counter32 value should be an integer"
    assert value >= 0, "Counter32 value should be non-negative"
  end
end
