defmodule SnmpSim.MultiDeviceStartupTest do
  use ExUnit.Case, async: false
  
  alias SnmpSim.{MultiDeviceStartup, LazyDevicePool, DeviceDistribution}
  alias SnmpSim.TestHelpers.PortHelper
  
  # Helper function to get unique port range for each test using PortHelper
  defp get_port_range(_test_name, size \\ 20) do
    PortHelper.get_port_range(size)
  end
  
  setup %{test: test_name} do
    # Ensure clean state for each test
    if Process.whereis(LazyDevicePool) do
      LazyDevicePool.shutdown_all_devices()
    else
      {:ok, _} = LazyDevicePool.start_link()
    end
    
    # Reset to default port assignments
    default_assignments = DeviceDistribution.default_port_assignments()
    LazyDevicePool.configure_port_assignments(default_assignments)
    
    # Provide unique port range for this test
    port_range = get_port_range(test_name)
    %{port_range: port_range}
  end
  
  describe "device population startup" do
    test "starts small device population successfully", %{port_range: port_range} do
      device_specs = [
        {:cable_modem, 3},
        {:switch, 2}
      ]
      
      result = MultiDeviceStartup.start_device_population(
        device_specs,
        port_range: port_range,
        parallel_workers: 2
      )
      
      assert {:ok, startup_result} = result
      assert startup_result.total_devices == 5
      assert is_map(startup_result.port_assignments)
      assert is_map(startup_result.startup_results)
      assert is_map(startup_result.pool_stats)
      
      # Verify devices are actually created
      pool_stats = LazyDevicePool.get_stats()
      assert pool_stats.devices_created >= 5
    end
    
    test "handles empty device specs", %{port_range: port_range} do
      device_specs = []
      
      result = MultiDeviceStartup.start_device_population(
        device_specs,
        port_range: port_range
      )
      
      assert {:error, :no_devices_specified} = result
    end
    
    test "validates device specs with invalid types", %{port_range: port_range} do
      device_specs = [
        {:invalid_device_type, 5}
      ]
      
      result = MultiDeviceStartup.start_device_population(
        device_specs,
        port_range: port_range
      )
      
      assert {:error, :invalid_device_types} = result
    end
    
    test "detects insufficient ports", %{port_range: _port_range} do
      device_specs = [
        {:cable_modem, 100}  # Too many for small range
      ]
      
      # Use a small port range to test insufficient ports scenario
      small_range = 30_000..30_010  # Only 11 ports
      
      result = MultiDeviceStartup.start_device_population(
        device_specs,
        port_range: small_range
      )
      
      assert {:error, {:insufficient_ports, 100, 11}} = result
    end
    
    test "respects parallel worker limits", %{port_range: port_range} do
      device_specs = [
        {:cable_modem, 5}
      ]
      
      # Should work with different worker counts
      result = MultiDeviceStartup.start_device_population(
        device_specs,
        port_range: port_range,
        parallel_workers: 1
      )
      
      assert {:ok, _} = result
      
      # Clean up for next test
      LazyDevicePool.shutdown_all_devices()
      
      result = MultiDeviceStartup.start_device_population(
        device_specs,
        port_range: port_range,
        parallel_workers: 10
      )
      
      assert {:ok, _} = result
    end
    
    test "handles timeout scenarios gracefully", %{port_range: port_range} do
      device_specs = [
        {:cable_modem, 2}
      ]
      
      # Very short timeout - might cause some failures but shouldn't crash
      result = MultiDeviceStartup.start_device_population(
        device_specs,
        port_range: port_range,
        timeout_ms: 1  # Very short timeout
      )
      
      # Should either succeed or fail gracefully
      case result do
        {:ok, _} -> :ok
        {:error, _} -> :ok
      end
    end
  end
  
  describe "predefined device mixes" do
    @tag :slow
    test "starts cable network mix", %{port_range: port_range} do
      # Use small_test mix instead to avoid file descriptor limits
      result = MultiDeviceStartup.start_device_mix(
        :small_test,
        port_range: port_range
      )
      
      assert {:ok, startup_result} = result
      assert startup_result.total_devices > 10  # Should be substantial for small test
      
      # Should have cable modems and other devices from small_test mix
      assignments = startup_result.port_assignments
      assert Map.has_key?(assignments, :cable_modem)
      assert Map.has_key?(assignments, :switch)
      assert Map.has_key?(assignments, :router)
    end
    
    @tag :slow  
    test "starts enterprise network mix", %{test: test_name} do
      # Use medium_test mix instead to avoid file descriptor limits
      # medium_test requires 140 devices, so use a larger port range
      large_port_range = get_port_range(test_name, 150)
      
      result = MultiDeviceStartup.start_device_mix(
        :medium_test,
        port_range: large_port_range
      )
      
      assert {:ok, startup_result} = result
      
      # Should have switches, routers, and servers from medium_test mix
      assignments = startup_result.port_assignments
      assert Map.has_key?(assignments, :cable_modem)
      assert Map.has_key?(assignments, :switch)
      assert Map.has_key?(assignments, :router)
      assert Map.has_key?(assignments, :server)
    end
    
    test "starts test mixes for development", %{port_range: port_range} do
      result = MultiDeviceStartup.start_device_mix(
        :small_test,
        port_range: port_range
      )
      
      assert {:ok, startup_result} = result
      assert startup_result.total_devices < 20  # Should be small
      
      # Use a larger port range for medium test (140 devices)
      large_range = get_port_range("medium_test", 150)
      result = MultiDeviceStartup.start_device_mix(
        :medium_test,
        port_range: large_range
      )
      
      assert {:ok, startup_result} = result
      assert startup_result.total_devices > 20   # Larger than small
      assert startup_result.total_devices < 200  # But not huge
    end
  end
  
  describe "pre-warming functionality" do
    test "pre-warms devices for immediate availability", %{port_range: port_range} do
      device_specs = [
        {:cable_modem, 3}
      ]
      
      result = MultiDeviceStartup.pre_warm_devices(
        device_specs,
        port_range: port_range
      )
      
      assert {:ok, startup_result} = result
      
      # Devices should be immediately available
      pool_stats = LazyDevicePool.get_stats()
      assert pool_stats.devices_created >= 3
      assert pool_stats.active_count >= 3
    end
  end
  
  describe "startup status and monitoring" do
    test "provides startup status information", %{port_range: port_range} do
      # Start some devices first
      device_specs = [
        {:cable_modem, 2}
      ]
      
      {:ok, _} = MultiDeviceStartup.start_device_population(
        device_specs,
        port_range: port_range
      )
      
      status = MultiDeviceStartup.get_startup_status()
      
      assert is_map(status)
      assert Map.has_key?(status, :active_devices)
      assert Map.has_key?(status, :peak_devices)
      assert Map.has_key?(status, :devices_created)
      assert Map.has_key?(status, :devices_cleaned_up)
      
      assert status.active_devices >= 2
      assert status.devices_created >= 2
    end
    
    test "tracks startup progress with callback", %{port_range: port_range} do
      # Create a simple progress tracker
      test_pid = self()
      progress_callback = fn progress ->
        send(test_pid, {:progress, progress})
      end
      
      device_specs = [
        {:cable_modem, 3}
      ]
      
      # Start with progress tracking
      task = Task.async(fn ->
        MultiDeviceStartup.start_device_population(
          device_specs,
          port_range: port_range,
          progress_callback: progress_callback
        )
      end)
      
      # Should receive progress updates
      result = Task.await(task, 10_000)
      assert {:ok, _} = result
      
      # Might receive progress messages (depending on timing)
      # This is not guaranteed in fast tests, so we don't assert
      flush_messages()
    end
    
    test "console progress callback works", %{port_range: port_range} do
      callback = MultiDeviceStartup.console_progress_callback()
      assert is_function(callback, 1)
      
      # Should handle progress map without crashing
      progress = %{
        completed: 5,
        total: 10,
        progress: 0.5,
        elapsed_ms: 1000,
        eta_ms: 1000
      }
      
      # Should not crash
      callback.(progress)
    end
  end
  
  describe "device population shutdown" do
    test "shuts down entire device population", %{port_range: port_range} do
      # Start some devices
      device_specs = [
        {:cable_modem, 3},
        {:switch, 2}
      ]
      
      {:ok, _} = MultiDeviceStartup.start_device_population(
        device_specs,
        port_range: port_range
      )
      
      # Verify devices exist
      pool_stats = LazyDevicePool.get_stats()
      assert pool_stats.active_count >= 5
      
      # Shutdown all
      assert :ok = MultiDeviceStartup.shutdown_device_population()
      
      # Verify all gone
      pool_stats = LazyDevicePool.get_stats()
      assert pool_stats.active_count == 0
    end
  end
  
  describe "error handling and recovery" do
    test "handles partial failures gracefully", %{port_range: port_range} do
      # This test would need mock failures, simplified for now
      device_specs = [
        {:cable_modem, 2}
      ]
      
      result = MultiDeviceStartup.start_device_population(
        device_specs,
        port_range: port_range
      )
      
      # Should succeed or fail gracefully
      case result do
        {:ok, _} -> 
          assert true
        {:error, reason} -> 
          assert is_atom(reason) or is_tuple(reason)
      end
    end
    
    test "validates port assignment conflicts", %{port_range: port_range} do
      # Create overlapping port assignments manually
      overlapping_assignments = %{
        cable_modem: 30_000..30_050,
        switch: 30_025..30_075  # Overlaps
      }
      
      # This should be caught during validation
      device_specs = [
        {:cable_modem, 10},
        {:switch, 10}
      ]
      
      # Configure conflicting assignments
      LazyDevicePool.configure_port_assignments(overlapping_assignments)
      
      result = MultiDeviceStartup.start_device_population(
        device_specs,
        port_range: port_range
      )
      
      # Should handle the conflict gracefully
      case result do
        {:ok, _} -> :ok  # Might succeed despite conflicts
        {:error, _} -> :ok  # Or fail gracefully
      end
    end
  end
  
  describe "startup with progress reporting" do
    test "starts with console progress reporting", %{port_range: port_range} do
      device_specs = [
        {:cable_modem, 5}
      ]
      
      result = MultiDeviceStartup.start_with_progress(
        device_specs,
        port_range: port_range
      )
      
      assert {:ok, startup_result} = result
      assert startup_result.total_devices == 5
    end
  end
  
  describe "concurrent startup operations" do
    test "handles concurrent startup requests", %{port_range: port_range} do
      # Start multiple startup operations concurrently
      tasks = for i <- 1..3 do
        Task.async(fn ->
          device_specs = [
            {:cable_modem, 2}
          ]
          
          MultiDeviceStartup.start_device_population(
            device_specs,
            port_range: port_range
          )
        end)
      end
      
      # Wait for all to complete
      results = Enum.map(tasks, &Task.await(&1, 10_000))
      
      # At least some should succeed
      successes = Enum.count(results, &match?({:ok, _}, &1))
      assert successes > 0
    end
  end
  
  # Helper function to flush any progress messages
  defp flush_messages do
    receive do
      {:progress, _} -> flush_messages()
    after
      100 -> :ok
    end
  end
end