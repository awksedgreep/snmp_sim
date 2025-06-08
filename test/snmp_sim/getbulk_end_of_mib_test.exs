defmodule SnmpSim.GetbulkEndOfMibTest do
  use ExUnit.Case, async: false
  alias SnmpSim.MIB.SharedProfiles
  alias SnmpSim.Device

  @moduletag :integration

  setup_all do
    # Start the application
    Application.ensure_all_started(:snmp_sim)
    
    # Load test profile
    profile_path = "priv/walks/cable_modem.walk"
    {:ok, profile_loader} = SnmpSim.ProfileLoader.load_profile(:cable_modem, {:walk_file, profile_path})
    
    # Extract data from ProfileLoader struct
    profile_data = Enum.to_list(profile_loader.oid_map)
    behavior_data = profile_loader.behaviors
    
    # Store the profile
    device_type = "cable_modem"
    :ok = SharedProfiles.store_profile(device_type, profile_data, behavior_data)
    
    # Get sorted OIDs for testing
    all_oids = Enum.map(profile_data, fn {oid, _data} -> oid end) 
      |> Enum.sort(&SharedProfiles.compare_oids_lexicographically/2)
    
    %{
      device_type: device_type,
      profile_data: profile_data,
      all_oids: all_oids,
      last_oid: List.last(all_oids),
      second_last_oid: Enum.at(all_oids, -2)
    }
  end

  describe "OID progression fixes" do
    test "get_next_oid does not return same OID (fixes infinite loop)", %{device_type: device_type, all_oids: all_oids} do
      # Test that get_next_oid never returns the same OID it was given
      # This was the core bug causing infinite loops
      
      # Test with several OIDs from the walk file
      test_oids = Enum.take_every(all_oids, div(length(all_oids), 10))
      
      for oid <- test_oids do
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
    
    test "get_next_oid progression covers all OIDs without loops", %{device_type: device_type, all_oids: all_oids} do
      # Start from first OID and walk through all OIDs
      # This should never loop and should cover all OIDs
      
      first_oid = List.first(all_oids)
      visited_oids = MapSet.new()
      current_oid = first_oid
      
      # Walk through OIDs, ensuring no loops
      {final_visited, _} = Enum.reduce_while(1..length(all_oids) + 10, {visited_oids, current_oid}, fn _i, {visited, oid} ->
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
      
      # Should have visited all OIDs in the walk file
      assert MapSet.size(final_visited) == length(all_oids)
    end
  end

  describe "GETBULK collection fixes" do
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
      
      # Test with several starting OIDs
      test_oids = Enum.take(all_oids, 5)
      
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
      max_repetitions = 10
      total_oids_collected = 0
      iterations = 0
      max_iterations = 100  # Safety limit
      
      {final_iterations, final_total} = Enum.reduce_while(1..max_iterations, {current_oid, 0}, fn i, {oid, total} ->
        case SharedProfiles.get_bulk_oids(device_type, oid, max_repetitions) do
          {:ok, bulk_oids} when length(bulk_oids) > 0 ->
            {_last_oid, _, _} = List.last(bulk_oids)
            new_total = total + length(bulk_oids)
            {:cont, {_last_oid, new_total}}
            
          {:ok, []} ->
            # End of MIB reached
            {:halt, {i, total}}
            
          {:error, reason} ->
            flunk("GETBULK failed at iteration #{i}: #{inspect(reason)}")
        end
      end)
      
      # Should complete within reasonable number of iterations
      assert final_iterations < max_iterations, "GETBULK walk did not complete within #{max_iterations} iterations"
      
      # Should collect a reasonable number of OIDs
      assert final_total > 0, "No OIDs collected during GETBULK walk"
      
      IO.puts("GETBULK walk completed in #{final_iterations} iterations, collected #{final_total} OIDs")
    end
  end

  describe "SNMP protocol compliance" do
    setup %{device_type: device_type} do
      # Start a test device
      port = 30199
      {:ok, device_pid} = Device.start_link(%{
        device_id: "test_device_#{port}",
        device_type: device_type,
        port: port,
        device_state: %{}
      })
      
      # Wait for device to initialize
      Process.sleep(500)
      
      on_exit(fn ->
        GenServer.stop(device_pid)
      end)
      
      %{port: port, device_pid: device_pid}
    end
    
    test "SNMP GETBULK from last OID returns endOfMibView", %{port: port, last_oid: last_oid} do
      # Test that GETBULK from last OID returns proper endOfMibView response
      
      {output, exit_code} = System.cmd("snmpbulkget", [
        "-v2c", "-c", "public", "127.0.0.1:#{port}",
        "-Cn0", "-Cr1", last_oid
      ], stderr_to_stdout: true)
      
      assert exit_code == 0, "SNMP command failed: #{output}"
      assert String.contains?(output, "No more variables left in this MIB View"), 
        "Expected endOfMibView response, got: #{output}"
      
      # Should contain only one endOfMibView response, not multiple
      end_of_mib_count = output
        |> String.split("\n")
        |> Enum.count(&String.contains?(&1, "No more variables left in this MIB View"))
      
      assert end_of_mib_count == 1, "Expected 1 endOfMibView response, got #{end_of_mib_count}"
    end
    
    test "SNMP GETBULK walk terminates correctly", %{port: port} do
      # Test that broad SNMP walk terminates without hanging
      
      {output, exit_code} = System.cmd("timeout", [
        "30s", "snmpbulkwalk", "-v2c", "-c", "public", 
        "127.0.0.1:#{port}", "1.3.6.1"
      ], stderr_to_stdout: true)
      
      # Should complete within timeout (exit_code 0) or reach end of MIB gracefully
      # If it times out (exit_code 124), that indicates the old infinite loop bug
      refute exit_code == 124, "SNMP walk timed out - indicates infinite loop bug returned"
      
      # Should contain actual OID data
      assert String.contains?(output, "1.3.6.1"), "Walk output should contain OIDs"
      
      # Should end with endOfMibView or complete successfully
      assert exit_code == 0 or String.contains?(output, "No more variables left in this MIB View"),
        "Walk should complete successfully or with endOfMibView"
    end
    
    test "SNMP GETNEXT progression works correctly", %{port: port} do
      # Test that GETNEXT operations progress correctly through the MIB
      
      start_oid = "1.3.6.1"
      current_oid = start_oid
      visited_oids = MapSet.new()
      max_steps = 20
      
      # Walk through several GETNEXT operations
      Enum.reduce_while(1..max_steps, current_oid, fn _i, oid ->
        {output, exit_code} = System.cmd("snmpgetnext", [
          "-v2c", "-c", "public", "127.0.0.1:#{port}", oid
        ], stderr_to_stdout: true)
        
        if exit_code != 0 do
          {:halt, oid}
        else
          # Extract the returned OID from output
          case Regex.run(~r/^\.([0-9.]+) =/, output) do
            [_, returned_oid] ->
              # Check for loops
              if MapSet.member?(visited_oids, returned_oid) do
                flunk("GETNEXT loop detected: OID #{returned_oid} returned twice")
              end
              
              new_visited = MapSet.put(visited_oids, returned_oid)
              {:cont, returned_oid}
              
            nil ->
              # End of MIB or error
              {:halt, oid}
          end
        end
      end)
      
      # Should have made progress without loops
      assert MapSet.size(visited_oids) > 0, "GETNEXT should return at least some OIDs"
    end
  end

  describe "edge cases and regression tests" do
    test "problematic OID 1.3.6.1.2.1.2.2.1.21.1 does not loop", %{device_type: device_type} do
      # This specific OID was causing infinite loops in the original bug
      problematic_oid = "1.3.6.1.2.1.2.2.1.21.1"
      
      case SharedProfiles.get_next_oid(device_type, problematic_oid) do
        {:ok, next_oid} ->
          assert next_oid != problematic_oid, "Problematic OID still returns itself"
          assert next_oid == "1.3.6.1.2.1.2.2.1.21.2", "Expected next OID to be 1.3.6.1.2.1.2.2.1.21.2"
        :end_of_mib ->
          # This is fine if it's actually the last OID
          :ok
      end
    end
    
    test "empty walk file handling", %{device_type: device_type} do
      # Test behavior with empty or minimal walk files
      
      # Store empty profile
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
  end
end
