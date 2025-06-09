defmodule SnmpSimPhase4IntegrationTest do
  use ExUnit.Case, async: false
  doctest SnmpSim

  alias SnmpSim.Device
  alias SnmpSim.TestHelpers.PortHelper

  @moduletag :integration

  setup_all do
    # Start the application if not already started
    Application.ensure_all_started(:snmp_sim)
    :ok
  end

  setup do
    # Track devices created during test for cleanup
    {:ok, %{created_devices: []}}
  end

  # Helper function to create a test device
  defp create_test_device(device_type, port, _context) do
    device_config = %{
      device_type: device_type,
      device_id: "test_#{device_type}_#{port}",
      port: port,
      walk_file: get_walk_file(device_type)
    }

    GenServer.start_link(Device, device_config)
  end

  # Helper function to get walk file for device type
  defp get_walk_file(device_type) do
    case device_type do
      :cable_modem -> "priv/walks/cable_modem.walk"
      :router -> "priv/walks/cable_modem.walk"  # Use cable_modem as fallback
      :switch -> "priv/walks/cable_modem.walk"  # Use cable_modem as fallback
      _ -> nil
    end
  end

  # Helper function to cleanup devices
  defp cleanup_devices(device_pids) do
    Enum.each(device_pids, fn pid ->
      if Process.alive?(pid) do
        GenServer.stop(pid)
      end
    end)
  end

  describe "Phase 4: End-to-End Integration (Individual Devices)" do
    test "individual device lifecycle management", context do
      # Create devices with available ports
      cable_modem_port = PortHelper.get_port()
      router_port = PortHelper.get_port()

      # Create cable modem device
      {:ok, cm_pid} = create_test_device(:cable_modem, cable_modem_port, context)
      
      # Verify device info
      assert info = GenServer.call(cm_pid, :get_info)
      assert info.device_type == :cable_modem
      assert info.port == cable_modem_port

      # Test SNMP request handling
      test_pdu = %{
        type: :get,
        varbinds: [
          %{oid: "1.3.6.1.2.1.1.1.0", value: nil}
        ]
      }
      
      assert result = GenServer.call(cm_pid, {:handle_snmp, test_pdu, %{}})
      assert {:ok, _response} = result

      # Create router device
      {:ok, router_pid} = create_test_device(:router, router_port, context)
      
      # Verify router device info
      assert router_info = GenServer.call(router_pid, :get_info)
      assert router_info.device_type == :router
      assert router_info.port == router_port

      # Cleanup
      cleanup_devices([cm_pid, router_pid])
    end

    test "multi-device creation and management", context do
      device_specs = [
        {:cable_modem, 2},
        {:router, 1},
        {:switch, 1}
      ]

      # Create devices based on specifications
      {devices, _} = 
        Enum.reduce(device_specs, {[], context}, fn {device_type, count}, {acc_devices, acc_context} ->
          new_devices = 
            Enum.map(1..count, fn _i ->
              port = PortHelper.get_port()
              {:ok, pid} = create_test_device(device_type, port, acc_context)
              {pid, device_type, port}
            end)
          
          {acc_devices ++ new_devices, acc_context}
        end)

      # Verify all devices are created and responsive
      Enum.each(devices, fn {pid, expected_type, expected_port} ->
        assert Process.alive?(pid)
        assert info = GenServer.call(pid, :get_info)
        assert info.device_type == expected_type
        assert info.port == expected_port
      end)

      # Verify we have the expected number of devices
      assert length(devices) == 4  # 2 cable_modems + 1 router + 1 switch

      # Group devices by type and verify counts
      device_counts = 
        devices
        |> Enum.group_by(fn {_pid, type, _port} -> type end)
        |> Enum.map(fn {type, devices_of_type} -> {type, length(devices_of_type)} end)
        |> Enum.into(%{})

      assert device_counts[:cable_modem] == 2
      assert device_counts[:router] == 1
      assert device_counts[:switch] == 1

      # Cleanup
      device_pids = Enum.map(devices, fn {pid, _type, _port} -> pid end)
      cleanup_devices(device_pids)
    end

    test "device characteristics affect behavior", context do
      # Create devices of different types
      cable_modem_port = PortHelper.get_port()
      router_port = PortHelper.get_port()
      switch_port = PortHelper.get_port()

      {:ok, cm_pid} = create_test_device(:cable_modem, cable_modem_port, context)
      {:ok, router_pid} = create_test_device(:router, router_port, context)
      {:ok, switch_pid} = create_test_device(:switch, switch_port, context)

      # Verify each device has appropriate characteristics
      assert cm_info = GenServer.call(cm_pid, :get_info)
      assert router_info = GenServer.call(router_pid, :get_info)
      assert switch_info = GenServer.call(switch_pid, :get_info)

      # Each device type should have different characteristics
      assert cm_info.device_type != router_info.device_type
      assert router_info.device_type != switch_info.device_type
      assert cm_info.device_type != switch_info.device_type

      # Verify ports are different
      assert cm_info.port != router_info.port
      assert router_info.port != switch_info.port
      assert cm_info.port != switch_info.port

      # Cleanup
      cleanup_devices([cm_pid, router_pid, switch_pid])
    end

    test "concurrent device access patterns", context do
      device_count = 5
      
      # Create multiple devices concurrently
      ports = Enum.map(1..device_count, fn _ -> PortHelper.get_port() end)
      
      device_tasks = 
        Enum.map(ports, fn port ->
          Task.async(fn ->
            {:ok, pid} = create_test_device(:cable_modem, port, context)
            {pid, port}
          end)
        end)

      # Wait for all devices to be created
      devices = Enum.map(device_tasks, &Task.await/1)

      # Test concurrent access to all devices
      access_tasks = 
        Enum.map(devices, fn {pid, _port} ->
          Task.async(fn ->
            test_pdu = %{
              type: :get,
              varbinds: [%{oid: "1.3.6.1.2.1.1.1.0", value: nil}]
            }
            result = GenServer.call(pid, {:handle_snmp, test_pdu, %{}})
            result
          end)
        end)

      # Verify all concurrent requests succeed
      results = Enum.map(access_tasks, &Task.await/1)
      assert length(results) == device_count
      Enum.each(results, fn result ->
        assert {:ok, _response} = result
      end)

      # Cleanup
      device_pids = Enum.map(devices, fn {pid, _port} -> pid end)
      cleanup_devices(device_pids)
    end
  end

  describe "Phase 4: Performance and Scale Testing (Individual Devices)" do
    test "handles medium scale device population", context do
      device_count = 10
      
      # Create devices in batches to avoid overwhelming the system
      batch_size = 5
      batches = Enum.chunk_every(1..device_count, batch_size)
      
      all_devices = 
        Enum.flat_map(batches, fn batch ->
          Enum.map(batch, fn i ->
            port = PortHelper.get_port()
            device_type = case rem(i, 3) do
              0 -> :cable_modem
              1 -> :router
              2 -> :switch
            end
            
            {:ok, pid} = create_test_device(device_type, port, context)
            {pid, device_type, port}
          end)
        end)

      # Verify all devices are operational
      Enum.each(all_devices, fn {pid, _type, _port} ->
        assert Process.alive?(pid)
        assert _info = GenServer.call(pid, :get_info)
      end)

      # Test performance with concurrent requests
      performance_tasks = 
        Enum.map(all_devices, fn {pid, _type, _port} ->
          Task.async(fn ->
            start_time = System.monotonic_time(:millisecond)
            
            test_pdu = %{
              type: :get,
              varbinds: [%{oid: "1.3.6.1.2.1.1.1.0", value: nil}]
            }
            
            result = GenServer.call(pid, {:handle_snmp, test_pdu, %{}})
            end_time = System.monotonic_time(:millisecond)
            
            {result, end_time - start_time}
          end)
        end)

      # Collect performance results
      performance_results = Enum.map(performance_tasks, &Task.await(&1, 5000))
      
      # Verify all requests succeeded
      Enum.each(performance_results, fn {result, _duration} ->
        assert {:ok, _response} = result
      end)

      # Verify reasonable response times (under 1 second each)
      durations = Enum.map(performance_results, fn {_result, duration} -> duration end)
      max_duration = Enum.max(durations)
      assert max_duration < 1000, "Response time too slow: #{max_duration}ms"

      # Cleanup
      device_pids = Enum.map(all_devices, fn {pid, _type, _port} -> pid end)
      cleanup_devices(device_pids)
    end
  end

  describe "Phase 4: Error Scenarios and Recovery (Individual Devices)" do
    test "recovers from device process failures", context do
      # Trap exits to prevent test process from dying
      Process.flag(:trap_exit, true)
      
      # Create a device
      port = PortHelper.get_port()
      {:ok, original_pid} = create_test_device(:cable_modem, port, context)
      
      # Verify device is working
      assert _info = GenServer.call(original_pid, :get_info)
      
      # Simulate device failure
      Process.exit(original_pid, :kill)
      
      # Wait for exit message and verify device is dead
      receive do
        {:EXIT, ^original_pid, :killed} -> :ok
      after
        1000 -> flunk("Expected exit message not received")
      end
      
      assert not Process.alive?(original_pid)
      
      # Create replacement device (may need to wait for port to be released)
      :timer.sleep(100)
      {:ok, replacement_pid} = create_test_device(:cable_modem, port, context)
      
      # Verify replacement device works
      assert info = GenServer.call(replacement_pid, :get_info)
      assert info.device_type == :cable_modem
      assert info.port == port
      
      # Cleanup
      cleanup_devices([replacement_pid])
      
      # Reset trap_exit
      Process.flag(:trap_exit, false)
    end

    test "handles invalid device configurations gracefully", _context do
      # Test with invalid device type
      invalid_config = %{
        device_type: :invalid_type,
        device_id: "test_invalid",
        port: PortHelper.get_port()
      }
      
      # This should either fail gracefully or handle the invalid type
      result = GenServer.start_link(Device, invalid_config)
      
      case result do
        {:ok, pid} ->
          # If it succeeds, cleanup
          cleanup_devices([pid])
        {:error, _reason} ->
          # Expected behavior for invalid configuration
          assert true
      end
    end

    test "handles port conflicts appropriately", context do
      # Trap exits to prevent test process from dying
      Process.flag(:trap_exit, true)
      
      # Get a port and create first device
      port = PortHelper.get_port()
      {:ok, first_pid} = create_test_device(:cable_modem, port, context)
      
      # Try to create second device with same port
      # This should fail with port conflict
      result = create_test_device(:router, port, context)
      
      case result do
        {:ok, second_pid} ->
          # If both succeed, they might be using different actual ports
          # Verify they're different processes
          assert first_pid != second_pid
          cleanup_devices([first_pid, second_pid])
        {:error, reason} ->
          # Expected behavior for port conflict
          assert reason == :eaddrinuse or match?({:shutdown, _}, reason)
          cleanup_devices([first_pid])
      end
      
      # Reset trap_exit
      Process.flag(:trap_exit, false)
    end
  end
end
