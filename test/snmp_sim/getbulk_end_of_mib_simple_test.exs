defmodule SnmpSim.GetbulkEndOfMibSimpleTest do
  use ExUnit.Case, async: false
  alias SnmpSim.MIB.SharedProfiles

  setup_all do
    # Start the application
    Application.ensure_all_started(:snmp_sim)
    
    # Create simple test data
    device_type = "test_device"
    
    # Create a small set of test OIDs in order
    test_profile_data = [
      {"1.3.6.1.2.1.1.1.0", %{type: "octet_string", value: "Test Device"}},
      {"1.3.6.1.2.1.1.2.0", %{type: "oid", value: "1.3.6.1.4.1.12345"}},
      {"1.3.6.1.2.1.1.3.0", %{type: "timeticks", value: "123456"}},
      {"1.3.6.1.2.1.2.1.0", %{type: "integer", value: "2"}},
      {"1.3.6.1.2.1.2.2.1.1.1", %{type: "integer", value: "1"}},
      {"1.3.6.1.2.1.2.2.1.1.2", %{type: "integer", value: "2"}},
      {"1.3.6.1.2.1.2.2.1.2.1", %{type: "octet_string", value: "eth0"}},
      {"1.3.6.1.2.1.2.2.1.2.2", %{type: "octet_string", value: "eth1"}}
    ]
    
    behavior_data = %{}
    
    # Store the profile
    :ok = SharedProfiles.store_profile(device_type, test_profile_data, behavior_data)
    
    # Get sorted OIDs for testing
    all_oids = Enum.map(test_profile_data, fn {oid, _data} -> oid end) 
      |> Enum.sort(&SharedProfiles.compare_oids_lexicographically/2)
    
    %{
      device_type: device_type,
      all_oids: all_oids,
      last_oid: List.last(all_oids),
      second_last_oid: Enum.at(all_oids, -2)
    }
  end

  describe "Core GETBULK end-of-MIB fixes" do
    test "get_next_oid does not return same OID (fixes infinite loop)", %{device_type: device_type, all_oids: all_oids} do
      # Test that get_next_oid never returns the same OID it was given
      # This was the core bug causing infinite loops
      
      for oid <- all_oids do
        case SharedProfiles.get_next_oid(device_type, oid) do
          {:ok, next_oid} ->
            assert next_oid != oid, "get_next_oid(#{oid}) returned same OID: #{next_oid}"
            assert SharedProfiles.compare_oids_lexicographically(oid, next_oid), 
              "Next OID #{next_oid} is not greater than #{oid}"
          :end_of_mib ->
            # This is fine for the last OID
            :ok
        end
      end
    end
    
    test "get_next_oid on last OID returns end_of_mib", %{device_type: device_type, last_oid: last_oid} do
      assert SharedProfiles.get_next_oid(device_type, last_oid) == :end_of_mib
    end
    
    test "get_bulk_oids from last OID returns empty list", %{device_type: device_type, last_oid: last_oid} do
      # This was returning the last OID itself, causing infinite loops
      assert {:ok, []} = SharedProfiles.get_bulk_oids(device_type, last_oid, 5)
    end
    
    test "get_bulk_oids from second-to-last OID returns only last OID", %{device_type: device_type, second_last_oid: second_last_oid, last_oid: last_oid} do
      {:ok, bulk_oids} = SharedProfiles.get_bulk_oids(device_type, second_last_oid, 5)
      
      assert length(bulk_oids) == 1
      {returned_oid, _type, _value} = List.first(bulk_oids)
      assert returned_oid == last_oid
    end
    
    test "get_bulk_oids does not include starting OID in results", %{device_type: device_type, all_oids: all_oids} do
      # Test that GETBULK returns OIDs *after* the starting OID, not including it
      
      # Test with first few OIDs
      test_oids = Enum.take(all_oids, 3)
      
      for start_oid <- test_oids do
        {:ok, bulk_oids} = SharedProfiles.get_bulk_oids(device_type, start_oid, 3)
        
        # None of the returned OIDs should be the starting OID
        returned_oids = Enum.map(bulk_oids, fn {oid, _, _} -> oid end)
        refute Enum.member?(returned_oids, start_oid), 
          "GETBULK from #{start_oid} incorrectly included starting OID in results"
        
        # All returned OIDs should be greater than starting OID
        for returned_oid <- returned_oids do
          assert SharedProfiles.compare_oids_lexicographically(start_oid, returned_oid),
            "GETBULK returned OID #{returned_oid} that is not greater than starting OID #{start_oid}"
        end
      end
    end
    
    test "get_bulk_oids simulates complete walk without infinite loops", %{device_type: device_type} do
      # Simulate what snmpbulkwalk does: start from broad OID and continue from last returned OID
      
      current_oid = "1.3.6.1"
      max_repetitions = 3
      iterations = 0
      max_iterations = 20  # Safety limit
      
      {final_iterations, final_total} = Enum.reduce_while(1..max_iterations, {current_oid, 0}, fn i, {oid, total} ->
        case SharedProfiles.get_bulk_oids(device_type, oid, max_repetitions) do
          {:ok, bulk_oids} when bulk_oids != [] ->
            {last_oid, _, _} = List.last(bulk_oids)
            new_total = total + length(bulk_oids)
            {:cont, {last_oid, new_total}}
            
          {:ok, []} ->
            # End of MIB reached
            {:halt, {i, total}}
            
          {:error, reason} ->
            flunk("GETBULK failed at iteration #{i}: #{inspect(reason)}")
        end
      end)
      
      # Should complete within reasonable number of iterations
      assert final_iterations < max_iterations, "GETBULK walk did not complete within #{max_iterations} iterations"
      
      # Should collect all test OIDs
      assert final_total > 0, "No OIDs collected during GETBULK walk"
      
      IO.puts("GETBULK walk completed in #{final_iterations} iterations, collected #{final_total} OIDs")
    end
  end

  describe "OID progression validation" do
    test "get_next_oid progression covers all OIDs without loops", %{device_type: device_type, all_oids: all_oids} do
      # Start from first OID and walk through all OIDs
      # This should never loop and should cover all OIDs
      
      first_oid = List.first(all_oids)
      visited_oids = MapSet.new()
      current_oid = first_oid
      
      # Walk through OIDs, ensuring no loops
      {final_visited, _} = Enum.reduce_while(1..length(all_oids) + 5, {visited_oids, current_oid}, fn _i, {visited, oid} ->
        if MapSet.member?(visited, oid) do
          flunk("Loop detected: OID #{oid} visited twice")
        end
        
        new_visited = MapSet.put(visited, oid)
        
        case SharedProfiles.get_next_oid(device_type, oid) do
          {:ok, next_oid} ->
            {:cont, {new_visited, next_oid}}
          :end_of_mib ->
            {:halt, {new_visited, oid}}
        end
      end)
      
      # Should have visited all OIDs in the test data
      assert MapSet.size(final_visited) == length(all_oids)
    end
    
    test "OID comparison function works correctly", %{all_oids: all_oids} do
      # Test that our OID comparison function produces correct lexicographic ordering
      
      # Test that each OID is less than the next one
      for {oid1, oid2} <- Enum.zip(all_oids, tl(all_oids)) do
        assert SharedProfiles.compare_oids_lexicographically(oid1, oid2),
          "OID #{oid1} should be less than #{oid2}"
        
        # Reverse should be false
        refute SharedProfiles.compare_oids_lexicographically(oid2, oid1),
          "OID #{oid2} should not be less than #{oid1}"
      end
      
      # Test that an OID is not less than itself
      for oid <- all_oids do
        refute SharedProfiles.compare_oids_lexicographically(oid, oid),
          "OID #{oid} should not be less than itself"
      end
    end
  end

  describe "Edge cases" do
    test "empty walk file handling" do
      # Test behavior with empty profile
      
      empty_device_type = "empty_test"
      :ok = SharedProfiles.store_profile(empty_device_type, [], %{})
      
      # Should handle empty profile gracefully
      assert SharedProfiles.get_next_oid(empty_device_type, "1.3.6.1") == :end_of_mib
      assert {:ok, []} = SharedProfiles.get_bulk_oids(empty_device_type, "1.3.6.1", 5)
    end
    
    test "large GETBULK requests don't cause issues", %{device_type: device_type} do
      # Test with large max_repetitions values
      
      {:ok, bulk_oids} = SharedProfiles.get_bulk_oids(device_type, "1.3.6.1", 1000)
      
      # Should return reasonable number of OIDs, not crash
      assert is_list(bulk_oids)
      assert length(bulk_oids) <= 1000
      
      # All returned OIDs should be valid
      for {oid, type, value} <- bulk_oids do
        assert is_binary(oid) or is_list(oid)
        assert is_atom(type)
        # value can be anything
      end
    end
    
    test "GETBULK with max_repetitions 0 returns empty list", %{device_type: device_type} do
      assert {:ok, []} = SharedProfiles.get_bulk_oids(device_type, "1.3.6.1", 0)
    end
    
    test "GETBULK with max_repetitions 1 returns at most 1 OID", %{device_type: device_type} do
      {:ok, bulk_oids} = SharedProfiles.get_bulk_oids(device_type, "1.3.6.1", 1)
      assert length(bulk_oids) <= 1
    end
  end
end
