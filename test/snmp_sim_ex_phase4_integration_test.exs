defmodule SNMPSimExPhase4IntegrationTest do
  use ExUnit.Case, async: false
  
  alias SNMPSimEx.{LazyDevicePool, DeviceDistribution, MultiDeviceStartup, Device}
  
  @moduletag :integration
  
  setup_all do
    # Start the application if not already started
    Application.ensure_all_started(:snmp_sim_ex)
    :ok
  end
  
  setup do
    # Ensure clean state for each test
    if Process.whereis(LazyDevicePool) do
      LazyDevicePool.shutdown_all_devices()
    else
      {:ok, _} = LazyDevicePool.start_link()
    end
    
    :ok
  end
  
  describe "Phase 4: End-to-End Integration" do
    test "complete lazy device pool lifecycle" do
      # Configure custom port assignments
      port_assignments = %{
        cable_modem: 40_000..40_099,
        switch: 40_100..40_149
      }
      
      assert :ok = LazyDevicePool.configure_port_assignments(port_assignments)
      
      # Create devices on demand
      cable_modem_port = 40_050
      switch_port = 40_125
      
      # First access should create devices
      assert {:ok, cm_pid} = LazyDevicePool.get_or_create_device(cable_modem_port)
      assert {:ok, sw_pid} = LazyDevicePool.get_or_create_device(switch_port)
      
      assert Process.alive?(cm_pid)
      assert Process.alive?(sw_pid)
      assert cm_pid != sw_pid
      
      # Verify device information
      {:ok, cm_info} = Device.get_info(cm_pid)
      {:ok, sw_info} = Device.get_info(sw_pid)
      
      assert cm_info.device_type == :cable_modem
      assert cm_info.port == cable_modem_port
      assert sw_info.device_type == :switch
      assert sw_info.port == switch_port
      
      # Second access should reuse devices
      assert {:ok, ^cm_pid} = LazyDevicePool.get_or_create_device(cable_modem_port)
      assert {:ok, ^sw_pid} = LazyDevicePool.get_or_create_device(switch_port)
      
      # Verify pool statistics
      stats = LazyDevicePool.get_stats()
      assert stats.active_count == 2
      assert stats.devices_created == 2
      assert stats.peak_count == 2
      
      # Cleanup specific device
      assert :ok = LazyDevicePool.shutdown_device(cable_modem_port)
      refute Process.alive?(cm_pid)
      assert Process.alive?(sw_pid)
      
      # Cleanup all devices
      assert :ok = LazyDevicePool.shutdown_all_devices()
      refute Process.alive?(sw_pid)
      
      final_stats = LazyDevicePool.get_stats()
      assert final_stats.active_count == 0
    end
    
    test "device distribution patterns work correctly" do
      # Test different device mixes
      cable_mix = DeviceDistribution.get_device_mix(:cable_network)
      enterprise_mix = DeviceDistribution.get_device_mix(:enterprise_network)
      
      # Cable network should be cable-modem heavy
      assert cable_mix.cable_modem > cable_mix.mta
      assert cable_mix.cable_modem > cable_mix.cmts
      
      # Enterprise should be switch heavy
      assert enterprise_mix.switch > enterprise_mix.router
      
      # Build port assignments
      port_range = 41_000..42_000
      cable_assignments = DeviceDistribution.build_port_assignments(cable_mix, port_range)
      
      # Validate assignments
      assert :ok = DeviceDistribution.validate_port_assignments(cable_assignments)
      
      # Calculate density statistics
      density_stats = DeviceDistribution.calculate_density_stats(cable_assignments)
      assert density_stats.total_devices == Enum.sum(Map.values(cable_mix))
      assert density_stats.largest_group.type == :cable_modem
      
      # Test device type determination
      cable_modem_port = Enum.at(cable_assignments.cable_modem, 10)
      mta_port = Enum.at(cable_assignments.mta, 5)
      
      assert DeviceDistribution.determine_device_type(cable_modem_port, cable_assignments) == :cable_modem
      assert DeviceDistribution.determine_device_type(mta_port, cable_assignments) == :mta
    end
    
    test "multi-device startup scales properly" do
      # Start small population
      device_specs = [
        {:cable_modem, 10},
        {:switch, 5},
        {:router, 2}
      ]
      
      result = MultiDeviceStartup.start_device_population(
        device_specs,
        port_range: 43_000..43_100,
        parallel_workers: 5
      )
      
      assert {:ok, startup_result} = result
      assert startup_result.total_devices == 17
      
      # Verify all devices are created
      pool_stats = LazyDevicePool.get_stats()
      assert pool_stats.devices_created >= 17
      assert pool_stats.active_count >= 17
      
      # Test device access patterns
      cable_ports = 43_000..43_009 |> Enum.to_list()
      switch_ports = 43_010..43_014 |> Enum.to_list()
      
      # Access cable modems
      cable_pids = Enum.map(cable_ports, fn port ->
        {:ok, pid} = LazyDevicePool.get_or_create_device(port)
        pid
      end)
      
      # Access switches  
      switch_pids = Enum.map(switch_ports, fn port ->
        {:ok, pid} = LazyDevicePool.get_or_create_device(port)
        pid
      end)
      
      # Verify all are alive and different
      Enum.each(cable_pids ++ switch_pids, fn pid ->
        assert Process.alive?(pid)
      end)
      
      unique_pids = Enum.uniq(cable_pids ++ switch_pids)
      assert length(unique_pids) == length(cable_pids) + length(switch_pids)
      
      # Shutdown population
      assert :ok = MultiDeviceStartup.shutdown_device_population()
      
      # Verify all devices are gone
      final_stats = LazyDevicePool.get_stats()
      assert final_stats.active_count == 0
    end
    
    test "device characteristics affect behavior" do
      # Create different device types
      cable_modem_port = 30_050
      switch_port = 39_550
      cmts_port = 39_960
      
      assert {:ok, cm_pid} = LazyDevicePool.get_or_create_device(cable_modem_port)
      assert {:ok, sw_pid} = LazyDevicePool.get_or_create_device(switch_port)
      assert {:ok, cmts_pid} = LazyDevicePool.get_or_create_device(cmts_port)
      
      # Get device information
      {:ok, cm_info} = Device.get_info(cm_pid)
      {:ok, sw_info} = Device.get_info(sw_pid)
      {:ok, cmts_info} = Device.get_info(cmts_pid)
      
      # Verify correct device types
      assert cm_info.device_type == :cable_modem
      assert sw_info.device_type == :switch
      assert cmts_info.device_type == :cmts
      
      # Get characteristics
      cm_chars = DeviceDistribution.get_device_characteristics(:cable_modem)
      sw_chars = DeviceDistribution.get_device_characteristics(:switch)
      cmts_chars = DeviceDistribution.get_device_characteristics(:cmts)
      
      # Verify realistic characteristics
      assert cm_chars.signal_monitoring == true
      assert sw_chars.signal_monitoring == false
      assert cmts_chars.signal_monitoring == true
      
      # Switches should have more interfaces
      assert sw_chars.typical_interfaces > cm_chars.typical_interfaces
      assert cmts_chars.typical_interfaces > cm_chars.typical_interfaces
      
      # CMTS should have highest uptime expectations
      assert cmts_chars.expected_uptime_days >= sw_chars.expected_uptime_days
      assert cmts_chars.expected_uptime_days >= cm_chars.expected_uptime_days
    end
    
    test "concurrent device access patterns" do
      # Configure for high concurrency
      port_range = 44_000..44_999
      port_assignments = %{
        cable_modem: port_range
      }
      
      LazyDevicePool.configure_port_assignments(port_assignments)
      
      # Create many concurrent access tasks
      ports = Enum.take(port_range, 100)
      
      # Access devices concurrently
      tasks = Enum.map(ports, fn port ->
        Task.async(fn ->
          case LazyDevicePool.get_or_create_device(port) do
            {:ok, pid} -> 
              # Simulate some device usage
              Device.get_info(pid)
              {:ok, pid}
            {:error, reason} -> 
              {:error, {port, reason}}
          end
        end)
      end)
      
      # Wait for all tasks with reasonable timeout
      results = Enum.map(tasks, fn task ->
        Task.await(task, 10_000)
      end)
      
      # Count successes
      successes = Enum.count(results, &match?({:ok, _}, &1))
      failures = Enum.count(results, &match?({:error, _}, &1))
      
      # Should have high success rate
      success_rate = successes / length(results)
      assert success_rate > 0.9, "Success rate: #{success_rate}, Failures: #{failures}"
      
      # Verify reasonable number of devices created
      pool_stats = LazyDevicePool.get_stats()
      assert pool_stats.devices_created >= successes
      assert pool_stats.active_count >= successes * 0.9  # Allow for some cleanup
    end
    
    test "device cleanup and idle management" do
      # Configure short idle timeout for testing
      LazyDevicePool.shutdown_all_devices()
      {:ok, _} = LazyDevicePool.start_link(idle_timeout_ms: 500, max_devices: 10)
      
      # Create devices
      ports = [45_001, 45_002, 45_003]
      device_pids = Enum.map(ports, fn port ->
        {:ok, pid} = LazyDevicePool.get_or_create_device(port)
        pid
      end)
      
      # Verify all alive
      Enum.each(device_pids, fn pid ->
        assert Process.alive?(pid)
      end)
      
      # Wait for idle timeout
      :timer.sleep(600)
      
      # Force cleanup
      LazyDevicePool.cleanup_idle_devices()
      
      # Wait for cleanup to complete
      :timer.sleep(100)
      
      # Devices should be cleaned up
      pool_stats = LazyDevicePool.get_stats()
      assert pool_stats.devices_cleaned_up >= 3
      assert pool_stats.active_count == 0
      
      # Device processes should be dead
      Enum.each(device_pids, fn pid ->
        refute Process.alive?(pid)
      end)
      
      # Access again should create new devices
      {:ok, new_pid} = LazyDevicePool.get_or_create_device(45_001)
      assert Process.alive?(new_pid)
      assert new_pid not in device_pids
    end
    
    test "predefined device mix startup patterns" do
      # Test different startup patterns
      test_configs = [
        {:small_test, 46_000..46_100},
        {:medium_test, 47_000..47_500}
      ]
      
      Enum.each(test_configs, fn {mix_type, port_range} ->
        # Clean state
        MultiDeviceStartup.shutdown_device_population()
        
        # Start device mix
        result = MultiDeviceStartup.start_device_mix(mix_type, port_range: port_range)
        assert {:ok, startup_result} = result
        
        # Verify reasonable device count
        device_mix = DeviceDistribution.get_device_mix(mix_type)
        expected_total = Enum.sum(Map.values(device_mix))
        assert startup_result.total_devices == expected_total
        
        # Verify devices are accessible
        status = MultiDeviceStartup.get_startup_status()
        assert status.active_devices >= expected_total * 0.8  # Allow some tolerance
        
        # Sample some devices to verify they work
        sample_ports = Enum.take(port_range, min(5, expected_total))
        Enum.each(sample_ports, fn port ->
          case LazyDevicePool.get_or_create_device(port) do
            {:ok, pid} ->
              assert Process.alive?(pid)
              {:ok, info} = Device.get_info(pid)
              assert info.port == port
            {:error, :unknown_port_range} ->
              # Some ports might not be assigned
              :ok
          end
        end)
      end)
    end
  end
  
  describe "Phase 4: Performance and Scale Testing" do
    @tag :slow
    test "handles medium scale device population" do
      # Test with moderate scale (adjust based on system capabilities)
      device_specs = [
        {:cable_modem, 100},
        {:switch, 20},
        {:router, 5}
      ]
      
      port_range = 50_000..50_500
      
      # Measure startup time
      {time_us, result} = :timer.tc(fn ->
        MultiDeviceStartup.start_device_population(
          device_specs,
          port_range: port_range,
          parallel_workers: 20
        )
      end)
      
      assert {:ok, startup_result} = result
      assert startup_result.total_devices == 125
      
      startup_time_ms = div(time_us, 1000)
      IO.puts("Startup time for 125 devices: #{startup_time_ms}ms")
      
      # Should complete in reasonable time (adjust threshold as needed)
      assert startup_time_ms < 30_000, "Startup took too long: #{startup_time_ms}ms"
      
      # Verify all devices are accessible
      pool_stats = LazyDevicePool.get_stats()
      assert pool_stats.devices_created >= 125
      
      # Sample device access performance
      sample_ports = Enum.take(port_range, 20)
      
      {access_time_us, _} = :timer.tc(fn ->
        Enum.each(sample_ports, fn port ->
          {:ok, _} = LazyDevicePool.get_or_create_device(port)
        end)
      end)
      
      avg_access_time_ms = div(access_time_us, 1000) / 20
      IO.puts("Average device access time: #{avg_access_time_ms}ms")
      
      # Device access should be fast (already created)
      assert avg_access_time_ms < 10, "Device access too slow: #{avg_access_time_ms}ms"
    end
    
    @tag :slow
    test "memory usage remains reasonable" do
      # Start moderate device population
      device_specs = [
        {:cable_modem, 50}
      ]
      
      # Measure memory before
      memory_before = :erlang.memory(:total)
      
      {:ok, _} = MultiDeviceStartup.start_device_population(
        device_specs,
        port_range: 51_000..51_100
      )
      
      # Measure memory after
      memory_after = :erlang.memory(:total)
      memory_diff_mb = (memory_after - memory_before) / (1024 * 1024)
      
      IO.puts("Memory usage for 50 devices: #{Float.round(memory_diff_mb, 2)}MB")
      
      # Should use reasonable memory per device (adjust threshold as needed)
      memory_per_device_kb = (memory_after - memory_before) / 50 / 1024
      assert memory_per_device_kb < 1024, "Too much memory per device: #{memory_per_device_kb}KB"
    end
  end
  
  describe "Phase 4: Error Scenarios and Recovery" do
    test "recovers from device process failures" do
      port = 52_001
      
      # Create device
      {:ok, original_pid} = LazyDevicePool.get_or_create_device(port)
      assert Process.alive?(original_pid)
      
      # Kill the device process
      Process.exit(original_pid, :kill)
      :timer.sleep(100)  # Allow cleanup
      
      # Access again should create new device
      {:ok, new_pid} = LazyDevicePool.get_or_create_device(port)
      assert Process.alive?(new_pid)
      assert new_pid != original_pid
      
      # New device should work normally
      {:ok, info} = Device.get_info(new_pid)
      assert info.port == port
    end
    
    test "handles rapid device creation and destruction" do
      ports = 53_000..53_020 |> Enum.to_list()
      
      # Rapid creation
      device_pids = Enum.map(ports, fn port ->
        {:ok, pid} = LazyDevicePool.get_or_create_device(port)
        pid
      end)
      
      # Verify all created
      assert length(device_pids) == length(ports)
      
      # Rapid destruction
      Enum.each(ports, fn port ->
        LazyDevicePool.shutdown_device(port)
      end)
      
      # Verify all gone
      :timer.sleep(100)
      pool_stats = LazyDevicePool.get_stats()
      assert pool_stats.active_count == 0
      
      # Should be able to create again
      {:ok, new_pid} = LazyDevicePool.get_or_create_device(Enum.at(ports, 0))
      assert Process.alive?(new_pid)
      assert new_pid not in device_pids
    end
  end
end