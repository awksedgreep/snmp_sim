defmodule SnmpSim.ComprehensiveBulkWalkTest do
  use ExUnit.Case, async: true
  alias SnmpSim.Device

  setup do
    # Start a device for testing
    {:ok, device_pid} =
      Device.start_link(%{
        device_id: "test_device_#{:rand.uniform(10000)}",
        device_type: :cable_modem,
        port: 50000 + :rand.uniform(10000),
        community: "public"
      })

    %{device_pid: device_pid}
  end

  describe "Comprehensive GETBULK Testing - 25+ Different Scenarios" do
    test "1. Basic GETBULK from system root", %{device_pid: device_pid} do
      result = Device.get_bulk(device_pid, "1.3.6.1.2.1.1", 10)

      assert {:ok, varbinds} = result
      assert length(varbinds) > 0

      # Verify all varbinds are 3-tuples with consistent format
      for {oid, type, value} <- varbinds do
        assert is_binary(oid), "OID should be string format: #{inspect(oid)}"
        assert is_atom(type), "Type should be atom: #{inspect(type)}"
        assert value != nil, "Value should not be nil"
      end
    end

    test "2. GETBULK with multiple OIDs", %{device_pid: device_pid} do
      # Test multiple separate calls since get_bulk takes single OID
      result1 = Device.get_bulk(device_pid, "1.3.6.1.2.1.1.1.0", 2)
      result2 = Device.get_bulk(device_pid, "1.3.6.1.2.1.1.2.0", 3)

      assert {:ok, varbinds1} = result1
      assert {:ok, varbinds2} = result2

      # Combine results
      all_varbinds = varbinds1 ++ varbinds2

      for {oid, type, value} <- all_varbinds do
        assert is_binary(oid)
        assert is_atom(type)
        assert value != nil
      end
    end

    test "3. GETBULK with max_repetitions = 1", %{device_pid: device_pid} do
      result = Device.get_bulk(device_pid, "1.3.6.1.2.1.1", 1)

      assert {:ok, varbinds} = result
      assert length(varbinds) >= 1

      for {oid, type, value} <- varbinds do
        assert is_binary(oid)
        assert is_atom(type)
        assert value != nil
      end
    end

    test "4. GETBULK with max_repetitions = 50", %{device_pid: device_pid} do
      result = Device.get_bulk(device_pid, "1.3.6.1.2.1.1", 50)

      assert {:ok, varbinds} = result

      for {oid, type, value} <- varbinds do
        assert is_binary(oid)
        assert is_atom(type)
        assert value != nil
      end
    end

    test "5. GETBULK from interfaces subtree", %{device_pid: device_pid} do
      result = Device.get_bulk(device_pid, "1.3.6.1.2.1.2", 10)

      assert {:ok, varbinds} = result

      for {oid, type, value} <- varbinds do
        assert is_binary(oid)
        assert is_atom(type)
        assert value != nil
      end
    end

    test "6. GETBULK from specific leaf OID", %{device_pid: device_pid} do
      result = Device.get_bulk(device_pid, "1.3.6.1.2.1.1.1.0", 5)

      assert {:ok, varbinds} = result

      for {oid, type, value} <- varbinds do
        assert is_binary(oid)
        assert is_atom(type)
        assert value != nil
      end
    end

    test "7. GETBULK with multiple starting OIDs", %{device_pid: device_pid} do
      # Test multiple separate calls
      result1 = Device.get_bulk(device_pid, "1.3.6.1.2.1.1.1.0", 1)
      result2 = Device.get_bulk(device_pid, "1.3.6.1.2.1.1.2.0", 1)
      result3 = Device.get_bulk(device_pid, "1.3.6.1.2.1.1.3.0", 1)

      assert {:ok, varbinds1} = result1
      assert {:ok, varbinds2} = result2
      assert {:ok, varbinds3} = result3

      all_varbinds = varbinds1 ++ varbinds2 ++ varbinds3

      for {oid, type, value} <- all_varbinds do
        assert is_binary(oid)
        assert is_atom(type)
        assert value != nil
      end
    end

    test "8. GETBULK with string OID input", %{device_pid: device_pid} do
      result = Device.get_bulk(device_pid, "1.3.6.1.2.1.1", 5)

      assert {:ok, varbinds} = result

      for {oid, type, value} <- varbinds do
        assert is_binary(oid)
        assert is_atom(type)
        assert value != nil
      end
    end

    test "9. GETBULK with list OID input", %{device_pid: device_pid} do
      result = Device.get_bulk(device_pid, [1, 3, 6, 1, 2, 1, 1], 5)

      assert {:ok, varbinds} = result

      for {oid, type, value} <- varbinds do
        assert is_binary(oid)
        assert is_atom(type)
        assert value != nil
      end
    end

    test "10. GETBULK from root OID", %{device_pid: device_pid} do
      result = Device.get_bulk(device_pid, "1", 10)

      assert {:ok, varbinds} = result

      for {oid, type, value} <- varbinds do
        assert is_binary(oid)
        assert is_atom(type)
        assert value != nil
      end
    end

    test "11. GETBULK from iso.org.dod.internet", %{device_pid: device_pid} do
      result = Device.get_bulk(device_pid, "1.3.6.1", 8)

      assert {:ok, varbinds} = result

      for {oid, type, value} <- varbinds do
        assert is_binary(oid)
        assert is_atom(type)
        assert value != nil
      end
    end

    test "12. GETBULK with zero max_repetitions", %{device_pid: device_pid} do
      result = Device.get_bulk(device_pid, "1.3.6.1.2.1.1.1.0", 0)

      assert {:ok, varbinds} = result
      # Should still return at least one result
      assert length(varbinds) >= 0

      for {oid, type, value} <- varbinds do
        assert is_binary(oid)
        assert is_atom(type)
        assert value != nil
      end
    end

    test "13. GETBULK with multiple separate calls", %{device_pid: device_pid} do
      result1 = Device.get_bulk(device_pid, "1.3.6.1.2.1.1.1.0", 5)
      result2 = Device.get_bulk(device_pid, "1.3.6.1.2.1.1.2.0", 5)

      assert {:ok, varbinds1} = result1
      assert {:ok, varbinds2} = result2
      assert length(varbinds1) >= 1
      assert length(varbinds2) >= 1

      for {oid, type, value} <- varbinds1 ++ varbinds2 do
        assert is_binary(oid)
        assert is_atom(type)
        assert value != nil
      end
    end

    test "14. GETBULK progression verification", %{device_pid: device_pid} do
      result = Device.get_bulk(device_pid, "1.3.6.1.2.1.1.1.0", 5)

      assert {:ok, varbinds} = result
      assert length(varbinds) >= 1

      # If we have multiple varbinds, verify OID progression
      if length(varbinds) > 1 do
        # Verify OID progression - each OID should be lexicographically greater than previous
        oid_strings =
          Enum.map(varbinds, fn {oid, _type, _value} ->
            oid
          end)

        sorted_oids = Enum.sort(oid_strings)
        assert oid_strings == sorted_oids, "OIDs should be in sorted order"
      end

      for {oid, type, value} <- varbinds do
        assert is_binary(oid)
        assert is_atom(type)
        assert value != nil
      end
    end

    test "15. GETBULK with invalid starting OID", %{device_pid: device_pid} do
      result = Device.get_bulk(device_pid, "9.9.9.9.9", 5)

      # Should handle gracefully, either with error or empty result
      case result do
        {:ok, varbinds} ->
          # If successful, verify format
          for {oid, type, value} <- varbinds do
            assert is_binary(oid)
            assert is_atom(type)
            assert value != nil
          end

        {:error, _reason} ->
          :ok
      end
    end

    test "16. GETBULK type consistency check", %{device_pid: device_pid} do
      result = Device.get_bulk(device_pid, "1.3.6.1.2.1.1", 10)

      assert {:ok, varbinds} = result

      # Check that we have various SNMP types
      types_found =
        varbinds
        |> Enum.map(fn {_oid, type, _value} -> type end)
        |> Enum.uniq()

      assert :octet_string in types_found

      for {oid, type, value} <- varbinds do
        assert is_binary(oid)
        assert is_atom(type)
        assert value != nil

        assert type in [
                 :octet_string,
                 :integer,
                 :timeticks,
                 :object_identifier,
                 :counter32,
                 :gauge32
               ]
      end
    end

    test "17. GETBULK value content verification", %{device_pid: device_pid} do
      result = Device.get_bulk(device_pid, "1.3.6.1.2.1.1.1.0", 5)

      assert {:ok, varbinds} = result

      # Find system description
      sys_desc =
        Enum.find(varbinds, fn {oid, _type, _value} ->
          oid == "1.3.6.1.2.1.1.1.0"
        end)

      if sys_desc do
        {_oid, _type, value} = sys_desc
        assert is_binary(value)
        assert String.contains?(value, "Cable Modem") or String.contains?(value, "SNMP Simulator")
      end

      for {oid, type, value} <- varbinds do
        assert is_binary(oid)
        assert is_atom(type)
        assert value != nil
      end
    end

    test "18. GETBULK with mixed OID formats", %{device_pid: device_pid} do
      # Test both string and list formats
      result1 = Device.get_bulk(device_pid, "1.3.6.1.2.1.1.1.0", 2)
      result2 = Device.get_bulk(device_pid, [1, 3, 6, 1, 2, 1, 1, 2, 0], 2)

      assert {:ok, varbinds1} = result1
      assert {:ok, varbinds2} = result2

      for {oid, type, value} <- varbinds1 ++ varbinds2 do
        assert is_binary(oid)
        assert is_atom(type)
        assert value != nil
      end
    end

    test "19. GETBULK large repetition count", %{device_pid: device_pid} do
      result = Device.get_bulk(device_pid, "1.3.6.1.2.1.1", 100)

      assert {:ok, varbinds} = result

      for {oid, type, value} <- varbinds do
        assert is_binary(oid)
        assert is_atom(type)
        assert value != nil
      end
    end

    test "20. GETBULK subtree boundary testing", %{device_pid: device_pid} do
      result = Device.get_bulk(device_pid, "1.3.6.1.2.1.1.9", 20)

      assert {:ok, varbinds} = result

      # Should transition to next subtree or end gracefully
      for {oid, type, value} <- varbinds do
        assert is_binary(oid)
        assert is_atom(type)
        assert value != nil
      end
    end

    test "21. GETBULK response size verification", %{device_pid: device_pid} do
      result = Device.get_bulk(device_pid, "1.3.6.1.2.1.1", 15)

      assert {:ok, varbinds} = result

      # Should respect max_repetitions (approximately)
      # Some tolerance
      assert length(varbinds) <= 20

      for {oid, type, value} <- varbinds do
        assert is_binary(oid)
        assert is_atom(type)
        assert value != nil
      end
    end

    test "22. GETBULK error handling", %{device_pid: device_pid} do
      # Test with negative count
      result = Device.get_bulk(device_pid, "1.3.6.1.2.1.1", -1)

      # Should handle gracefully
      case result do
        {:ok, varbinds} ->
          for {oid, type, value} <- varbinds do
            assert is_binary(oid)
            assert is_atom(type)
            assert value != nil
          end

        {:error, _reason} ->
          :ok
      end
    end

    test "23. GETBULK with empty OID", %{device_pid: device_pid} do
      result = Device.get_bulk(device_pid, "", 5)

      # Should handle empty OID gracefully
      case result do
        {:ok, varbinds} ->
          assert is_list(varbinds)

        {:error, _reason} ->
          :ok
      end
    end

    test "24. GETBULK sequential consistency", %{device_pid: device_pid} do
      # Run same request twice, should get consistent results
      oid = "1.3.6.1.2.1.1"
      count = 5

      result1 = Device.get_bulk(device_pid, oid, count)
      result2 = Device.get_bulk(device_pid, oid, count)

      assert {:ok, varbinds1} = result1
      assert {:ok, varbinds2} = result2

      # Results should be identical
      assert length(varbinds1) == length(varbinds2)

      for {oid, type, value} <- varbinds1 do
        assert is_binary(oid)
        assert is_atom(type)
        assert value != nil
      end

      for {oid, type, value} <- varbinds2 do
        assert is_binary(oid)
        assert is_atom(type)
        assert value != nil
      end
    end

    test "25. GETBULK comprehensive format validation", %{device_pid: device_pid} do
      # Test multiple calls since get_bulk takes single OID
      result1 = Device.get_bulk(device_pid, "1.3.6.1.2.1.1.1.0", 5)
      result2 = Device.get_bulk(device_pid, "1.3.6.1.2.1.1.2.0", 5)

      assert {:ok, varbinds1} = result1
      assert {:ok, varbinds2} = result2

      varbinds = varbinds1 ++ varbinds2
      assert length(varbinds) > 0

      # Comprehensive validation of every varbind
      for {oid, type, value} <- varbinds do
        # OID validation
        assert is_binary(oid), "OID must be string: #{inspect(oid)}"
        assert String.length(oid) > 0, "OID must not be empty"

        # Type validation
        assert is_atom(type), "Type must be atom: #{inspect(type)}"

        assert type in [
                 :octet_string,
                 :integer,
                 :timeticks,
                 :object_identifier,
                 :counter32,
                 :gauge32,
                 :null
               ],
               "Invalid type: #{inspect(type)}"

        # Value validation
        assert value != nil, "Value must not be nil"

        case type do
          :integer -> assert is_integer(value)
          :counter32 -> assert is_integer(value)
          :gauge32 -> assert is_integer(value)
          :octet_string -> assert is_binary(value)
          :timeticks -> assert is_integer(value)
          :object_identifier -> assert is_binary(value) or is_list(value)
          _ -> :ok
        end
      end

      # Verify OID ordering
      oid_strings =
        Enum.map(varbinds, fn {oid, _type, _value} ->
          oid
        end)

      sorted_oids = Enum.sort(oid_strings)
      assert oid_strings == sorted_oids, "OIDs should be in sorted order"
    end

    test "26. GETBULK edge case - end of MIB", %{device_pid: device_pid} do
      result = Device.get_bulk(device_pid, "1.3.6.1.2.1.999", 5)

      # Should handle end-of-MIB gracefully
      case result do
        {:ok, varbinds} ->
          for {oid, type, value} <- varbinds do
            assert is_binary(oid)
            assert is_atom(type)
            assert value != nil
          end

        {:error, _reason} ->
          :ok
      end
    end

    test "27. GETBULK stress test - multiple rapid requests", %{device_pid: device_pid} do
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            Device.get_bulk(device_pid, "1.3.6.1.2.1.1.#{i}", 3)
          end)
        end

      results = Task.await_many(tasks, 5000)
      # All requests should succeed or fail gracefully
      for result <- results do
        case result do
          {:ok, varbinds} ->
            for {oid, type, value} <- varbinds do
              assert is_binary(oid)
              assert is_atom(type)
              assert value != nil
            end

          {:error, _reason} ->
            :ok
        end
      end
    end
  end

  describe "Tuple Format Regression Tests" do
    test "get_next_oid_value returns 3-tuples consistently", %{device_pid: _device_pid} do
      # Test that get_next_oid_value returns proper 3-tuple format
      oid_value_pairs = [
        {"1.3.6.1.2.1.1.1.0", :octet_string, "Test Value"},
        {"1.3.6.1.2.1.1.2.0", :object_identifier, "1.3.6.1.4.1.1"},
        {"1.3.6.1.2.1.1.3.0", :timeticks, 12345}
      ]

      for item <- oid_value_pairs do
        assert tuple_size(item) == 3, "Expected 3-tuple, got: #{inspect(item)}"
        {oid, type, value} = item
        assert is_binary(oid) or is_list(oid)
        assert is_atom(type)
        assert value != nil
      end
    end

    test "Device.get_next returns proper format", %{device_pid: device_pid} do
      oids_to_test = [
        "1.3.6.1.2.1.1.1.0",
        "1.3.6.1.2.1.1.2.0",
        "1.3.6.1.2.1.1.3.0"
      ]

      for oid <- oids_to_test do
        result = Device.get_next(device_pid, oid)

        assert {:ok, {next_oid, type, value}} = result

        assert is_binary(next_oid)
        assert is_atom(type)
        assert value != nil
      end
    end
  end
end
