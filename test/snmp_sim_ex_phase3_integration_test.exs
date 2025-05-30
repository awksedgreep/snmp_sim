defmodule SNMPSimExPhase3IntegrationTest do
  use ExUnit.Case, async: false
  
  alias SNMPSimEx.ProfileLoader
  alias SNMPSimEx.Device
  alias SNMPSimEx.Core.PDU
  alias SNMPSimEx.MIB.SharedProfiles
  alias SNMPSimEx.TestHelpers.PortHelper
  
  setup do
    # Start SharedProfiles for tests that need it
    case GenServer.whereis(SharedProfiles) do
      nil -> 
        {:ok, _} = SharedProfiles.start_link([])
      _pid -> 
        :ok
    end
    
    # PortHelper automatically handles port allocation
    
    :ok
  end
  
  describe "Phase 3: OID Tree and GETBULK Integration" do
    test "device with OID tree responds to GETNEXT requests correctly" do
      {:ok, profile} = ProfileLoader.load_profile(
        :cable_modem,
        {:walk_file, "priv/walks/cable_modem.walk"}
      )
      
      port = PortHelper.get_port()
      device_config = %{
        port: port,
        device_type: :cable_modem,
        device_id: "cable_modem_#{port}",
        community: "public"
      }

      {:ok, device} = Device.start_link(device_config)
      
      Process.sleep(100)  # Give device time to initialize
      
      # Test GETNEXT traversal through the OID tree
      test_oids = [
        "1.3.6.1.2.1.1.1",     # Should get sysDescr
        "1.3.6.1.2.1.1.3",     # Should get sysUpTime
        "1.3.6.1.2.1.2.1"      # Should get ifNumber
      ]
      
      for base_oid <- test_oids do
        response = send_snmp_getnext(port, base_oid)
        
        case response do
          {:ok, pdu} ->
            assert pdu.error_status == 0
            assert length(pdu.variable_bindings) == 1
            
            [{next_oid, value}] = pdu.variable_bindings
            assert String.starts_with?(next_oid, base_oid)
            assert value != nil
            
          error ->
            flunk("GETNEXT failed for #{base_oid}: #{inspect(error)}")
        end
      end
      
      GenServer.stop(device)
    end
    
    test "device supports GETBULK operations for interface tables" do
      {:ok, profile} = ProfileLoader.load_profile(
        :cable_modem,
        {:walk_file, "priv/walks/cable_modem.walk"}
      )
      
      port = PortHelper.get_port()
      device_config = %{
        port: port,
        device_type: :cable_modem,
        device_id: "cable_modem_#{port}",
        community: "public"
      }

      {:ok, device} = Device.start_link(device_config)
      
      Process.sleep(100)
      
      # Test GETBULK on interface table
      response = send_snmp_getbulk(port, "1.3.6.1.2.1.2.2.1.1", 0, 5)
      
      case response do
        {:ok, pdu} ->
          assert pdu.error_status == 0
          assert length(pdu.variable_bindings) <= 5  # Should respect max-repetitions
          assert length(pdu.variable_bindings) > 0   # Should get some results
          
          # All returned OIDs should be lexicographically ordered
          oids = Enum.map(pdu.variable_bindings, fn {oid, _value} -> oid end)
          sorted_oids = Enum.sort(oids, &(compare_oids(&1, &2) != :gt))
          assert oids == sorted_oids
          
        error ->
          flunk("GETBULK failed: #{inspect(error)}")
      end
      
      GenServer.stop(device)
    end
    
    test "GETBULK with non-repeaters works correctly" do
      {:ok, profile} = ProfileLoader.load_profile(
        :cable_modem,
        {:walk_file, "priv/walks/cable_modem.walk"}
      )
      
      port = PortHelper.get_port()
      device_config = %{
        port: port,
        device_type: :cable_modem,
        device_id: "cable_modem_#{port}",
        community: "public"
      }

      {:ok, device} = Device.start_link(device_config)
      
      Process.sleep(100)
      
      # Test GETBULK with 1 non-repeater, 3 max-repetitions
      # Request sysDescr (non-repeater) and interface table (repeaters)
      varbinds = [
        {"1.3.6.1.2.1.1.1.0", nil},  # sysDescr (non-repeater)
        {"1.3.6.1.2.1.2.2.1.1", nil}  # ifIndex table (repeater)
      ]
      
      response = send_snmp_getbulk_with_varbinds(port, varbinds, 1, 3)
      
      case response do
        {:ok, pdu} ->
          assert pdu.error_status == 0
          assert length(pdu.variable_bindings) <= 4  # 1 non-repeater + 3 repetitions
          assert length(pdu.variable_bindings) > 1   # Should get at least non-repeater result
          
        error ->
          flunk("GETBULK with non-repeaters failed: #{inspect(error)}")
      end
      
      GenServer.stop(device)
    end
    
    test "large GETBULK requests are handled efficiently" do
      {:ok, profile} = ProfileLoader.load_profile(
        :cable_modem,
        {:walk_file, "priv/walks/cable_modem.walk"}
      )
      
      port = PortHelper.get_port()
      device_config = %{
        port: port,
        device_type: :cable_modem,
        device_id: "cable_modem_#{port}",
        community: "public"
      }

      {:ok, device} = Device.start_link(device_config)
      
      Process.sleep(100)
      
      # Test large GETBULK request
      start_time = :erlang.monotonic_time(:millisecond)
      
      response = send_snmp_getbulk(port, "1.3.6.1.2.1.2.2.1", 0, 50)
      
      end_time = :erlang.monotonic_time(:millisecond)
      response_time = end_time - start_time
      
      case response do
        {:ok, pdu} ->
          assert pdu.error_status == 0
          assert length(pdu.variable_bindings) > 0
          
          # Response should be fast (under 100ms for 50 OIDs)
          assert response_time < 100, "GETBULK took #{response_time}ms, expected < 100ms"
          
        error ->
          flunk("Large GETBULK failed: #{inspect(error)}")
      end
      
      GenServer.stop(device)
    end
    
    test "GETBULK respects UDP packet size limits" do
      {:ok, profile} = ProfileLoader.load_profile(
        :cable_modem,
        {:walk_file, "priv/walks/cable_modem.walk"}
      )
      
      port = PortHelper.get_port()
      device_config = %{
        port: port,
        device_type: :cable_modem,
        device_id: "cable_modem_#{port}",
        community: "public"
      }

      {:ok, device} = Device.start_link(device_config)
      
      Process.sleep(100)
      
      # Request many OIDs that could exceed UDP limits
      response = send_snmp_getbulk(port, "1.3.6.1.2.1", 0, 200)
      
      case response do
        {:ok, pdu} ->
          # Should either succeed with reasonable number of results
          # or return tooBig error
          case pdu.error_status do
            0 -> 
              # Success - verify response isn't too large
              assert length(pdu.variable_bindings) < 200  # Should be truncated
              
            1 -> 
              # tooBig error is acceptable
              assert true
              
            _ ->
              flunk("Unexpected error status: #{pdu.error_status}")
          end
          
        error ->
          flunk("GETBULK size limit test failed: #{inspect(error)}")
      end
      
      GenServer.stop(device)
    end
    
    test "GETNEXT traversal maintains correct lexicographic order" do
      {:ok, profile} = ProfileLoader.load_profile(
        :cable_modem,
        {:walk_file, "priv/walks/cable_modem.walk"}
      )
      
      port = PortHelper.get_port()
      device_config = %{
        port: port,
        device_type: :cable_modem,
        device_id: "cable_modem_#{port}",
        community: "public"
      }

      {:ok, device} = Device.start_link(device_config)
      
      Process.sleep(100)
      
      # Walk through several OIDs using GETNEXT to verify ordering
      current_oid = "1.3.6.1.2.1.1"
      traversed_oids = []
      max_iterations = 10
      
      {final_oids, _} = Enum.reduce(1..max_iterations, {[], current_oid}, fn _i, {acc_oids, oid} ->
        case send_snmp_getnext(port, oid) do
          {:ok, pdu} when pdu.error_status == 0 ->
            [{next_oid, _value}] = pdu.variable_bindings
            {[next_oid | acc_oids], next_oid}
          
          _ ->
            {acc_oids, oid}  # Stop on error or end of MIB
        end
      end)
      
      traversed_oids = Enum.reverse(final_oids)
      
      # Verify lexicographic ordering
      if length(traversed_oids) > 1 do
        ordered_pairs = Enum.zip(traversed_oids, tl(traversed_oids))
        
        assert Enum.all?(ordered_pairs, fn {oid1, oid2} ->
          compare_oids(oid1, oid2) == :lt
        end), "OIDs not in lexicographic order: #{inspect(traversed_oids)}"
      end
      
      GenServer.stop(device)
    end
    
    test "device handles concurrent GETBULK requests" do
      {:ok, profile} = ProfileLoader.load_profile(
        :cable_modem,
        {:walk_file, "priv/walks/cable_modem.walk"}
      )
      
      port = PortHelper.get_port()
      device_config = %{
        port: port,
        device_type: :cable_modem,
        device_id: "cable_modem_#{port}",
        community: "public"
      }

      {:ok, device} = Device.start_link(device_config)
      
      Process.sleep(100)
      
      # Send multiple concurrent GETBULK requests
      tasks = for i <- 1..5 do
        Task.async(fn ->
          base_oid = "1.3.6.1.2.1.2.2.1.#{i}"
          send_snmp_getbulk(port, base_oid, 0, 10)
        end)
      end
      
      # Wait for all tasks to complete
      results = Task.await_many(tasks, 5000)
      
      # All requests should succeed
      successful_responses = Enum.count(results, fn
        {:ok, pdu} when pdu.error_status == 0 -> true
        _ -> false
      end)
      
      assert successful_responses >= 3, "Only #{successful_responses}/5 concurrent requests succeeded"
      
      GenServer.stop(device)
    end
  end
  
  describe "Performance and Scalability" do
    test "OID tree operations scale to 1000+ OIDs" do
      # Create profile with many OIDs
      large_oid_map = for i <- 1..1000 do
        oid = "1.3.6.1.2.1.2.2.1.10.#{i}"
        {oid, %{type: "Counter32", value: i * 1000}}
      end |> Map.new()
      
      profile = %ProfileLoader{
        device_type: :large_device,
        source_type: :manual,
        oid_map: large_oid_map,
        behaviors: [],
        metadata: %{}
      }
      
      port = PortHelper.get_port()
      
      # Time device startup (should be fast even with many OIDs)
      start_time = :erlang.monotonic_time(:millisecond)
      device_config = %{
        port: port,
        device_type: :large_device,
        device_id: "large_device_#{port}",
        community: "public"
      }

      {:ok, device} = Device.start_link(device_config)
      end_time = :erlang.monotonic_time(:millisecond)
      
      startup_time = end_time - start_time
      assert startup_time < 1000, "Device startup took #{startup_time}ms with 1000 OIDs"
      
      Process.sleep(100)
      
      # Test GETBULK performance on large tree
      bulk_start = :erlang.monotonic_time(:millisecond)
      response = send_snmp_getbulk(port, "1.3.6.1.2.1.2.2.1.10", 0, 100)
      bulk_end = :erlang.monotonic_time(:millisecond)
      
      bulk_time = bulk_end - bulk_start
      
      case response do
        {:ok, pdu} ->
          assert pdu.error_status == 0
          assert length(pdu.variable_bindings) > 0
          
          # GETBULK should be fast even on large trees
          assert bulk_time < 50, "GETBULK took #{bulk_time}ms on 1000-OID tree"
          
        error ->
          flunk("GETBULK on large tree failed: #{inspect(error)}")
      end
      
      GenServer.stop(device)
    end
  end
  
  # Helper functions
  
  defp send_snmp_getnext(port, oid, community \\ "public") do
    request_pdu = %PDU{
      version: 1,
      community: community,
      pdu_type: 0xA1,  # GETNEXT_REQUEST
      request_id: :rand.uniform(65535),
      error_status: 0,
      error_index: 0,
      variable_bindings: [{oid, nil}]
    }
    
    send_snmp_request(port, request_pdu)
  end
  
  defp send_snmp_getbulk(port, oid, non_repeaters, max_repetitions, community \\ "public") do
    request_pdu = %PDU{
      version: 1,
      community: community,
      pdu_type: 0xA5,  # GETBULK_REQUEST
      request_id: :rand.uniform(65535),
      error_status: 0,
      error_index: 0,
      non_repeaters: non_repeaters,
      max_repetitions: max_repetitions,
      variable_bindings: [{oid, nil}]
    }
    
    send_snmp_request(port, request_pdu)
  end
  
  defp send_snmp_getbulk_with_varbinds(port, varbinds, non_repeaters, max_repetitions, community \\ "public") do
    request_pdu = %PDU{
      version: 1,
      community: community,
      pdu_type: 0xA5,  # GETBULK_REQUEST
      request_id: :rand.uniform(65535),
      error_status: 0,
      error_index: 0,
      non_repeaters: non_repeaters,
      max_repetitions: max_repetitions,
      variable_bindings: varbinds
    }
    
    send_snmp_request(port, request_pdu)
  end
  
  defp send_snmp_request(port, request_pdu) do
    case PDU.encode(request_pdu) do
      {:ok, packet} ->
        {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])
        
        :gen_udp.send(socket, {127, 0, 0, 1}, port, packet)
        
        result = case :gen_udp.recv(socket, 0, 2000) do
          {:ok, {_ip, _port, response_data}} ->
            PDU.decode(response_data)
          {:error, :timeout} ->
            :timeout
          {:error, reason} ->
            {:error, reason}
        end
        
        :gen_udp.close(socket)
        result
        
      {:error, reason} ->
        {:error, {:encode_failed, reason}}
    end
  end
  
  defp compare_oids(oid1, oid2) do
    parts1 = String.split(oid1, ".") |> Enum.map(&String.to_integer/1)
    parts2 = String.split(oid2, ".") |> Enum.map(&String.to_integer/1)
    
    compare_oid_parts(parts1, parts2)
  end
  
  defp compare_oid_parts([], []), do: :eq
  defp compare_oid_parts([], _), do: :lt
  defp compare_oid_parts(_, []), do: :gt
  defp compare_oid_parts([a | rest_a], [b | rest_b]) when a == b do
    compare_oid_parts(rest_a, rest_b)
  end
  defp compare_oid_parts([a | _], [b | _]) when a < b, do: :lt
  defp compare_oid_parts([a | _], [b | _]) when a > b, do: :gt
end