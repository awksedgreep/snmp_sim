defmodule SnmpSim.GetbulkRegressionTest do
  use ExUnit.Case, async: false
  alias SnmpSim.MIB.SharedProfiles

  @moduletag :integration

  setup_all do
    # Start the application
    Application.ensure_all_started(:snmp_sim)
    
    # Load a real walk profile that we know exists
    device_type = "cable_modem"
    walk_file = "priv/walks/cable_modem.walk"
    
    # Check if walk file exists
    if File.exists?(walk_file) do
      {:ok, _} = SharedProfiles.load_walk_profile(device_type, walk_file)
      %{device_type: device_type, walk_file_exists: true}
    else
      %{device_type: device_type, walk_file_exists: false}
    end
  end

  describe "GETBULK end-of-MIB regression tests" do
    test "get_next_oid does not return same OID (infinite loop fix)", %{device_type: device_type, walk_file_exists: walk_file_exists} do
      if not walk_file_exists do
        IO.puts("Skipping test - walk file not found")
        assert true
      else
        # Test the specific problematic OID that was causing infinite loops
        problematic_oid = "1.3.6.1.2.1.2.2.1.21.1"
        
        case SharedProfiles.get_next_oid(device_type, problematic_oid) do
          {:ok, next_oid} ->
            assert next_oid != problematic_oid, "get_next_oid still returns same OID: #{next_oid}"
            IO.puts("✓ get_next_oid(#{problematic_oid}) = #{next_oid} (different OID)")
          :end_of_mib ->
            IO.puts("✓ get_next_oid(#{problematic_oid}) = :end_of_mib (reached end)")
        end
      end
    end
    
    test "get_bulk_oids from broad OID does not hang", %{device_type: device_type, walk_file_exists: walk_file_exists} do
      if not walk_file_exists do
        IO.puts("Skipping test - walk file not found")
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
        assert duration < 5000, "GETBULK took too long: #{duration}ms (possible hang)"
        
        case result do
          {:ok, bulk_oids} ->
            assert is_list(bulk_oids), "GETBULK should return a list"
            IO.puts("✓ GETBULK from #{start_oid} returned #{length(bulk_oids)} OIDs in #{duration}ms")
          {:error, reason} ->
            flunk("GETBULK failed: #{inspect(reason)}")
        end
      end
    end
    
    test "get_bulk_oids simulates walk without infinite loops", %{device_type: device_type, walk_file_exists: walk_file_exists} do
      if not walk_file_exists do
        IO.puts("Skipping test - walk file not found")
        assert true
      else
        # Simulate snmpbulkwalk behavior
        current_oid = "1.3.6.1"
        max_repetitions = 5
        total_oids = 0
        iterations = 0
        max_iterations = 50
        start_time = System.monotonic_time(:millisecond)
        
        # Walk through OIDs like snmpbulkwalk does
        {final_iterations, final_total, final_time} = Enum.reduce_while(1..max_iterations, {current_oid, 0}, fn i, {oid, total} ->
          case SharedProfiles.get_bulk_oids(device_type, oid, max_repetitions) do
            {:ok, bulk_oids} when bulk_oids != [] ->
              {last_oid, _, _} = List.last(bulk_oids)
              new_total = total + length(bulk_oids)
              
              # Check for time limit (prevent actual hangs in test)
              current_time = System.monotonic_time(:millisecond)
              if current_time - start_time > 10000 do  # 10 second limit
                {:halt, {i, new_total, current_time - start_time}}
              else
                {:cont, {last_oid, new_total}}
              end
              
            {:ok, []} ->
              # End of MIB reached - this is the correct behavior
              current_time = System.monotonic_time(:millisecond)
              {:halt, {i, total, current_time - start_time}}
              
            {:error, reason} ->
              flunk("GETBULK failed at iteration #{i}: #{inspect(reason)}")
          end
        end)
        
        # Should complete within reasonable time and iterations
        assert final_iterations < max_iterations, "Walk did not complete within #{max_iterations} iterations"
        assert final_time < 10000, "Walk took too long: #{final_time}ms"
        assert final_total > 0, "No OIDs collected during walk"
        
        IO.puts("✓ GETBULK walk completed: #{final_iterations} iterations, #{final_total} OIDs, #{final_time}ms")
      end
    end
    
    test "get_bulk_oids does not include starting OID", %{device_type: device_type, walk_file_exists: walk_file_exists} do
      if not walk_file_exists do
        IO.puts("Skipping test - walk file not found")
        assert true
      else
        # Test that GETBULK doesn't include the starting OID in results
        start_oid = "1.3.6.1.2.1.1.1.0"
        
        case SharedProfiles.get_bulk_oids(device_type, start_oid, 5) do
          {:ok, bulk_oids} ->
            returned_oids = Enum.map(bulk_oids, fn {oid, _, _} -> oid end)
            
            refute Enum.member?(returned_oids, start_oid), 
              "GETBULK incorrectly included starting OID #{start_oid} in results"
            
            IO.puts("✓ GETBULK from #{start_oid} correctly excluded starting OID")
            
          {:error, reason} ->
            flunk("GETBULK failed: #{inspect(reason)}")
        end
      end
    end
  end

  describe "End-of-MIB handling" do
    test "GETBULK at end of MIB returns empty list", %{device_type: device_type, walk_file_exists: walk_file_exists} do
      if not walk_file_exists do
        IO.puts("Skipping test - walk file not found")
        assert true
      else
        # Find the last OID by walking to the end
        current_oid = "1.3.6.1"
        last_oid = nil
        
        # Walk to find the last OID
        last_oid = Enum.reduce_while(1..1000, current_oid, fn _i, oid ->
          case SharedProfiles.get_next_oid(device_type, oid) do
            {:ok, next_oid} -> {:cont, next_oid}
            :end_of_mib -> {:halt, oid}
          end
        end)
        
        if last_oid do
          # GETBULK from last OID should return empty list
          case SharedProfiles.get_bulk_oids(device_type, last_oid, 5) do
            {:ok, []} ->
              IO.puts("✓ GETBULK from last OID #{last_oid} correctly returned empty list")
            {:ok, bulk_oids} ->
              flunk("GETBULK from last OID should return empty list, got: #{inspect(bulk_oids)}")
            {:error, reason} ->
              flunk("GETBULK from last OID failed: #{inspect(reason)}")
          end
        else
          flunk("Could not find last OID in walk")
        end
      end
    end
  end

  describe "Performance and stability" do
    test "repeated GETBULK calls are stable", %{device_type: device_type, walk_file_exists: walk_file_exists} do
      if not walk_file_exists do
        IO.puts("Skipping test - walk file not found")
        assert true
      else
        # Test that repeated GETBULK calls return consistent results
        start_oid = "1.3.6.1.2.1.1"
        
        # Make multiple calls and compare results
        results = Enum.map(1..5, fn _i ->
          SharedProfiles.get_bulk_oids(device_type, start_oid, 3)
        end)
        
        # All results should be identical
        first_result = List.first(results)
        
        for {result, i} <- Enum.with_index(results, 1) do
          assert result == first_result, "GETBULK call #{i} returned different result than first call"
        end
        
        IO.puts("✓ 5 repeated GETBULK calls returned consistent results")
      end
    end
  end
end
