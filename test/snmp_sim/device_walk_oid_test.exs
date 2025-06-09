defmodule SnmpSim.DeviceWalkOidTest do
  @moduledoc """
  Tests for the Device.walk_oid functionality that was previously broken.

  This test suite specifically validates the walk_oid_recursive function
  and get_next_oid_value function to ensure they return consistent formats
  and handle OID format conversions properly.
  """

  use ExUnit.Case, async: false

  alias SnmpSim.{LazyDevicePool}
  alias SnmpSim.TestHelpers.PortHelper

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

  describe "Device.walk_oid functionality" do
    test "walk_oid returns consistent format for system group", %{device_pid: device_pid} do
      # Test walking the system group - this was the original failing case
      result = GenServer.call(device_pid, {:walk_oid, "1.3.6.1.2.1.1"})

      # Should return {:ok, list_of_tuples}
      assert {:ok, oid_value_pairs} = result
      assert is_list(oid_value_pairs)
      assert length(oid_value_pairs) > 0

      # Each element should be a {oid_string, type, value} tuple
      for {oid, type, value} <- oid_value_pairs do
        assert is_binary(oid)
        assert is_atom(type)
        assert String.starts_with?(oid, "1.3.6.1.2.1.1")
        assert value != nil
      end

      # Should contain the system description
      system_desc =
        Enum.find(oid_value_pairs, fn {oid, _type, _value} ->
          oid == "1.3.6.1.2.1.1.1.0"
        end)

      assert system_desc != nil
      {_oid, _type, desc_value} = system_desc
      assert is_binary(desc_value)

      assert String.contains?(desc_value, "Cable Modem") or
               String.contains?(desc_value, "SNMP Simulator Device")
    end

    test "walk_oid handles empty subtrees gracefully", %{device_pid: device_pid} do
      # Test walking a non-existent subtree
      result = GenServer.call(device_pid, {:walk_oid, "1.3.6.1.2.1.99.99.99"})

      # Should return empty list, not crash
      assert {:ok, []} = result
    end

    test "walk_oid handles interface table OIDs", %{device_pid: device_pid} do
      # Test walking interface table - this might return empty but shouldn't crash
      result = GenServer.call(device_pid, {:walk_oid, "1.3.6.1.2.1.2.2.1"})

      # Should return a result without crashing
      assert {:ok, _oid_value_pairs} = result
    end

    test "walk_oid with different OID formats", %{device_pid: device_pid} do
      # Test with various OID string formats
      test_oids = [
        "1.3.6.1.2.1.1",
        "1.3.6.1.2.1.1.1",
        "1.3.6.1.2.1.1.1.0"
      ]

      for oid <- test_oids do
        result = GenServer.call(device_pid, {:walk_oid, oid})

        # Should always return {:ok, list} format, never crash
        assert {:ok, oid_value_pairs} = result
        assert is_list(oid_value_pairs)

        # All returned OIDs should be strings
        for {returned_oid, _type, _value} <- oid_value_pairs do
          assert is_binary(returned_oid)
        end
      end
    end

    test "walk_oid recursion limit prevents infinite loops", %{device_pid: device_pid} do
      # Walk a large subtree to test recursion limit
      result = GenServer.call(device_pid, {:walk_oid, "1.3.6.1.2.1"})

      assert {:ok, oid_value_pairs} = result
      assert is_list(oid_value_pairs)

      # Should not exceed reasonable limits (walk_oid_recursive has limit of 100)
      assert length(oid_value_pairs) <= 100
    end
  end

  describe "OID format consistency" do
    test "walk_oid always returns string OIDs", %{device_pid: device_pid} do
      result = GenServer.call(device_pid, {:walk_oid, "1.3.6.1.2.1.1"})

      assert {:ok, oid_value_pairs} = result

      # Every OID in the result should be a string, not a list
      for {oid, _type, _value} <- oid_value_pairs do
        assert is_binary(oid)
        refute is_list(oid), "OID should be string, not list: #{inspect(oid)}"

        # Should be a valid dotted decimal format
        assert Regex.match?(~r/^\d+(\.\d+)*$/, oid)
      end
    end

    test "walk_oid handles OID prefix checking correctly", %{device_pid: device_pid} do
      # Walk system group and verify all returned OIDs are within the subtree
      result = GenServer.call(device_pid, {:walk_oid, "1.3.6.1.2.1.1"})

      assert {:ok, oid_value_pairs} = result

      for {oid, _type, _value} <- oid_value_pairs do
        assert String.starts_with?(oid, "1.3.6.1.2.1.1"),
               "OID #{oid} should start with requested prefix"
      end
    end
  end

  describe "Error handling" do
    test "walk_oid handles device errors gracefully", %{device_pid: device_pid} do
      # Test with empty OID - this should handle gracefully
      result = GenServer.call(device_pid, {:walk_oid, ""})

      # Should handle gracefully, not crash
      assert match?({:ok, []}, result) or match?({:error, _}, result)
    end

    test "walk_oid timeout handling", %{device_pid: device_pid} do
      # Test that walk_oid completes within reasonable time
      start_time = System.monotonic_time(:millisecond)
      result = GenServer.call(device_pid, {:walk_oid, "1.3.6.1.2.1.1"}, 5000)
      end_time = System.monotonic_time(:millisecond)

      assert {:ok, _} = result
      assert end_time - start_time < 5000, "Walk should complete quickly"
    end
  end

  describe "Regression tests for the original bug" do
    test "walk_oid does not crash with CaseClauseError", %{device_pid: device_pid} do
      # This is the exact scenario that was failing before the fix
      # The error was: (CaseClauseError) no case clause matching: 
      # {[1, 3, 6, 1, 2, 1, 1, 1, 0], :octet_string, "Motorola SB6141 DOCSIS 3.0 Cable Modem"}

      # This should not crash the device process
      result = GenServer.call(device_pid, {:walk_oid, "1.3.6.1.2.1.1"})

      # Device should still be alive
      assert Process.alive?(device_pid)

      # Should return proper result
      assert {:ok, oid_value_pairs} = result
      assert is_list(oid_value_pairs)

      # Should contain the system description that was causing the crash
      system_desc =
        Enum.find(oid_value_pairs, fn {oid, _type, _value} ->
          oid == "1.3.6.1.2.1.1.1.0"
        end)

      assert system_desc != nil
    end

    test "get_next_oid_value returns consistent format", %{device_pid: device_pid} do
      # Test that the internal function returns the expected format
      # This tests the fix for inconsistent return formats

      # We can't call get_next_oid_value directly, but we can verify
      # that walk_oid works, which depends on get_next_oid_value
      result = GenServer.call(device_pid, {:walk_oid, "1.3.6.1.2.1.1.1"})

      assert {:ok, oid_value_pairs} = result

      # If get_next_oid_value was returning inconsistent formats,
      # this would fail with a pattern matching error
      for {oid, type, value} <- oid_value_pairs do
        assert is_binary(oid)
        assert is_atom(type)
        assert value != nil
      end
    end
  end
end
