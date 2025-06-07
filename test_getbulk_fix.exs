#!/usr/bin/env elixir

# Simple test script to verify GETBULK fallback functionality

defmodule GetBulkTest do
  def test_fallback_bulk_oids do
    # Simulate device state
    state = %{device_type: :cable_modem}
    
    # Test the fallback function with OID "1.3.6.1"
    result = get_fallback_bulk_oids("1.3.6.1", 10, state)
    
    IO.puts("GETBULK fallback result for OID '1.3.6.1':")
    IO.inspect(result, pretty: true)
    
    # Verify we get multiple OIDs (not just one)
    case result do
      [] -> 
        IO.puts("❌ ERROR: Empty result - no OIDs returned")
      [single_result] -> 
        IO.puts("⚠️  WARNING: Only one OID returned: #{inspect(single_result)}")
      multiple_results when is_list(multiple_results) -> 
        IO.puts("✅ SUCCESS: #{length(multiple_results)} OIDs returned for GETBULK walking")
        
        # Check format of first few results
        Enum.take(multiple_results, 3)
        |> Enum.with_index()
        |> Enum.each(fn {{oid, type, value}, index} ->
          IO.puts("  [#{index}] OID: #{oid}, Type: #{type}, Value: #{inspect(value)}")
        end)
      other -> 
        IO.puts("❌ ERROR: Unexpected result format: #{inspect(other)}")
    end
  end
  
  # Copy the fallback function from device.ex for testing
  defp get_fallback_bulk_oids(start_oid, max_repetitions, state) do
    case start_oid do
      "1.3.6.1.2.1.2.2.1.1" ->
        for i <- 1..min(max_repetitions, 3) do
          {"1.3.6.1.2.1.2.2.1.1.#{i}", i}
        end
      "1.3.6.1.2.1.2.2.1.10" ->
        for i <- 1..min(max_repetitions, 3) do
          {"1.3.6.1.2.1.2.2.1.10.#{i}", {:counter32, i * 1000}}
        end
      oid when oid in ["1.3.6.1", "1.3.6.1.2", "1.3.6.1.2.1", "1.3.6.1.2.1.1"] ->
        system_oids = [
          {"1.3.6.1.2.1.1.1.0", :octet_string, case state.device_type do
            :cable_modem -> "Motorola SB6141 DOCSIS 3.0 Cable Modem"
            :cmts -> "Cisco CMTS Cable Modem Termination System" 
            :router -> "Cisco Router"
            _ -> "SNMP Simulator Device"
          end},
          {"1.3.6.1.2.1.1.2.0", :oid, [1, 3, 6, 1, 4, 1, 4491, 2, 1, 21, 1, 1]},
          {"1.3.6.1.2.1.1.3.0", :timeticks, 123456789},
          {"1.3.6.1.2.1.1.4.0", :octet_string, "System Contact"},
          {"1.3.6.1.2.1.1.5.0", :octet_string, "snmp-sim-device"},
          {"1.3.6.1.2.1.1.6.0", :octet_string, "SNMP Simulator Location"},
          {"1.3.6.1.2.1.1.7.0", :integer, 72},
          {"1.3.6.1.2.1.2.1.0", :integer, 2},
          {"1.3.6.1.2.1.2.2.1.1.1", :integer, 1},
          {"1.3.6.1.2.1.2.2.1.1.2", :integer, 2},
          {"1.3.6.1.2.1.2.2.1.2.1", :octet_string, "eth0"},
          {"1.3.6.1.2.1.2.2.1.2.2", :octet_string, "eth1"},
          {"1.3.6.1.2.1.2.2.1.3.1", :integer, 6},
          {"1.3.6.1.2.1.2.2.1.3.2", :integer, 6},
          {"1.3.6.1.2.1.2.2.1.5.1", :gauge32, 100000000},
          {"1.3.6.1.2.1.2.2.1.5.2", :gauge32, 100000000},
          {"1.3.6.1.2.1.2.2.1.8.1", :integer, 1},
          {"1.3.6.1.2.1.2.2.1.8.2", :integer, 1},
          {"1.3.6.1.2.1.2.2.1.10.1", :counter32, 2320569},
          {"1.3.6.1.2.1.2.2.1.10.2", :counter32, 1845123},
          {"1.3.6.1.2.1.2.2.1.16.1", :counter32, 2512272},
          {"1.3.6.1.2.1.2.2.1.16.2", :counter32, 1923456}
        ]
        
        filtered_oids = Enum.filter(system_oids, fn {oid, _, _} ->
          compare_oids_lexicographically(start_oid, oid)
        end)
        
        Enum.take(filtered_oids, max_repetitions)
      _ ->
        case get_fallback_next_oid(start_oid, state) do
          {_oid_list, :end_of_mib_view, _} -> []
          single_result -> [single_result]
        end
    end
  end
  
  defp get_fallback_next_oid(oid, state) do
    case oid do
      oid when oid in ["1.3.6.1.2.1", "1.3.6.1.2.1.1", "1.3.6.1", "1.3.6", "1.3", "1"] ->
        device_type_str = case state.device_type do
          :cable_modem -> "Motorola SB6141 DOCSIS 3.0 Cable Modem"
          :cmts -> "Cisco CMTS Cable Modem Termination System"
          :router -> "Cisco Router"
          _ -> "SNMP Simulator Device"
        end
        {[1, 3, 6, 1, 2, 1, 1, 1, 0], :octet_string, device_type_str}
      _ ->
        oid_list = case oid do
          oid when is_list(oid) -> oid
          oid when is_binary(oid) -> string_to_oid_list(oid)
          _ -> oid
        end
        {oid_list, :end_of_mib_view, {:end_of_mib_view, nil}}
    end
  end
  
  defp compare_oids_lexicographically(oid1, oid2) do
    list1 = case oid1 do
      oid when is_binary(oid) -> string_to_oid_list(oid)
      oid when is_list(oid) -> oid
      _ -> []
    end
    
    list2 = case oid2 do
      oid when is_binary(oid) -> string_to_oid_list(oid)
      oid when is_list(oid) -> oid
      _ -> []
    end
    
    list1 < list2
  end
  
  defp string_to_oid_list(oid_string) when is_binary(oid_string) do
    oid_string
    |> String.split(".")
    |> Enum.map(&String.to_integer/1)
  end
  defp string_to_oid_list(oid) when is_list(oid), do: oid
  defp string_to_oid_list(oid), do: oid
end

GetBulkTest.test_fallback_bulk_oids()
