defmodule SnmpSimEx.TestScenariosTest do
  use ExUnit.Case, async: false
  
  alias SnmpSimEx.{TestScenarios}
  alias SNMPSimEx.Device
  alias SnmpSimEx.MIB.SharedProfiles
  
  setup do
    # Start shared profiles for testing only if not already started
    case SharedProfiles.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end
    
    # Create test devices
    devices = Enum.map(1..3, fn i ->
      device_config = %{
        port: 9100 + i,
        device_type: :cable_modem,
        device_id: "test_device_#{i}",
        community: "public"
      }
      
      {:ok, device_pid} = Device.start_link(device_config)
      device_pid
    end)
    
    on_exit(fn ->
      Enum.each(devices, fn device_pid ->
        if Process.alive?(device_pid) do
          Device.stop(device_pid)
        end
      end)
    end)
    
    %{devices: devices}
  end
  
  describe "network outage scenarios" do
    test "creates network outage scenario with immediate recovery", %{devices: devices} do
      result = TestScenarios.network_outage_scenario(devices,
        duration_seconds: 10,
        recovery_type: :immediate,
        affected_percentage: 1.0
      )
      
      # Verify scenario result structure
      assert %{
        scenario_id: scenario_id,
        start_time: start_time,
        devices_affected: devices_affected,
        conditions_applied: conditions,
        estimated_duration_ms: duration_ms
      } = result
      
      assert is_binary(scenario_id)
      assert String.starts_with?(scenario_id, "network_outage_")
      assert %DateTime{} = start_time
      assert devices_affected == length(devices)
      assert is_list(conditions)
      assert duration_ms == 10_000
    end
    
    test "creates gradual recovery scenario", %{devices: devices} do
      result = TestScenarios.network_outage_scenario(devices,
        duration_seconds: 60,
        recovery_type: :gradual,
        affected_percentage: 0.8
      )
      
      assert result.devices_affected <= length(devices)
      assert result.estimated_duration_ms == 60_000
      assert String.contains?(result.scenario_id, "network_outage")
    end
    
    test "creates sporadic outage scenario", %{devices: devices} do
      result = TestScenarios.network_outage_scenario(devices,
        duration_seconds: 30,
        recovery_type: :sporadic,
        affected_percentage: 0.5
      )
      
      assert result.devices_affected <= length(devices)
      assert result.estimated_duration_ms == 30_000
    end
  end
  
  describe "signal degradation scenarios" do
    test "creates steady signal degradation", %{devices: devices} do
      result = TestScenarios.signal_degradation_scenario(devices,
        snr_degradation: 8,
        power_variation: 4,
        duration_minutes: 15,
        pattern: :steady
      )
      
      assert String.starts_with?(result.scenario_id, "signal_degradation_")
      assert result.devices_affected == length(devices)
      assert result.estimated_duration_ms == 15 * 60 * 1000
      assert is_list(result.conditions_applied)
    end
    
    test "creates fluctuating signal degradation", %{devices: devices} do
      result = TestScenarios.signal_degradation_scenario(devices,
        snr_degradation: 12,
        duration_minutes: 30,
        pattern: :fluctuating
      )
      
      assert result.estimated_duration_ms == 30 * 60 * 1000
      assert String.contains?(result.scenario_id, "signal_degradation")
    end
    
    test "creates progressive signal degradation", %{devices: devices} do
      result = TestScenarios.signal_degradation_scenario(devices,
        snr_degradation: 15,
        duration_minutes: 45,
        pattern: :progressive
      )
      
      assert result.estimated_duration_ms == 45 * 60 * 1000
    end
  end
  
  describe "high load scenarios" do
    test "creates steady high load scenario", %{devices: devices} do
      result = TestScenarios.high_load_scenario(devices,
        utilization_percent: 90,
        duration_minutes: 60,
        congestion_type: :steady,
        error_rate_multiplier: 3.0
      )
      
      assert String.starts_with?(result.scenario_id, "high_load_")
      assert result.devices_affected == length(devices)
      assert result.estimated_duration_ms == 60 * 60 * 1000
    end
    
    test "creates bursty high load scenario", %{devices: devices} do
      result = TestScenarios.high_load_scenario(devices,
        utilization_percent: 95,
        congestion_type: :bursty,
        error_rate_multiplier: 8.0
      )
      
      assert result.estimated_duration_ms == 60 * 60 * 1000  # Default duration
      assert String.contains?(result.scenario_id, "high_load")
    end
    
    test "creates cascade high load scenario", %{devices: devices} do
      result = TestScenarios.high_load_scenario(devices,
        utilization_percent: 85,
        congestion_type: :cascade
      )
      
      assert is_list(result.conditions_applied)
    end
  end
  
  describe "device flapping scenarios" do
    test "creates regular flapping pattern", %{devices: devices} do
      result = TestScenarios.device_flapping_scenario(devices,
        flap_interval_seconds: 60,
        down_duration_seconds: 15,
        total_duration_minutes: 30,
        flap_pattern: :regular
      )
      
      assert String.starts_with?(result.scenario_id, "device_flapping_")
      assert result.estimated_duration_ms == 30 * 60 * 1000
      assert result.devices_affected == length(devices)
    end
    
    test "creates irregular flapping pattern", %{devices: devices} do
      result = TestScenarios.device_flapping_scenario(devices,
        flap_pattern: :irregular,
        total_duration_minutes: 45
      )
      
      assert result.estimated_duration_ms == 45 * 60 * 1000
    end
    
    test "creates degrading flapping pattern", %{devices: devices} do
      result = TestScenarios.device_flapping_scenario(devices,
        flap_pattern: :degrading,
        flap_interval_seconds: 120,
        total_duration_minutes: 60
      )
      
      assert result.estimated_duration_ms == 60 * 60 * 1000
    end
  end
  
  describe "cascading failure scenarios" do
    test "creates cascading failure scenario", %{devices: devices} do
      result = TestScenarios.cascading_failure_scenario(devices,
        initial_failure_percentage: 0.1,
        cascade_delay_seconds: 30,
        cascade_growth_factor: 2.0,
        max_affected_percentage: 0.8
      )
      
      assert String.starts_with?(result.scenario_id, "cascading_failure_")
      assert result.devices_affected == length(devices)
      assert is_integer(result.estimated_duration_ms)
      assert result.estimated_duration_ms > 0
    end
    
    test "calculates cascade duration correctly with small device count", %{devices: devices} do
      result = TestScenarios.cascading_failure_scenario(devices,
        initial_failure_percentage: 0.5,
        cascade_delay_seconds: 60,
        cascade_growth_factor: 1.5,
        max_affected_percentage: 1.0
      )
      
      # With 3 devices, should cascade quickly
      assert result.estimated_duration_ms > 0
      assert result.estimated_duration_ms < 5 * 60 * 1000  # Less than 5 minutes
    end
  end
  
  describe "environmental scenarios" do
    test "creates weather scenario with mild severity", %{devices: devices} do
      result = TestScenarios.environmental_scenario(devices,
        condition_type: :weather,
        severity: :mild,
        duration_hours: 2,
        geographic_pattern: :random
      )
      
      assert String.starts_with?(result.scenario_id, "environmental_weather_")
      assert result.estimated_duration_ms == 2 * 60 * 60 * 1000
      assert result.devices_affected <= length(devices)
    end
    
    test "creates power scenario with severe severity", %{devices: devices} do
      result = TestScenarios.environmental_scenario(devices,
        condition_type: :power,
        severity: :severe,
        duration_hours: 1,
        geographic_pattern: :clustered
      )
      
      assert String.contains?(result.scenario_id, "environmental_power")
      assert result.estimated_duration_ms == 1 * 60 * 60 * 1000
    end
    
    test "creates temperature scenario", %{devices: devices} do
      result = TestScenarios.environmental_scenario(devices,
        condition_type: :temperature,
        severity: :moderate,
        duration_hours: 3,
        geographic_pattern: :linear
      )
      
      assert String.contains?(result.scenario_id, "environmental_temperature")
      assert result.estimated_duration_ms == 3 * 60 * 60 * 1000
    end
    
    test "creates interference scenario", %{devices: devices} do
      result = TestScenarios.environmental_scenario(devices,
        condition_type: :interference,
        severity: :moderate,
        duration_hours: 4
      )
      
      assert String.contains?(result.scenario_id, "environmental_interference")
      assert result.estimated_duration_ms == 4 * 60 * 60 * 1000
    end
  end
  
  describe "multi-scenario tests" do
    test "creates multiple concurrent scenarios", %{devices: devices} do
      scenarios = [
        {:signal_degradation, [snr_degradation: 8, duration_minutes: 60]},
        {:high_load, [utilization_percent: 90, duration_minutes: 45]},
        {:device_flapping, [flap_interval_seconds: 120, total_duration_minutes: 30]}
      ]
      
      results = TestScenarios.multi_scenario_test(devices, scenarios)
      
      assert is_list(results)
      assert length(results) == 3
      
      # Verify each result has proper structure
      Enum.each(results, fn result ->
        assert %{
          scenario_id: scenario_id,
          start_time: start_time,
          devices_affected: devices_affected,
          conditions_applied: conditions,
          estimated_duration_ms: duration_ms
        } = result
        
        assert is_binary(scenario_id)
        assert String.starts_with?(scenario_id, "multi_scenario_")
        assert %DateTime{} = start_time
        assert devices_affected == length(devices)
        assert is_list(conditions)
        assert is_integer(duration_ms)
      end)
    end
    
    test "handles empty scenario list", %{devices: devices} do
      results = TestScenarios.multi_scenario_test(devices, [])
      assert results == []
    end
    
    test "stagger scenario start times", %{devices: devices} do
      scenarios = [
        {:signal_degradation, [duration_minutes: 30]},
        {:high_load, [duration_minutes: 45]}
      ]
      
      results = TestScenarios.multi_scenario_test(devices, scenarios)
      
      # Verify that start times are staggered
      [first_result, second_result] = results
      time_diff = DateTime.diff(second_result.start_time, first_result.start_time, :millisecond)
      
      # Should be approximately 30 seconds apart (30,000 ms)
      assert time_diff >= 29_000 and time_diff <= 31_000
    end
  end
  
  describe "scenario ID generation" do
    test "generates unique scenario IDs", %{devices: devices} do
      # Generate multiple scenarios of the same type
      results = Enum.map(1..5, fn _ ->
        TestScenarios.network_outage_scenario(devices, duration_seconds: 10)
      end)
      
      scenario_ids = Enum.map(results, & &1.scenario_id)
      
      # All IDs should be unique
      assert length(Enum.uniq(scenario_ids)) == 5
      
      # All should start with the scenario type
      Enum.each(scenario_ids, fn id ->
        assert String.starts_with?(id, "network_outage_")
      end)
    end
  end
  
  describe "scenario validation" do
    test "handles empty device list gracefully" do
      result = TestScenarios.network_outage_scenario([],
        duration_seconds: 60
      )
      
      assert result.devices_affected == 0
      assert is_list(result.conditions_applied)
    end
    
    test "validates percentage parameters" do
      devices = [self()]  # Use current process as a mock device
      
      result = TestScenarios.network_outage_scenario(devices,
        affected_percentage: 1.5  # Over 100%
      )
      
      # Should handle gracefully
      assert result.devices_affected <= length(devices)
    end
    
    test "handles zero duration scenarios" do
      devices = [self()]
      
      result = TestScenarios.signal_degradation_scenario(devices,
        duration_minutes: 0
      )
      
      assert result.estimated_duration_ms == 0
    end
  end
end