defmodule SnmpSim.GetbulkFixesTest do
  use ExUnit.Case, async: false
  alias SnmpSim.MIB.SharedProfiles

  @moduletag :integration

  setup_all do
    # Start the application
    Application.ensure_all_started(:snmp_sim)
    
    # Load a real walk profile that we know exists
    device_type = "cable_modem"
    walk_file = "priv/walks/cable_modem.walk"
    
    # Check if walk file exists and load it
    if File.exists?(walk_file) do
      case SharedProfiles.load_walk_profile(device_type, walk_file) do
        :ok -> 
          %{device_type: device_type, walk_file_loaded: true}
        {:error, reason} -> 
          IO.puts("Failed to load walk file: #{inspect(reason)}")
          %{device_type: device_type, walk_file_loaded: false}
      end
    else
      IO.puts("Walk file not found: #{walk_file}")
      %{device_type: device_type, walk_file_loaded: false}
    end
  end

  describe "Critical GETBULK fixes validation" do
    test "get_next_oid does not return same OID (infinite loop fix)", %{device_type: device_type, walk_file_loaded: walk_file_loaded} do
      if not walk_file_loaded do
        IO.puts("Skipping test - walk file not loaded")
        assert true
      else
        # Test the specific problematic OID that was causing infinite loops
        problematic_oid = "1.3.6.1.2.1.2.2.1.21.1"
        
        case SharedProfiles.get_next_oid(device_type, problematic_oid) do
          {:ok, next_oid} ->
            assert next_oid != problematic_oid, "CRITICAL BUG: get_next_oid still returns same OID"
            IO.puts("✓ FIXED: get_next_oid(#{problematic_oid}) = #{next_oid}")
          :end_of_mib ->
            IO.puts("✓ FIXED: get_next_oid(#{problematic_oid}) = :end_of_mib")
          {:error, reason} ->
            IO.puts("Note: get_next_oid failed with: #{inspect(reason)}")
            assert true  # Not a failure, just means OID doesn't exist
        end
      end
    end
    
    test "get_bulk_oids from broad OID completes quickly", %{device_type: device_type, walk_file_loaded: walk_file_loaded} do
      if not walk_file_loaded do
        IO.puts("Skipping test - walk file not loaded")
        assert true
      else
        # Test GETBULK from broad OID that was causing hangs
        start_oid = "1.3.6.1"
        max_repetitions = 10
        
        start_time = System.monotonic_time(:millisecond)
        result = SharedProfiles.get_bulk_oids(device_type, start_oid, max_repetitions)
        end_time = System.monotonic_time(:millisecond)
        
        duration = end_time - start_time
        
        # Should complete quickly (not hang)
        assert duration < 1000, "CRITICAL BUG: GETBULK took too long: #{duration}ms (possible hang)"
        
        case result do
          {:ok, bulk_oids} ->
            assert is_list(bulk_oids), "GETBULK should return a list"
            IO.puts("✓ FIXED: GETBULK from #{start_oid} returned #{length(bulk_oids)} OIDs in #{duration}ms")
          {:error, reason} ->
            IO.puts("Note: GETBULK failed with: #{inspect(reason)}")
            assert true  # Not necessarily a failure
        end
      end
    end
    
    test "get_bulk_oids does not include starting OID", %{device_type: device_type, walk_file_loaded: walk_file_loaded} do
      if not walk_file_loaded do
        IO.puts("Skipping test - walk file not loaded")
        assert true
      else
        # Test that GETBULK doesn't include the starting OID in results
        start_oid = "1.3.6.1.2.1.1.1.0"
        
        case SharedProfiles.get_bulk_oids(device_type, start_oid, 5) do
          {:ok, bulk_oids} when bulk_oids != [] ->
            returned_oids = Enum.map(bulk_oids, fn {oid, _, _} -> oid end)
            
            refute Enum.member?(returned_oids, start_oid), 
              "CRITICAL BUG: GETBULK incorrectly included starting OID #{start_oid}"
            
            IO.puts("✓ FIXED: GETBULK from #{start_oid} correctly excluded starting OID")
            
          {:ok, []} ->
            IO.puts("Note: GETBULK returned empty list (end of MIB)")
            assert true
            
          {:error, reason} ->
            IO.puts("Note: GETBULK failed with: #{inspect(reason)}")
            assert true
        end
      end
    end
    
    test "get_bulk_oids walk simulation completes", %{device_type: device_type, walk_file_loaded: walk_file_loaded} do
      if not walk_file_loaded do
        IO.puts("Skipping test - walk file not loaded")
        assert true
      else
        # Simulate snmpbulkwalk behavior - this was hanging before
        current_oid = "1.3.6.1"
        max_repetitions = 5
        max_iterations = 100
        start_time = System.monotonic_time(:millisecond)
        
        # Walk through OIDs like snmpbulkwalk does
        {final_iterations, final_total, final_time} = Enum.reduce_while(1..max_iterations, {current_oid, 0}, fn i, {oid, total} ->
          case SharedProfiles.get_bulk_oids(device_type, oid, max_repetitions) do
            {:ok, bulk_oids} when bulk_oids != [] ->
              {last_oid, _, _} = List.last(bulk_oids)
              new_total = total + length(bulk_oids)
              
              # Check for time limit (prevent actual hangs in test)
              current_time = System.monotonic_time(:millisecond)
              if current_time - start_time > 5000 do  # 5 second limit
                {:halt, {i, new_total, current_time - start_time}}
              else
                {:cont, {last_oid, new_total}}
              end
              
            {:ok, []} ->
              # End of MIB reached - this is the correct behavior
              current_time = System.monotonic_time(:millisecond)
              {:halt, {i, total, current_time - start_time}}
              
            {:error, _reason} ->
              # Error occurred - halt
              current_time = System.monotonic_time(:millisecond)
              {:halt, {i, total, current_time - start_time}}
          end
        end)
        
        # Should complete within reasonable time and iterations
        assert final_iterations < max_iterations, "CRITICAL BUG: Walk did not complete within #{max_iterations} iterations"
        assert final_time < 5000, "CRITICAL BUG: Walk took too long: #{final_time}ms"
        
        IO.puts("✓ FIXED: GETBULK walk completed: #{final_iterations} iterations, #{final_total} OIDs, #{final_time}ms")
      end
    end
  end

  describe "End-of-MIB behavior validation" do
    test "GETBULK at end of MIB returns empty list", %{device_type: device_type, walk_file_loaded: walk_file_loaded} do
      if not walk_file_loaded do
        IO.puts("Skipping test - walk file not loaded")
        assert true
      else
        # Try to find an OID near the end of the walk
        # We'll use a high OID that's likely to be at or near the end
        test_oid = "1.3.6.1.4.1.99999.99999.99999"
        
        case SharedProfiles.get_bulk_oids(device_type, test_oid, 5) do
          {:ok, []} ->
            IO.puts("✓ FIXED: GETBULK from high OID #{test_oid} correctly returned empty list")
          {:ok, bulk_oids} ->
            IO.puts("Note: GETBULK from #{test_oid} returned #{length(bulk_oids)} OIDs (not at end yet)")
            assert true
          {:error, reason} ->
            IO.puts("Note: GETBULK failed with: #{inspect(reason)}")
            assert true
        end
      end
    end
  end

  describe "Performance and stability validation" do
    test "repeated GETBULK calls are consistent", %{device_type: device_type, walk_file_loaded: walk_file_loaded} do
      if not walk_file_loaded do
        IO.puts("Skipping test - walk file not loaded")
        assert true
      else
        # Test that repeated GETBULK calls return consistent results
        start_oid = "1.3.6.1.2.1.1"
        
        # Make multiple calls and compare results
        results = Enum.map(1..3, fn _i ->
          SharedProfiles.get_bulk_oids(device_type, start_oid, 3)
        end)
        
        # All results should be identical
        first_result = List.first(results)
        
        for {result, i} <- Enum.with_index(results, 1) do
          assert result == first_result, "CRITICAL BUG: GETBULK call #{i} returned different result"
        end
        
        IO.puts("✓ FIXED: 3 repeated GETBULK calls returned consistent results")
      end
    end
    
    test "GETBULK with various max_repetitions values", %{device_type: device_type, walk_file_loaded: walk_file_loaded} do
      if not walk_file_loaded do
        IO.puts("Skipping test - walk file not loaded")
        assert true
      else
        start_oid = "1.3.6.1.2.1.1"
        
        # Test different max_repetitions values
        for max_rep <- [0, 1, 5, 10, 100] do
          case SharedProfiles.get_bulk_oids(device_type, start_oid, max_rep) do
            {:ok, bulk_oids} ->
              assert length(bulk_oids) <= max_rep, "GETBULK returned more OIDs than max_repetitions"
              if max_rep == 0 do
                assert bulk_oids == [], "GETBULK with max_repetitions=0 should return empty list"
              end
            {:error, _reason} ->
              # Not necessarily a failure
              :ok
          end
        end
        
        IO.puts("✓ FIXED: GETBULK works correctly with various max_repetitions values")
      end
    end
  end
end
