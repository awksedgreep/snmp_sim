defmodule SnmpSimExIntegrationTest do
  use ExUnit.Case, async: false
  
  alias SnmpSimEx.{ProfileLoader, Device, LazyDevicePool}
  alias SnmpSimEx.Core.PDU

  describe "End-to-End Device Simulation" do
    test "loads profile and starts device successfully" do
      # Load profile from walk file
      {:ok, profile} = ProfileLoader.load_profile(
        :cable_modem,
        {:walk_file, "priv/walks/cable_modem.walk"}
      )
      
      port = find_free_port()
      
      # Start device
      {:ok, device} = Device.start_link(profile, port: port)
      
      # Wait for device to be ready
      Process.sleep(100)
      
      # Test SNMP GET request
      response = send_snmp_get(port, "1.3.6.1.2.1.1.1.0")
      
      assert {:ok, pdu} = response
      assert pdu.error_status == 0
      assert length(pdu.variable_bindings) == 1
      
      [{oid, value}] = pdu.variable_bindings
      assert oid == "1.3.6.1.2.1.1.1.0"
      assert is_binary(value) and String.contains?(value, "Motorola")
      
      GenServer.stop(device)
    end

    test "handles GETNEXT operations correctly" do
      {:ok, profile} = ProfileLoader.load_profile(
        :cable_modem,
        {:walk_file, "priv/walks/cable_modem.walk"}
      )
      
      port = find_free_port()
      {:ok, device} = Device.start_link(profile, port: port)
      
      Process.sleep(100)
      
      # Test GETNEXT starting from system group
      response = send_snmp_getnext(port, "1.3.6.1.2.1.1")
      
      assert {:ok, pdu} = response
      assert pdu.error_status == 0
      assert length(pdu.variable_bindings) == 1
      
      [{next_oid, _value}] = pdu.variable_bindings
      assert String.starts_with?(next_oid, "1.3.6.1.2.1.1.")
      
      GenServer.stop(device)
    end

    test "responds with proper error for non-existent OIDs" do
      {:ok, profile} = ProfileLoader.load_profile(
        :cable_modem,
        {:walk_file, "priv/walks/cable_modem.walk"}
      )
      
      port = find_free_port()
      {:ok, device} = Device.start_link(profile, port: port)
      
      Process.sleep(100)
      
      # Request non-existent OID
      response = send_snmp_get(port, "1.3.6.1.2.1.99.99.99.0")
      
      assert {:ok, pdu} = response
      assert length(pdu.variable_bindings) == 1
      
      [{_oid, value}] = pdu.variable_bindings
      assert match?({:no_such_object, _}, value)
      
      GenServer.stop(device)
    end

    test "handles multiple devices simultaneously" do
      device_configs = [
        {:cable_modem, {:walk_file, "priv/walks/cable_modem.walk"}, count: 3}
      ]
      
      port_range = find_free_port_range(3)
      
      {:ok, devices} = LazyDevicePool.start_device_population(
        device_configs,
        port_range: port_range
      )
      
      assert map_size(devices) == 3
      
      # Test each device responds independently
      device_ports = devices
                    |> Enum.map(fn {%{port: port}, _pid} -> port end)
                    |> Enum.sort()
      
      responses = Enum.map(device_ports, fn port ->
        send_snmp_get(port, "1.3.6.1.2.1.1.1.0")
      end)
      
      # All devices should respond successfully
      assert Enum.all?(responses, fn
        {:ok, pdu} -> pdu.error_status == 0
        _ -> false
      end)
      
      # Stop all devices
      Enum.each(devices, fn {_info, pid} -> GenServer.stop(pid) end)
    end

    test "device info and statistics work correctly" do
      {:ok, profile} = ProfileLoader.load_profile(
        :cable_modem,
        {:walk_file, "priv/walks/cable_modem.walk"}
      )
      
      port = find_free_port()
      {:ok, device} = Device.start_link(profile, port: port, mac_address: "00:1A:2B:3C:4D:5E")
      
      Process.sleep(100)
      
      # Get device info
      info = Device.get_info(device)
      
      assert info.device_type == :cable_modem
      assert info.port == port
      assert info.mac_address == "00:1A:2B:3C:4D:5E"
      assert info.oid_count > 0
      assert is_integer(info.uptime)
      
      GenServer.stop(device)
    end

    test "device reboot functionality works" do
      {:ok, profile} = ProfileLoader.load_profile(
        :cable_modem,
        {:walk_file, "priv/walks/cable_modem.walk"}
      )
      
      port = find_free_port()
      {:ok, device} = Device.start_link(profile, port: port)
      
      Process.sleep(100)
      
      # Get initial uptime
      initial_info = Device.get_info(device)
      assert is_map(initial_info), "Initial device info should be a map, got: #{inspect(initial_info)}"
      initial_uptime = initial_info.uptime
      
      # Reboot device
      :ok = Device.reboot(device)
      
      Process.sleep(50)
      
      # Check uptime was reset
      final_info = Device.get_info(device)
      assert is_map(final_info), "Final device info should be a map, got: #{inspect(final_info)}"
      final_uptime = final_info.uptime
      
      assert final_uptime < initial_uptime
      
      GenServer.stop(device)
    end
  end

  describe "Performance and Reliability" do
    test "handles multiple concurrent requests per device" do
      {:ok, profile} = ProfileLoader.load_profile(
        :cable_modem,
        {:walk_file, "priv/walks/cable_modem.walk"}
      )
      
      port = find_free_port()
      {:ok, device} = Device.start_link(profile, port: port)
      
      Process.sleep(100)
      
      # Send multiple concurrent requests
      tasks = for i <- 1..20 do
        Task.async(fn ->
          send_snmp_get(port, "1.3.6.1.2.1.1.1.0")
        end)
      end
      
      results = Enum.map(tasks, &Task.await(&1, 5000))
      
      # All requests should succeed
      successful = Enum.count(results, fn
        {:ok, pdu} -> pdu.error_status == 0
        _ -> false
      end)
      
      assert successful >= 18  # Allow for some timing issues
      
      GenServer.stop(device)
    end

    test "device memory usage remains stable" do
      {:ok, profile} = ProfileLoader.load_profile(
        :cable_modem,
        {:walk_file, "priv/walks/cable_modem.walk"}
      )
      
      port = find_free_port()
      {:ok, device} = Device.start_link(profile, port: port)
      
      Process.sleep(100)
      
      # Get initial memory usage
      initial_memory = get_process_memory(device)
      
      # Send many requests to stress test memory
      for _i <- 1..100 do
        send_snmp_get(port, "1.3.6.1.2.1.1.1.0")
      end
      
      Process.sleep(500)
      
      # Check final memory usage
      final_memory = get_process_memory(device)
      
      # Memory should not have grown significantly (allow for some variance)
      memory_growth = final_memory - initial_memory
      assert memory_growth < initial_memory * 0.5  # Less than 50% growth
      
      GenServer.stop(device)
    end
  end

  describe "Error Handling and Edge Cases" do
    test "handles invalid community strings" do
      {:ok, profile} = ProfileLoader.load_profile(
        :cable_modem,
        {:walk_file, "priv/walks/cable_modem.walk"}
      )
      
      port = find_free_port()
      {:ok, device} = Device.start_link(profile, port: port, community: "secret")
      
      Process.sleep(100)
      
      # Send request with wrong community
      response = send_snmp_get(port, "1.3.6.1.2.1.1.1.0", "wrong")
      
      # Should timeout (server ignores invalid community)
      assert response == :timeout
      
      GenServer.stop(device)
    end

    test "handles port conflicts gracefully" do
      # Trap exits to handle GenServer failures properly
      Process.flag(:trap_exit, true)
      
      {:ok, profile} = ProfileLoader.load_profile(
        :cable_modem,
        {:walk_file, "priv/walks/cable_modem.walk"}
      )
      
      port = find_free_port()
      
      # Start first device
      {:ok, device1} = Device.start_link(profile, port: port)
      
      # Try to start second device on same port - this should fail due to port conflict
      # Use spawn_link and catch the exit to get proper error handling
      parent = self()
      spawn_link(fn ->
        result = Device.start_link(profile, port: port)
        send(parent, {:result, result})
      end)
      
      result = receive do
        {:result, res} -> res
        {:EXIT, _pid, reason} -> {:error, reason}
      after
        1000 -> {:error, :timeout}
      end
      
      # Should get an error return
      case result do
        {:error, :eaddrinuse} ->
          # Expected outcome
          :ok
        {:error, reason} ->
          flunk("Expected :eaddrinuse but got: #{inspect(reason)}")
        {:ok, _pid} ->
          flunk("Expected failure but device started successfully")
      end
      
      GenServer.stop(device1)
    end

    test "device population handles mixed success/failure" do
      device_configs = [
        {:cable_modem, {:walk_file, "priv/walks/cable_modem.walk"}, count: 2},
        {:bad_device, {:walk_file, "non_existent_file.walk"}, count: 1}
      ]
      
      port_range = find_free_port_range(3)
      
      result = LazyDevicePool.start_device_population(
        device_configs,
        port_range: port_range
      )
      
      # Should fail due to bad profile
      assert {:error, _reason} = result
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
    
    send_snmp_request(port, request_pdu)
  end

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

  defp send_snmp_request(port, pdu) do
    case PDU.encode(pdu) do
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

  defp get_process_memory(pid) do
    info = Process.info(pid, :memory)
    case info do
      {:memory, memory} -> memory
      nil -> 0
    end
  end
end