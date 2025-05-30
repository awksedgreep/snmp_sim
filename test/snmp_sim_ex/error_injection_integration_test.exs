defmodule SnmpSimEx.ErrorInjectionIntegrationTest do
  use ExUnit.Case, async: false
  
  alias SnmpSimEx.{ErrorInjector, TestScenarios}
  alias SNMPSimEx.Device
  alias SnmpSimEx.MIB.SharedProfiles
  
  setup do
    # Start shared profiles for testing only if not already started
    case SharedProfiles.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end
    
    # Create a test device
    device_config = %{
      port: 9200 + :rand.uniform(100),
      device_type: :cable_modem,
      device_id: "integration_test_device_#{:rand.uniform(10000)}",
      community: "public"
    }
    
    {:ok, device_pid} = Device.start_link(device_config)
    
    on_exit(fn ->
      if Process.alive?(device_pid) do
        Device.stop(device_pid)
      end
    end)
    
    %{device_pid: device_pid, device_config: device_config}
  end
  
  describe "Error injection integration" do
    test "ErrorInjector can communicate with Device", %{device_pid: device_pid, device_config: config} do
      # Start error injector
      {:ok, injector_pid} = ErrorInjector.start_link(device_pid, config.port)
      
      # Verify both processes are running
      assert Process.alive?(device_pid)
      assert Process.alive?(injector_pid)
      
      # Get device info before error injection
      device_info = Device.get_info(device_pid)
      assert device_info.device_id == config.device_id
      
      # Inject timeout error
      :ok = ErrorInjector.inject_timeout(injector_pid, 
        probability: 0.1,
        duration_ms: 100
      )
      
      # Verify error injection was recorded
      stats = ErrorInjector.get_error_statistics(injector_pid)
      assert stats.total_injections == 1
      assert stats.injections_by_type.timeout == 1
      
      # Clean up
      GenServer.stop(injector_pid)
    end
    
    test "Device processes error injection messages", %{device_pid: device_pid, device_config: config} do
      {:ok, injector_pid} = ErrorInjector.start_link(device_pid, config.port)
      
      # Inject packet loss
      :ok = ErrorInjector.inject_packet_loss(injector_pid,
        loss_rate: 0.05,
        burst_loss: false
      )
      
      # Give the device time to process the message
      Process.sleep(10)
      
      # Verify injection was recorded
      stats = ErrorInjector.get_error_statistics(injector_pid)
      assert stats.injections_by_type.packet_loss == 1
      
      # Test removing error condition
      :ok = ErrorInjector.remove_error_condition(injector_pid, :packet_loss)
      
      GenServer.stop(injector_pid)
    end
    
    test "Device failure simulation", %{device_pid: device_pid, device_config: config} do
      {:ok, injector_pid} = ErrorInjector.start_link(device_pid, config.port)
      
      # Simulate device reboot with short duration for testing
      :ok = ErrorInjector.simulate_device_failure(injector_pid, :reboot,
        duration_ms: 100,
        recovery_behavior: :normal
      )
      
      # Give time for the failure and recovery to process
      Process.sleep(150)
      
      # Verify device is still running (should have recovered)
      assert Process.alive?(device_pid)
      
      # Verify device failure was recorded
      stats = ErrorInjector.get_error_statistics(injector_pid)
      assert stats.device_failures == 1
      
      GenServer.stop(injector_pid)
    end
    
    test "SNMP error injection", %{device_pid: device_pid, device_config: config} do
      {:ok, injector_pid} = ErrorInjector.start_link(device_pid, config.port)
      
      # Inject SNMP errors
      :ok = ErrorInjector.inject_snmp_error(injector_pid, :genErr,
        probability: 0.2,
        target_oids: ["1.3.6.1.2.1.1.1.0"]
      )
      
      # Verify injection was recorded
      stats = ErrorInjector.get_error_statistics(injector_pid)
      assert stats.injections_by_type.snmp_error == 1
      
      GenServer.stop(injector_pid)
    end
  end
  
  describe "Test scenario integration" do
    test "Network outage scenario affects device", %{device_pid: device_pid} do
      devices = [device_pid]
      
      # Apply network outage scenario with very short duration
      result = TestScenarios.network_outage_scenario(devices,
        duration_seconds: 1,
        recovery_type: :immediate,
        affected_percentage: 1.0
      )
      
      # Verify scenario was applied
      assert result.devices_affected == 1
      assert result.estimated_duration_ms == 1000
      assert String.starts_with?(result.scenario_id, "network_outage_")
      assert is_list(result.conditions_applied)
      
      # Give time for scenario to process
      Process.sleep(50)
      
      # Device should still be running
      assert Process.alive?(device_pid)
    end
    
    test "Signal degradation scenario", %{device_pid: device_pid} do
      devices = [device_pid]
      
      # Apply signal degradation scenario
      result = TestScenarios.signal_degradation_scenario(devices,
        snr_degradation: 5,
        duration_minutes: 1,
        pattern: :steady
      )
      
      # Verify scenario was applied  
      assert result.devices_affected == 1
      assert result.estimated_duration_ms == 60 * 1000
      assert String.contains?(result.scenario_id, "signal_degradation")
      
      # Give time for scenario to start
      Process.sleep(50)
      
      # Device should still be running
      assert Process.alive?(device_pid)
    end
    
    test "Multi-scenario test", %{device_pid: device_pid} do
      devices = [device_pid]
      
      scenarios = [
        {:signal_degradation, [snr_degradation: 3, duration_minutes: 1]},
        {:high_load, [utilization_percent: 80, duration_minutes: 1]}
      ]
      
      results = TestScenarios.multi_scenario_test(devices, scenarios)
      
      # Verify multiple scenarios were created
      assert length(results) == 2
      
      # Check each result
      Enum.each(results, fn result ->
        assert result.devices_affected == 1
        assert String.starts_with?(result.scenario_id, "multi_scenario_")
        assert is_list(result.conditions_applied)
      end)
      
      # Give time for scenarios to start
      Process.sleep(100)
      
      # Device should still be running
      assert Process.alive?(device_pid)
    end
  end
  
  describe "Error injection persistence" do
    test "Clear all errors removes all conditions", %{device_pid: device_pid, device_config: config} do
      {:ok, injector_pid} = ErrorInjector.start_link(device_pid, config.port)
      
      # Inject multiple error types
      :ok = ErrorInjector.inject_timeout(injector_pid, probability: 0.1)
      :ok = ErrorInjector.inject_packet_loss(injector_pid, loss_rate: 0.05)
      :ok = ErrorInjector.inject_snmp_error(injector_pid, :genErr, probability: 0.1)
      
      # Verify all injections were recorded
      stats = ErrorInjector.get_error_statistics(injector_pid)
      assert stats.total_injections == 3
      
      # Clear all errors
      :ok = ErrorInjector.clear_all_errors(injector_pid)
      
      # Give time for clear to process
      Process.sleep(10)
      
      # Device should still be running
      assert Process.alive?(device_pid)
      
      GenServer.stop(injector_pid)
    end
    
    test "Statistics tracking works correctly", %{device_pid: device_pid, device_config: config} do
      {:ok, injector_pid} = ErrorInjector.start_link(device_pid, config.port)
      
      # Get initial statistics
      initial_stats = ErrorInjector.get_error_statistics(injector_pid)
      assert initial_stats.total_injections == 0
      assert initial_stats.burst_events == 0
      assert initial_stats.device_failures == 0
      
      # Inject errors of different types
      :ok = ErrorInjector.inject_timeout(injector_pid, probability: 0.1)
      :ok = ErrorInjector.inject_packet_loss(injector_pid, loss_rate: 0.05)
      :ok = ErrorInjector.inject_malformed_response(injector_pid, :truncated, probability: 0.1)
      
      # Check updated statistics
      updated_stats = ErrorInjector.get_error_statistics(injector_pid)
      assert updated_stats.total_injections == 3
      assert updated_stats.injections_by_type.timeout == 1
      assert updated_stats.injections_by_type.packet_loss == 1
      assert updated_stats.injections_by_type.malformed == 1
      
      GenServer.stop(injector_pid)
    end
  end
  
  describe "Scenario validation" do
    test "Scenario with empty device list", %{} do
      # Test with empty device list
      result = TestScenarios.network_outage_scenario([],
        duration_seconds: 30
      )
      
      assert result.devices_affected == 0
      assert result.estimated_duration_ms == 30_000
      assert is_list(result.conditions_applied)
    end
    
    test "Scenario ID generation is unique", %{device_pid: device_pid} do
      devices = [device_pid]
      
      # Generate multiple scenarios
      results = Enum.map(1..3, fn _ ->
        TestScenarios.network_outage_scenario(devices, duration_seconds: 10)
      end)
      
      scenario_ids = Enum.map(results, & &1.scenario_id)
      
      # All IDs should be unique
      assert length(Enum.uniq(scenario_ids)) == 3
      
      # All should start with the correct prefix
      Enum.each(scenario_ids, fn id ->
        assert String.starts_with?(id, "network_outage_")
      end)
    end
  end
end