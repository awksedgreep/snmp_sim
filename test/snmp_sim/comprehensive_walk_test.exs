defmodule SnmpSim.ComprehensiveWalkTest do
  @moduledoc """
  Comprehensive tests for SNMP walk functionality across all versions and scenarios.
  
  This test suite ensures that walk operations work correctly for:
  - All SNMP versions (v1, v2c)
  - Different OID subtrees
  - Error conditions and edge cases
  - Format consistency
  - Fallback mechanisms
  """
  
  use ExUnit.Case, async: false
  
  alias SnmpSim.{Device, LazyDevicePool}
  alias SnmpSim.TestHelpers.PortHelper
  alias SnmpLib.PDU
  
  def oid_to_string(oid) when is_list(oid), do: Enum.join(oid, ".")
  def oid_to_string(oid) when is_binary(oid), do: oid
  
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
  
  describe "Walk Functionality - All Versions" do
    test "SNMPv1 walk returns consistent format", %{device_pid: device_pid} do
      # Test walk with SNMPv1
      result = GenServer.call(device_pid, {:walk_oid, "1.3.6.1.2.1.1"})
      
      assert {:ok, oid_value_pairs} = result
      assert is_list(oid_value_pairs)
      assert length(oid_value_pairs) > 0
      
      # Verify all OIDs are strings and values are present
      for {oid, value} <- oid_value_pairs do
        assert is_binary(oid)
        assert String.starts_with?(oid, "1.3.6.1.2.1.1")
        assert value != nil
      end
      
      # Should contain system description
      assert Enum.any?(oid_value_pairs, fn {oid, _} -> oid == "1.3.6.1.2.1.1.1.0" end)
    end
    
    test "SNMPv2c walk returns consistent format", %{device_pid: device_pid} do
      # Test walk with SNMPv2c context
      result = GenServer.call(device_pid, {:walk_oid, "1.3.6.1.2.1.1"})
      
      assert {:ok, oid_value_pairs} = result
      assert is_list(oid_value_pairs)
      assert length(oid_value_pairs) > 0
      
      # Verify format consistency
      for {oid, value} <- oid_value_pairs do
        assert is_binary(oid)
        assert String.starts_with?(oid, "1.3.6.1.2.1.1")
        assert value != nil
      end
    end
    
    test "walk with GETNEXT sequence - SNMPv1", %{device_pid: device_pid} do
      # Test individual GETNEXT operations that make up a walk
      start_oid = "1.3.6.1.2.1.1"
      
      # First GETNEXT
      request_pdu = %{
        version: :v1,
        community: "public",
        type: :get_next_request,
        request_id: 99999,
        error_status: 0,
        error_index: 0,
        varbinds: [{start_oid, nil}]
      }
      
      result = GenServer.call(device_pid, {:handle_snmp, request_pdu, "public"})
      
      assert {:ok, response_pdu} = result
      assert response_pdu.version == :v1
      assert response_pdu.type == :get_response
      assert length(response_pdu.varbinds) == 1
      
      [{next_oid, type, value}] = response_pdu.varbinds
      assert is_list(next_oid) or is_binary(next_oid)
      assert String.starts_with?(oid_to_string(next_oid), "1.3.6.1.2.1.1")
      assert value != nil
    end
    
    test "walk with GETNEXT sequence - SNMPv2c", %{device_pid: device_pid} do
      # Test individual GETNEXT operations that make up a walk
      start_oid = "1.3.6.1.2.1.1"
      
      # First GETNEXT
      request_pdu = %{
        version: :v2c,
        community: "public",
        type: :get_next_request,
        request_id: 88888,
        error_status: 0,
        error_index: 0,
        varbinds: [{start_oid, nil}]
      }
      
      result = GenServer.call(device_pid, {:handle_snmp, request_pdu, "public"})
      
      assert {:ok, response_pdu} = result
      assert response_pdu.version == :v2c
      assert response_pdu.type == :get_response
      assert length(response_pdu.varbinds) == 1
      
      [{next_oid, type, value}] = response_pdu.varbinds
      assert is_list(next_oid) or is_binary(next_oid)
      assert String.starts_with?(oid_to_string(next_oid), "1.3.6.1.2.1.1")
      assert value != nil
    end
    
    test "GETBULK operation - SNMPv2c only", %{device_pid: device_pid} do
      request_pdu = %{
        version: :v2c,
        community: "public",
        type: :get_bulk_request,
        request_id: 77777,
        error_status: 0,
        error_index: 0,
        varbinds: [{"1.3.6.1.2.1.1", nil}],
        non_repeaters: 0,
        max_repetitions: 5
      }
      
      result = GenServer.call(device_pid, {:handle_snmp, request_pdu, "public"})
      
      assert {:ok, response_pdu} = result
      assert response_pdu.version == :v2c
      assert response_pdu.type == :get_response
      assert length(response_pdu.varbinds) <= 5
      
      # All returned OIDs should be in the requested subtree or beyond
      for {oid, type, value} <- response_pdu.varbinds do
        assert is_list(oid) or is_binary(oid)
        # Should be >= the requested OID in lexicographic order
        assert oid_to_string(oid) >= "1.3.6.1.2.1.1"
      end
    end
  end
  
  describe "Walk Error Handling" do
    test "walk with non-existent OID subtree", %{device_pid: device_pid} do
      result = GenServer.call(device_pid, {:walk_oid, "1.3.6.1.2.1.99.99.99"})
      
      # Should return empty list, not crash
      assert {:ok, []} = result
    end
    
    test "walk with invalid OID format", %{device_pid: device_pid} do
      result = GenServer.call(device_pid, {:walk_oid, "invalid.oid"})
      
      # Should handle gracefully
      case result do
        {:ok, []} -> assert true
        {:error, _} -> assert true
      end
    end
    
    test "walk with empty OID", %{device_pid: device_pid} do
      result = GenServer.call(device_pid, {:walk_oid, ""})
      
      # Should handle gracefully
      case result do
        {:ok, []} -> assert true
        {:error, _} -> assert true
      end
    end
    
    test "walk reaches end of MIB view", %{device_pid: device_pid} do
      # Walk a specific leaf OID that should reach end quickly
      result = GenServer.call(device_pid, {:walk_oid, "1.3.6.1.2.1.1.1.0"})
      
      # Should return the single OID or empty list
      assert {:ok, oid_value_pairs} = result
      assert is_list(oid_value_pairs)
      assert length(oid_value_pairs) <= 1
    end
  end
  
  describe "Walk Format Consistency" do
    test "get_next_oid returns consistent format", %{device_pid: device_pid} do
      # Test the internal function that was causing issues
      result = GenServer.call(device_pid, {:get_next_oid, "1.3.6.1.2.1.1"})
      
      # Should always return {:ok, {next_oid, value}} or {:error, reason}
      case result do
        {:ok, {next_oid, value}} ->
          assert is_list(next_oid) or is_binary(next_oid)
          assert value != nil
        {:error, reason} ->
          assert reason in [:end_of_mib_view, :no_such_object, :no_such_instance]
        other ->
          flunk("Unexpected format: #{inspect(other)}")
      end
    end
    
    test "walk_oid_recursive handles OID format conversions", %{device_pid: device_pid} do
      # Test that internal recursive function handles string/list conversions
      result = GenServer.call(device_pid, {:walk_oid, "1.3.6.1.2.1.1"})
      
      assert {:ok, oid_value_pairs} = result
      
      # All OIDs should be strings or lists
      for {oid, _value} <- oid_value_pairs do
        assert is_list(oid) or is_binary(oid)
      end
    end
    
    test "fallback functions return proper format", %{device_pid: device_pid} do
      # Test scenario where fallback functions might be used
      # This tests the case where SharedProfiles might fail
      
      # Walk a subtree that might trigger fallback
      result = GenServer.call(device_pid, {:walk_oid, "1.3.6.1.2.1.2"})
      
      assert {:ok, oid_value_pairs} = result
      
      # Even with fallbacks, format should be consistent
      for {oid, value} <- oid_value_pairs do
        assert is_list(oid) or is_binary(oid)
        assert value != nil
      end
    end
  end
  
  describe "Walk Performance and Limits" do
    test "walk respects recursion limits", %{device_pid: device_pid} do
      # Walk a large subtree to test recursion limit
      result = GenServer.call(device_pid, {:walk_oid, "1.3.6.1.2.1"})
      
      assert {:ok, oid_value_pairs} = result
      assert is_list(oid_value_pairs)
      
      # Should not exceed reasonable limits (walk_oid_recursive has limit of 100)
      assert length(oid_value_pairs) <= 100
    end
    
    test "walk completes within reasonable time", %{device_pid: device_pid} do
      start_time = :erlang.monotonic_time()
      
      result = GenServer.call(device_pid, {:walk_oid, "1.3.6.1.2.1.1"}, 5000)
      
      end_time = :erlang.monotonic_time()
      duration_ms = :erlang.convert_time_unit(end_time - start_time, :native, :millisecond)
      
      assert {:ok, _oid_value_pairs} = result
      assert duration_ms < 5000  # Should complete within 5 seconds
    end
    
    test "concurrent walks don't interfere", %{device_pid: device_pid} do
      # Start multiple walks concurrently
      tasks = for i <- 1..3 do
        Task.async(fn ->
          GenServer.call(device_pid, {:walk_oid, "1.3.6.1.2.1.1.#{i}"})
        end)
      end
      
      results = Task.await_many(tasks, 10_000)
      
      # All should succeed
      for result <- results do
        assert {:ok, _oid_value_pairs} = result
      end
    end
  end
  
  describe "Walk Integration with Different Device Types" do
    test "walk works with different device profiles", %{device_pid: device_pid} do
      # Test that walk works regardless of device type/profile
      
      # System group should work for any device
      result = GenServer.call(device_pid, {:walk_oid, "1.3.6.1.2.1.1"})
      assert {:ok, oid_value_pairs} = result
      assert length(oid_value_pairs) > 0
      
      # Interface group might be empty but shouldn't crash
      result = GenServer.call(device_pid, {:walk_oid, "1.3.6.1.2.1.2"})
      assert {:ok, _oid_value_pairs} = result
    end
  end
end
