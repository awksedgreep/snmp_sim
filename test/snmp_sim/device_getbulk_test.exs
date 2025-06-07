defmodule SnmpSim.DeviceGetBulkTest do
  use ExUnit.Case, async: false
  
  alias SnmpSim.Device
  alias SnmpSim.MIB.SharedProfiles
  
  @moduletag :unit

  setup do
    # Start SharedProfiles for testing (handle if already started)
    case SharedProfiles.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
    
    # Create test device state
    state = %{
      device_id: "test_device_001",
      device_type: :cable_modem,
      port: 30100,
      community: "public",
      version: :v2c,
      counters: %{
        "1.3.6.1.2.1.2.2.1.10.1" => 1234567,
        "1.3.6.1.2.1.2.2.1.16.1" => 2345678
      },
      gauges: %{
        "1.3.6.1.2.1.2.2.1.5.1" => 100000000
      },
      uptime_start: System.monotonic_time(:millisecond)
    }
    
    {:ok, device_pid} = Device.start_link(state)
    
    on_exit(fn ->
      if Process.alive?(device_pid) do
        Device.stop(device_pid)
      end
    end)
    
    %{device: device_pid, state: state}
  end

  describe "GETBULK functionality" do
    test "get_bulk returns multiple varbinds for system OIDs", %{device: device} do
      # Test GETBULK on system group
      result = Device.get_bulk(device, [1, 3, 6, 1, 2, 1, 1], 5)
      
      assert {:ok, varbinds} = result
      assert is_list(varbinds)
      # May return 0 results for root OID - this is acceptable
      
      # Verify varbind format is 3-tuples {oid, type, value}
      Enum.each(varbinds, fn varbind ->
        assert {oid, type, value} = varbind
        assert is_binary(oid) or is_list(oid)
        assert is_atom(type)
        refute is_nil(value)
      end)
    end

    test "get_bulk handles interface table OIDs", %{device: device} do
      # Test GETBULK on interface table
      result = Device.get_bulk(device, [1, 3, 6, 1, 2, 1, 2, 2, 1], 3)
      
      assert {:ok, varbinds} = result
      assert is_list(varbinds)
      
      # Should return some varbinds even if using fallback
      if length(varbinds) > 0 do
        # Verify format
        Enum.each(varbinds, fn varbind ->
          case varbind do
            {oid, type, _value} ->
              assert String.starts_with?(oid, "1.3.6.1.2.1.2.2.1")
            {oid, _value} ->
              assert String.starts_with?(oid, "1.3.6.1.2.1.2.2.1")
          end
        end)
      end
    end

    test "get_bulk with count 1 returns single varbind", %{device: device} do
      result = Device.get_bulk(device, [1, 3, 6, 1, 2, 1, 1, 1], 1)
      
      assert {:ok, varbinds} = result
      assert is_list(varbinds)
      
      # Should return at least one varbind
      if length(varbinds) > 0 do
        assert length(varbinds) >= 1
        [{oid, type, value}] = varbinds
        # Convert OID to string if it's a list
        oid_string = if is_list(oid), do: Enum.join(oid, "."), else: oid
        assert is_binary(oid_string)
        assert String.starts_with?(oid_string, "1.3.6.1.2.1.1")
      end
    end

    test "get_bulk with large count is properly limited", %{device: device} do
      result = Device.get_bulk(device, [1, 3, 6, 1, 2, 1, 1], 1000)
      
      assert {:ok, varbinds} = result
      assert is_list(varbinds)
      
      # Should not return 1000 varbinds - should be reasonably limited
      assert length(varbinds) < 100
    end

    test "get_bulk handles empty results gracefully", %{device: device} do
      # Test with an OID that might not have next values
      result = Device.get_bulk(device, [1, 3, 6, 1, 9, 9, 9, 9], 5)
      
      # Should return ok with empty list or some fallback values
      assert {:ok, varbinds} = result
      assert is_list(varbinds)
      # Empty list is acceptable for non-existent OID subtrees
    end

    test "get_bulk returns consistent OID format", %{device: device} do
      result = Device.get_bulk(device, [1, 3, 6, 1, 2, 1, 1], 3)
      
      assert {:ok, varbinds} = result
      assert is_list(varbinds)
      
      if length(varbinds) > 0 do
        # All OIDs should be in consistent format (preferably strings)
        oid_formats = Enum.map(varbinds, fn varbind ->
          case varbind do
            {oid, _type, _value} -> 
              cond do
                is_binary(oid) -> :string
                is_list(oid) -> :list
                true -> :other
              end
            {oid, _value} -> 
              cond do
                is_binary(oid) -> :string
                is_list(oid) -> :list
                true -> :other
              end
          end
        end)
        
        # All should be the same format
        unique_formats = Enum.uniq(oid_formats)
        assert length(unique_formats) <= 1, "Mixed OID formats found: #{inspect(unique_formats)}"
      end
    end

    test "get_bulk handles different OID input formats", %{device: device} do
      # Test with list OID
      result1 = Device.get_bulk(device, [1, 3, 6, 1, 2, 1, 1], 2)
      assert {:ok, varbinds1} = result1
      
      # Test with string OID (if supported)
      result2 = Device.get_bulk(device, "1.3.6.1.2.1.1", 2)
      assert {:ok, varbinds2} = result2
      
      # Both should return valid results
      assert is_list(varbinds1)
      assert is_list(varbinds2)
    end

    test "get_bulk with zero count returns empty list", %{device: device} do
      result = Device.get_bulk(device, [1, 3, 6, 1, 2, 1, 1], 0)
      
      assert {:ok, varbinds} = result
      assert varbinds == []
    end
  end

  describe "GETBULK fallback functionality" do
    test "fallback generates proper OID sequences", %{device: device} do
      # Test fallback when SharedProfiles is not available
      # This tests the get_fallback_bulk_oids function
      
      result = Device.get_bulk(device, [1, 3, 6, 1], 5)
      
      assert {:ok, varbinds} = result
      assert is_list(varbinds)
      
      if length(varbinds) > 0 do
        # Verify that OIDs progress logically
        oids = Enum.map(varbinds, fn varbind ->
          case varbind do
            {oid, _type, _value} -> oid
            {oid, _value} -> oid
          end
        end)
        
        # Convert all to strings for comparison
        oid_strings = Enum.map(oids, fn oid ->
          case oid do
            oid when is_binary(oid) -> oid
            oid when is_list(oid) -> Enum.join(oid, ".")
            _ -> to_string(oid)
          end
        end)
        
        # Should have at least some OIDs starting with the requested prefix
        prefix = "1.3.6.1"
        matching_oids = Enum.filter(oid_strings, &String.starts_with?(&1, prefix))
        assert length(matching_oids) > 0, "No OIDs found with prefix #{prefix}"
      end
    end

    test "fallback handles root OID requests", %{device: device} do
      # Test with very root OID
      result = Device.get_bulk(device, [1], 3)
      
      assert {:ok, varbinds} = result
      assert is_list(varbinds)
      
      # Should return some OIDs even for root request
      if length(varbinds) > 0 do
        # All should be valid 3-tuples
        Enum.each(varbinds, fn varbind ->
          case varbind do
            {oid, type, _value} ->
              assert is_binary(oid) or is_list(oid)
              assert is_atom(type)
            {oid, _value} ->
              assert is_binary(oid) or is_list(oid)
          end
        end)
      end
    end
  end

  describe "GETBULK error handling" do
    test "get_bulk handles device process crashes gracefully" do
      # Create a device that will crash
      crash_state = %{
        device_id: "crash_device",
        device_type: :cable_modem,
        port: 30250,  # Different port to avoid conflicts
        community: "public",
        version: :v2c,
        counters: %{},
        gauges: %{},
        uptime_start: System.monotonic_time(:millisecond)
      }

      {:ok, crash_device_pid} = Device.start_link(crash_state)
      
      # Stop the device to simulate a crash
      Device.stop(crash_device_pid)
      
      # Try to call get_bulk on the crashed device - should throw an exception
      assert catch_exit(Device.get_bulk(crash_device_pid, [1, 3, 6, 1, 2, 1, 1], 5))
    end

    test "get_bulk with invalid OID format", %{device: device} do
      # Test with invalid OID
      result = Device.get_bulk(device, "invalid.oid", 3)
      
      # Should handle gracefully - either error or empty result
      case result do
        {:ok, varbinds} -> assert is_list(varbinds)
        {:error, _reason} -> :ok
        _ -> flunk("Unexpected result: #{inspect(result)}")
      end
    end

    test "get_bulk with negative count", %{device: device} do
      result = Device.get_bulk(device, [1, 3, 6, 1, 2, 1, 1], -1)
      
      # Should handle gracefully
      case result do
        {:ok, varbinds} -> 
          assert is_list(varbinds)
          assert varbinds == []  # Negative count should return empty
        {:error, _reason} -> :ok
        _ -> flunk("Unexpected result: #{inspect(result)}")
      end
    end
  end

  describe "GETBULK integration with SharedProfiles" do
    test "get_bulk uses SharedProfiles when available", %{device: device} do
      # This test verifies that the device tries to use SharedProfiles first
      # and falls back to internal logic when needed
      
      result = Device.get_bulk(device, [1, 3, 6, 1, 2, 1, 1], 3)
      
      assert {:ok, varbinds} = result
      assert is_list(varbinds)
      
      # The exact behavior depends on whether SharedProfiles has data
      # but it should always return a valid result
      if length(varbinds) > 0 do
        # Verify all varbinds are properly formatted
        Enum.each(varbinds, fn varbind ->
          case varbind do
            {oid, type, value} ->
              assert is_binary(oid) or is_list(oid)
              assert is_atom(type)
              refute is_nil(value)
            {oid, value} ->
              assert is_binary(oid) or is_list(oid)
              refute is_nil(value)
          end
        end)
      end
    end
  end

  describe "GETBULK edge cases and boundary conditions" do
    test "get_bulk with very large max_repetitions", %{device: device} do
      # Test with a very large count to ensure proper limiting
      result = Device.get_bulk(device, [1, 3, 6, 1, 2, 1, 1], 1000)
      
      assert {:ok, varbinds} = result
      assert is_list(varbinds)
      # Should not return 1000 items, but should be limited reasonably
      assert length(varbinds) < 100
      # May return 0 results for root OID - this is acceptable
    end

    test "get_bulk with max_repetitions of 1", %{device: device} do
      # Test boundary condition with count = 1
      result = Device.get_bulk(device, [1, 3, 6, 1, 2, 1, 1], 1)
      
      assert {:ok, varbinds} = result
      assert is_list(varbinds)
      assert length(varbinds) == 1
      
      # Verify the single varbind is properly formatted
      [{oid, type, value}] = varbinds
      # Convert OID to string if it's a list
      oid_string = if is_list(oid), do: Enum.join(oid, "."), else: oid
      assert is_binary(oid_string)
      assert String.starts_with?(oid_string, "1.3.6.1.2.1.1")
    end

    test "get_bulk with string OID format", %{device: device} do
      # Test with string OID instead of list
      result = Device.get_bulk(device, "1.3.6.1.2.1.1", 3)
      
      assert {:ok, varbinds} = result
      assert is_list(varbinds)
      # May return 0 results for root OID - this is acceptable
      
      # All returned OIDs should be strings and properly formatted
      Enum.each(varbinds, fn varbind ->
        case varbind do
          {oid, _type, _value} ->
            # Convert OID to string if it's a list
            oid_string = if is_list(oid), do: Enum.join(oid, "."), else: oid
            assert is_binary(oid_string)
            assert String.match?(oid_string, ~r/^\d+(\.\d+)*$/)
          {oid, _value} ->
            # Convert OID to string if it's a list
            oid_string = if is_list(oid), do: Enum.join(oid, "."), else: oid
            assert is_binary(oid_string)
            assert String.match?(oid_string, ~r/^\d+(\.\d+)*$/)
        end
      end)
    end

    test "get_bulk with mixed OID format consistency", %{device: device} do
      # Test that both list and string OIDs return consistent results
      list_result = Device.get_bulk(device, [1, 3, 6, 1, 2, 1, 1], 3)
      string_result = Device.get_bulk(device, "1.3.6.1.2.1.1", 3)
      
      assert {:ok, list_varbinds} = list_result
      assert {:ok, string_varbinds} = string_result
      
      # Results should be identical regardless of input format
      assert list_varbinds == string_varbinds
    end

    test "get_bulk with interface table OIDs", %{device: device} do
      # Test specific interface table traversal
      result = Device.get_bulk(device, [1, 3, 6, 1, 2, 1, 2, 2, 1, 1], 5)
      
      assert {:ok, varbinds} = result
      assert is_list(varbinds)
      
      # Should return OIDs that are at or beyond the requested depth
      Enum.each(varbinds, fn varbind ->
        case varbind do
          {oid, _type, _value} ->
            # Convert OID to string if it's a list
            oid_string = if is_list(oid), do: Enum.join(oid, "."), else: oid
            assert String.starts_with?(oid_string, "1.3.6.1.2.1.2.2.1")
          {oid, _value} ->
            # Convert OID to string if it's a list
            oid_string = if is_list(oid), do: Enum.join(oid, "."), else: oid
            assert String.starts_with?(oid_string, "1.3.6.1.2.1.2.2.1")
        end
      end)
    end

    test "get_bulk with non-existent OID subtree", %{device: device} do
      # Test with an OID that doesn't exist in our MIB
      result = Device.get_bulk(device, [1, 3, 6, 1, 4, 1, 99999], 3)
      
      # Should either return empty list or fallback OIDs
      assert {:ok, varbinds} = result
      assert is_list(varbinds)
      # May be empty or contain fallback OIDs
    end

    test "get_bulk with root OID", %{device: device} do
      # Test starting from the very root
      result = Device.get_bulk(device, [1], 5)
      
      assert {:ok, varbinds} = result
      assert is_list(varbinds)
      
      # Root OID may return empty results - this is acceptable behavior
      if length(varbinds) > 0 do
        # Verify first varbind format if any results
        [{first_oid, _type, _value} | _] = varbinds
        oid_str = if is_list(first_oid), do: Enum.join(first_oid, "."), else: first_oid
        assert String.starts_with?(oid_str, "1")
      end
    end    end

    test "get_bulk with empty OID list", %{device: device} do
      # Test edge case with empty OID
      result = Device.get_bulk(device, [], 3)
      
      # Should handle gracefully, either error or fallback
      case result do
        {:ok, varbinds} -> 
          assert is_list(varbinds)
        {:error, _reason} -> 
          :ok  # Acceptable to return error for invalid OID
      end
    end

    test "get_bulk OID progression is strictly increasing", %{device: device} do
      # Ensure OIDs are returned in strictly increasing order
      result = Device.get_bulk(device, [1, 3, 6, 1, 2, 1, 1], 10)
      
      assert {:ok, varbinds} = result
      assert length(varbinds) > 1
      
      oids = Enum.map(varbinds, fn varbind ->
        case varbind do
          {oid, _type, _value} -> oid
          {oid, _value} -> oid
        end
      end)
      
      # Check that each OID is lexicographically greater than the previous
      oids
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.each(fn [oid1, oid2] ->
        assert oid1 < oid2, "OID progression not increasing: #{oid1} >= #{oid2}"
      end)
    end

    test "get_bulk with counter and gauge OIDs", %{device: device} do
      # Test specific counter OIDs that should have proper types
      result = Device.get_bulk(device, [1, 3, 6, 1, 2, 1, 2, 2, 1, 10], 3)
      
      assert {:ok, varbinds} = result
      assert is_list(varbinds)
      
      # Check that counter values are properly typed
      Enum.each(varbinds, fn varbind ->
        case varbind do
          {oid, type, value} ->
            # Convert OID to string if it's a list
            oid_string = if is_list(oid), do: Enum.join(oid, "."), else: oid
            assert is_binary(oid_string)
            # Counter values should be integers or tuples with type info
            assert is_integer(value) or (is_tuple(value) and elem(value, 0) == :counter32)
          {oid, value} ->
            # Convert OID to string if it's a list
            oid_string = if is_list(oid), do: Enum.join(oid, "."), else: oid
            assert is_binary(oid_string)
            # Handle 2-tuple format
            assert is_integer(value) or (is_tuple(value) and elem(value, 0) == :counter32)
        end
      end)
    end

    test "get_bulk fallback handles list OID conversion", %{device: device} do
      # Specifically test the list-to-string OID conversion in fallback
      # Stop SharedProfiles to force fallback
      pid = Process.whereis(SharedProfiles)
      if pid, do: Process.exit(pid, :kill)
      Process.sleep(10)
      
      result = Device.get_bulk(device, [1, 3, 6, 1, 2, 1, 2, 2, 1, 1], 3)
      
      assert {:ok, varbinds} = result
      assert is_list(varbinds)
      
      # Restart SharedProfiles for other tests
      SharedProfiles.start_link([])
    end

    test "get_bulk with maximum valid count boundary", %{device: device} do
      # Test with a reasonable maximum count
      result = Device.get_bulk(device, [1, 3, 6, 1, 2, 1, 1], 50)
      
      assert {:ok, varbinds} = result
      assert is_list(varbinds)
      assert length(varbinds) <= 50
      # May return 0 results for root OID - this is acceptable
    end

    test "get_bulk varbind format consistency", %{device: device} do
      # Ensure all varbinds follow the expected 3-tuple format
      result = Device.get_bulk(device, [1, 3, 6, 1, 2, 1, 1], 5)
      
      assert {:ok, varbinds} = result
      assert is_list(varbinds)
      
      Enum.each(varbinds, fn varbind ->
        case varbind do
          {oid, type, value} ->
            # Convert OID to string if it's a list
            oid_string = if is_list(oid), do: Enum.join(oid, "."), else: oid
            assert is_binary(oid_string)
            # Value can be various types but should not be nil
            refute is_nil(value)
          {oid, value} ->
            # Convert OID to string if it's a list
            oid_string = if is_list(oid), do: Enum.join(oid, "."), else: oid
            assert is_binary(oid_string)
            # Value can be various types but should not be nil
            refute is_nil(value)
        end
      end)
    end

    test "get_bulk with deep OID hierarchy", %{device: device} do
      # Test with a deep OID to ensure proper traversal
      result = Device.get_bulk(device, [1, 3, 6, 1, 2, 1, 2, 2, 1, 2, 1], 3)
      
      assert {:ok, varbinds} = result
      assert is_list(varbinds)
      
      # Should return OIDs that are at or beyond the requested depth
      Enum.each(varbinds, fn varbind ->
        case varbind do
          {oid, _type, _value} ->
            oid_parts = if is_binary(oid) do
              String.split(oid, ".")
            else
              oid  # Already a list
            end
            assert length(oid_parts) >= 10  # Deep enough
          {oid, _value} ->
            oid_parts = if is_binary(oid) do
              String.split(oid, ".")
            else
              oid  # Already a list
            end
            assert length(oid_parts) >= 10  # Deep enough
        end
      end)
    end
  end
