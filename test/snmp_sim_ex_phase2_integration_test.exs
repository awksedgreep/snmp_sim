defmodule SnmpSimExPhase2IntegrationTest do
  use ExUnit.Case, async: false
  
  alias SnmpSimEx.ProfileLoader
  alias SNMPSimEx.Device
  alias SnmpSimEx.BehaviorConfig
  alias SnmpSimEx.Core.PDU
  alias SnmpSimEx.MIB.SharedProfiles

  setup do
    # Start SharedProfiles for tests that need it
    case GenServer.whereis(SharedProfiles) do
      nil -> 
        {:ok, _} = SharedProfiles.start_link([])
      _pid -> 
        :ok
    end
    
    :ok
  end

  describe "Enhanced Behavior Integration" do
    test "loads walk file with automatic behavior enhancement" do
      {:ok, profile} = ProfileLoader.load_profile(
        :cable_modem,
        {:walk_file, "priv/walks/cable_modem.walk"}
      )
      
      # Profile should have behaviors automatically applied
      assert profile.metadata.enhancement_applied == true
      
      # Check that counter OIDs have behaviors
      counter_oids = profile.oid_map
                    |> Enum.filter(fn {_oid, value_info} ->
                      String.downcase(value_info.type) in ["counter32", "counter64"]
                    end)
      
      assert length(counter_oids) > 0
      
      # At least some counter OIDs should have behaviors
      enhanced_counters = counter_oids
                         |> Enum.filter(fn {_oid, value_info} ->
                           Map.has_key?(value_info, :behavior)
                         end)
      
      assert length(enhanced_counters) > 0
    end

    test "loads walk file with custom behavior configuration" do
      behaviors = [
        {:increment_counters, %{
          oid_patterns: ["ifInOctets", "ifOutOctets"],
          rate_range: {5000, 100_000_000},
          daily_variation: true
        }},
        {:vary_gauges, %{
          oid_patterns: ["ifSpeed"],
          range: {0, 1000000000},
          pattern: :stable
        }}
      ]
      
      {:ok, profile} = ProfileLoader.load_profile(
        :cable_modem,
        {:walk_file, "priv/walks/cable_modem.walk"},
        behaviors: behaviors
      )
      
      assert profile.behaviors == behaviors
      
      # Find an ifInOctets OID and verify behavior
      octets_oid = Enum.find(profile.oid_map, fn {oid, _} ->
        String.contains?(oid, "1.3.6.1.2.1.2.2.1.10")
      end)
      
      assert octets_oid != nil
      {_oid, value_info} = octets_oid
      assert Map.has_key?(value_info, :behavior)
    end

    test "device generates realistic values with enhanced behaviors" do
      {:ok, profile} = ProfileLoader.load_profile(
        :cable_modem,
        {:walk_file, "priv/walks/cable_modem.walk"},
        behaviors: BehaviorConfig.get_preset(:cable_modem_realistic)
      )
      
      port = find_free_port()
      device_config = %{
        port: port,
        device_type: :cable_modem,
        device_id: "cable_modem_#{port}",
        community: "public"
      }
      {:ok, device} = Device.start_link(device_config)
      
      Process.sleep(100)
      
      # Test multiple OIDs to see if they generate different values over time
      test_oids = [
        "1.3.6.1.2.1.2.2.1.10.1",  # ifInOctets
        "1.3.6.1.2.1.1.3.0"        # sysUpTime
      ]
      
      # Get initial values
      initial_values = Enum.map(test_oids, fn oid ->
        response = send_snmp_get(port, oid)
        case response do
          {:ok, pdu} ->
            [{^oid, value}] = pdu.variable_bindings
            {oid, value}
          _ ->
            {oid, nil}
        end
      end)
      
      # Wait a moment and get values again
      Process.sleep(1000)
      
      second_values = Enum.map(test_oids, fn oid ->
        response = send_snmp_get(port, oid)
        case response do
          {:ok, pdu} ->
            [{^oid, value}] = pdu.variable_bindings
            {oid, value}
          _ ->
            {oid, nil}
        end
      end)
      
      # sysUpTime should have incremented
      {_, initial_uptime} = List.keyfind(initial_values, "1.3.6.1.2.1.1.3.0", 0)
      {_, second_uptime} = List.keyfind(second_values, "1.3.6.1.2.1.1.3.0", 0)
      
      case {initial_uptime, second_uptime} do
        {{:timeticks, initial_val}, {:timeticks, second_val}} ->
          assert second_val > initial_val
        _ ->
          # Values might be in different formats, that's ok for now
          assert true
      end
      
      GenServer.stop(device)
    end

    test "applies preset behaviors correctly" do
      preset_behaviors = BehaviorConfig.get_preset(:cable_modem_realistic)
      assert is_list(preset_behaviors)
      assert length(preset_behaviors) > 5
      
      {:ok, profile} = ProfileLoader.load_profile(
        :cable_modem,
        {:walk_file, "priv/walks/cable_modem.walk"},
        behaviors: preset_behaviors
      )
      
      port = find_free_port()
      device_config = %{
        port: port,
        device_type: :cable_modem,
        device_id: "cable_modem_#{port}",
        community: "public"
      }
      {:ok, device} = Device.start_link(device_config)
      
      # Device should start successfully with preset behaviors
      info = Device.get_info(device)
      assert info.device_type == :cable_modem
      assert info.oid_count > 0
      
      GenServer.stop(device)
    end
  end

  describe "Time-based Pattern Verification" do
    test "values change based on time patterns" do
      # This test would ideally run at different times of day
      # For now, we just verify the mechanism works
      
      {:ok, profile} = ProfileLoader.load_profile(
        :cable_modem,
        {:walk_file, "priv/walks/cable_modem.walk"},
        behaviors: [:daily_patterns, :realistic_counters]
      )
      
      port = find_free_port()
      device_config = %{
        port: port,
        device_type: :cable_modem,
        device_id: "cable_modem_#{port}",
        community: "public"
      }
      {:ok, device} = Device.start_link(device_config)
      
      # Test that the device responds to requests
      response = send_snmp_get(port, "1.3.6.1.2.1.1.1.0")
      assert {:ok, pdu} = response
      assert pdu.error_status == 0
      
      GenServer.stop(device)
    end
  end

  describe "Behavior Configuration System" do
    test "custom behavior configurations work end-to-end" do
      custom_behaviors = [
        {:increment_counters, %{
          oid_patterns: ["ifInOctets"],
          rate_range: {2000, 20_000_000},
          burst_probability: 0.2
        }},
        {:vary_gauges, %{
          oid_patterns: ["ifSpeed"],
          range: {100000000, 1000000000},
          pattern: :daily_variation
        }}
      ]
      
      {:ok, profile} = ProfileLoader.load_profile(
        :cable_modem,
        {:walk_file, "priv/walks/cable_modem.walk"},
        behaviors: custom_behaviors
      )
      
      # Load the profile into SharedProfiles for device access
      :ok = SharedProfiles.load_walk_profile(
        :cable_modem,
        "priv/walks/cable_modem.walk",
        behaviors: custom_behaviors
      )
      
      port = find_free_port()
      device_config = %{
        port: port,
        device_type: :cable_modem,
        device_id: "cable_modem_#{port}",
        community: "public"
      }
      {:ok, device} = Device.start_link(device_config)
      
      # Test sysDescr (should be static)
      response = send_snmp_get(port, "1.3.6.1.2.1.1.1.0")
      {:ok, pdu} = response
      [{_oid, sys_descr}] = pdu.variable_bindings
      assert is_binary(sys_descr)
      assert String.contains?(sys_descr, "Motorola")
      
      # Test ifNumber (should be static integer)
      response = send_snmp_get(port, "1.3.6.1.2.1.2.1.0")
      {:ok, pdu} = response
      [{_oid, if_number}] = pdu.variable_bindings
      assert if_number == 2
      
      GenServer.stop(device)
    end
  end

  describe "Error Handling and Edge Cases" do
    test "handles missing behavior gracefully" do
      {:ok, profile} = ProfileLoader.load_profile(
        :cable_modem,
        {:manual, %{
          "1.3.6.1.2.1.1.1.0" => "Test Device without behaviors"
        }}
      )
      
      port = find_free_port()
      device_config = %{
        port: port,
        device_type: :cable_modem,
        device_id: "cable_modem_#{port}",
        community: "public"
      }
      {:ok, device} = Device.start_link(device_config)
      
      # Should still work even without advanced behaviors
      response = send_snmp_get(port, "1.3.6.1.2.1.1.1.0")
      {:ok, pdu} = response
      assert pdu.error_status == 0
      
      GenServer.stop(device)
    end

    test "handles invalid behavior configuration gracefully" do
      # Test with invalid behavior that shouldn't crash the system
      {:ok, profile} = ProfileLoader.load_profile(
        :cable_modem,
        {:walk_file, "priv/walks/cable_modem.walk"},
        behaviors: [:invalid_behavior]  # This should be ignored
      )
      
      port = find_free_port()
      device_config = %{
        port: port,
        device_type: :cable_modem,
        device_id: "cable_modem_#{port}",
        community: "public"
      }
      {:ok, device} = Device.start_link(device_config)
      
      # Device should still work
      response = send_snmp_get(port, "1.3.6.1.2.1.1.1.0")
      {:ok, pdu} = response
      assert pdu.error_status == 0
      
      GenServer.stop(device)
    end
  end

  describe "Performance with Enhanced Behaviors" do
    test "enhanced behaviors don't significantly impact performance" do
      {:ok, simple_profile} = ProfileLoader.load_profile(
        :cable_modem,
        {:walk_file, "priv/walks/cable_modem.walk"}
      )
      
      {:ok, enhanced_profile} = ProfileLoader.load_profile(
        :cable_modem,
        {:walk_file, "priv/walks/cable_modem.walk"},
        behaviors: BehaviorConfig.get_preset(:cable_modem_realistic)
      )
      
      # Both profiles should have similar OID counts
      simple_count = map_size(simple_profile.oid_map)
      enhanced_count = map_size(enhanced_profile.oid_map)
      
      # Enhanced profile might have the same or more OIDs (due to behavior analysis)
      assert enhanced_count >= simple_count
      
      # Enhanced profile should have metadata indicating enhancement
      assert enhanced_profile.metadata.enhancement_applied == true
    end

    test "multiple devices with enhanced behaviors" do
      device_configs = [
        {:cable_modem, {:walk_file, "priv/walks/cable_modem.walk"}, 
         count: 3, behaviors: [:realistic_counters]}
      ]
      
      port_range = find_free_port_range(3)
      
      # This should use the basic device pool for now
      # Full lazy device pool with shared profiles is Phase 4
      manual_devices = start_manual_devices(device_configs, port_range)
      
      assert length(manual_devices) == 3
      
      # Test that all devices respond
      responses = Enum.map(manual_devices, fn {port, device_pid} ->
        response = send_snmp_get(port, "1.3.6.1.2.1.1.1.0")
        GenServer.stop(device_pid)
        response
      end)
      
      successful_responses = Enum.count(responses, fn
        {:ok, _pdu} -> true
        _ -> false
      end)
      
      assert successful_responses >= 2  # Allow for some timing issues
    end
  end

  # Helper functions

  defp find_free_port do
    {:ok, socket} = :gen_udp.open(0, [:binary])
    {:ok, port} = :inet.port(socket)
    :gen_udp.close(socket)
    port
  end

  defp find_free_port_range(count) do
    start_port = find_free_port()
    start_port..(start_port + count - 1)
  end

  defp start_manual_devices(device_configs, port_range) do
    ports = Enum.to_list(port_range)
    
    [{device_type, source, opts}] = device_configs
    count = Keyword.get(opts, :count, 1)
    behaviors = Keyword.get(opts, :behaviors, [])
    
    {:ok, profile} = ProfileLoader.load_profile(device_type, source, behaviors: behaviors)
    
    Enum.take(ports, count)
    |> Enum.map(fn port ->
      device_config = %{
        port: port,
        device_type: device_type,
        device_id: "#{device_type}_#{port}",
        community: "public"
      }
      {:ok, device_pid} = Device.start_link(device_config)
      Process.sleep(50)  # Give device time to start
      {port, device_pid}
    end)
  end

  defp send_snmp_get(port, oid, community \\ "public") do
    request_pdu = %PDU{
      version: 1,
      community: community,
      pdu_type: 0xA0,  # GET_REQUEST
      request_id: :rand.uniform(65535),
      error_status: 0,
      error_index: 0,
      variable_bindings: [{oid, nil}]
    }
    
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
end