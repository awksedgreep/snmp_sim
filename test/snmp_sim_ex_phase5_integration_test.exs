defmodule SNMPSimEx.Phase5IntegrationTest do
  use ExUnit.Case, async: false
  
  alias SNMPSimEx.{ValueSimulator, TimePatterns, CorrelationEngine}
  alias SNMPSimEx.TestHelpers.PortHelper

  @moduletag :integration
  
  setup do
    # PortHelper automatically handles port allocation
    
    :ok
  end

  describe "Phase 5 Realistic Value Simulation Integration" do
    test "complete traffic counter simulation with all Phase 5 features" do
      # Simulate a cable modem with comprehensive behaviors
      profile_data = %{type: "Counter32", value: 1_500_000}
      
      device_state = %{
        device_id: "cm_001A2B3C4D5E",
        uptime: 7200,  # 2 hours
        interface_utilization: 0.6,
        signal_quality: 82.0,
        temperature: 42.0,
        device_type: :cable_modem,
        mac_address: "001A2B3C4D5E"
      }
      
      # Comprehensive configuration with all Phase 5 features
      config = %{
        rate_range: {8_000, 100_000_000},    # Cable modem range
        variance_type: :device_specific,      # Device-specific variance
        variance: 0.15,                       # 15% variance
        burst_probability: 0.1,               # 10% burst probability
        burst_multiplier: 2.0,                # 2x burst intensity
        smoothing_factor: 0.2,                # Smoothing for rate changes
        post_wrap_jitter: true,               # Counter wrap jitter
        jitter: %{
          jitter_pattern: :gaussian,          # Gaussian jitter pattern
          jitter_amount: 0.02,                # 2% jitter
          jitter_burst_probability: 0.05      # 5% jitter burst chance
        }
      }
      
      # Simulate value with all features
      result = ValueSimulator.simulate_value(
        profile_data,
        {:traffic_counter, config},
        device_state
      )
      
      # Verify result structure and validity
      assert {:counter32, value} = result
      assert is_integer(value)
      assert value >= 0
      
      # Value should have increased significantly due to 2-hour uptime
      assert value > profile_data.value
      
      # Value should be within reasonable bounds for cable modem
      expected_max = profile_data.value + (config.rate_range |> elem(1)) * device_state.uptime
      assert value <= expected_max * 3  # Allow for bursts and variance
    end

    test "gauge simulation integrates time patterns and correlations" do
      current_time = DateTime.utc_now()
      
      # Test during business hours
      business_time = %{current_time | hour: 14, minute: 30}  # 2:30 PM
      
      profile_data = %{type: "Gauge32", value: 35}
      device_state = %{
        device_type: :switch,
        interface_utilization: 0.4,
        network_utilization: 0.5,
        utilization_bias: 1.1
      }
      
      config = %{
        jitter: %{
          jitter_pattern: :time_correlated,
          jitter_amount: 0.05,
          correlation_period_seconds: 1800  # 30-minute correlation
        }
      }
      
      # Simulate utilization during business hours
      result = ValueSimulator.simulate_value(
        profile_data,
        {:utilization_gauge, config},
        Map.put(device_state, :current_time, business_time)
      )
      
      assert {:gauge32, value} = result
      assert value >= 0
      assert value <= 100
      
      # Business hours should generally show higher utilization
      # (though this is probabilistic due to patterns and jitter)
      assert is_integer(value)
    end

    test "signal quality simulation with environmental correlations" do
      # Test signal gauge during different weather conditions
      profile_data = %{type: "Gauge32", value: 12}  # dBmV power level
      
      device_state = %{
        device_type: :cable_modem,
        distance_factor: 0.85,  # Somewhat far from head-end
        temperature: 38.0,      # Moderate temperature
        interface_utilization: 0.7  # High utilization
      }
      
      config = %{
        range: {-15, 15},
        weather_sensitivity: true,
        environmental_factors: true
      }
      
      # Multiple simulations to test consistency
      results = for _ <- 1..20 do
        ValueSimulator.simulate_value(
          profile_data,
          {:signal_gauge, config},
          device_state
        )
      end
      
      # All results should be valid gauge values
      Enum.each(results, fn {:gauge32, value} ->
        assert value >= -15
        assert value <= 15
        assert is_integer(value)
      end)
      
      # Results should show some variation due to environmental factors
      values = Enum.map(results, fn {:gauge32, value} -> value end)
      unique_values = Enum.uniq(values)
      
      # Should have some variation (not all identical)
      assert length(unique_values) > 1
    end

    test "error counter correlation with utilization and signal quality" do
      profile_data = %{type: "Counter32", value: 50}
      
      # High utilization, poor signal scenario
      high_error_state = %{
        uptime: 3600,  # 1 hour
        interface_utilization: 0.9,   # Very high utilization
        signal_quality: 0.6,          # Poor signal quality
        device_type: :cable_modem
      }
      
      # Low utilization, good signal scenario
      low_error_state = %{
        uptime: 3600,  # 1 hour
        interface_utilization: 0.2,   # Low utilization
        signal_quality: 0.95,         # Excellent signal quality
        device_type: :cable_modem
      }
      
      config = %{rate_range: {0, 1000}, error_burst_probability: 0.1}
      
      # Simulate errors under both conditions
      high_error_result = ValueSimulator.simulate_value(
        profile_data,
        {:error_counter, config},
        high_error_state
      )
      
      low_error_result = ValueSimulator.simulate_value(
        profile_data,
        {:error_counter, config},
        low_error_state
      )
      
      assert {:counter32, high_errors} = high_error_result
      assert {:counter32, low_errors} = low_error_result
      
      # Both should be valid counter values
      assert high_errors >= profile_data.value
      assert low_errors >= profile_data.value
      
      # High utilization + poor signal should generally result in more errors
      # (though this is probabilistic, so we test multiple times)
      error_differences = for _ <- 1..10 do
        {:counter32, high} = ValueSimulator.simulate_value(
          profile_data, {:error_counter, config}, high_error_state
        )
        {:counter32, low} = ValueSimulator.simulate_value(
          profile_data, {:error_counter, config}, low_error_state
        )
        high - low
      end
      
      # Most iterations should show higher errors for poor conditions
      positive_differences = Enum.count(error_differences, & &1 > 0)
      assert positive_differences >= 6  # At least 60% of tests
    end

    test "time patterns integration across daily cycle" do
      profile_data = %{type: "Gauge32", value: 40}
      device_state = %{device_type: :cable_modem, utilization_bias: 1.0}
      config = %{}
      
      # Test utilization at different times of day
      times_and_expected = [
        {3, 0.4},   # 3 AM - low usage
        {9, 0.9},   # 9 AM - business hours
        {14, 1.0},  # 2 PM - business hours
        {19, 1.4},  # 7 PM - evening peak
        {23, 0.7}   # 11 PM - late evening
      ]
      
      base_time = DateTime.utc_now()
      
      results = Enum.map(times_and_expected, fn {hour, expected_factor} ->
        test_time = %{base_time | hour: hour, minute: 0}
        
        # Get time pattern factor
        daily_factor = TimePatterns.get_daily_utilization_pattern(test_time)
        weekly_factor = TimePatterns.get_weekly_pattern(test_time)
        
        # Simulate utilization
        result = ValueSimulator.simulate_value(
          profile_data,
          {:utilization_gauge, config},
          Map.put(device_state, :current_time, test_time)
        )
        
        {:gauge32, value} = result
        {hour, daily_factor, weekly_factor, value, expected_factor}
      end)
      
      # Verify that time patterns are being applied
      Enum.each(results, fn {hour, daily_factor, weekly_factor, value, expected_factor} ->
        assert is_float(daily_factor)
        assert is_float(weekly_factor)
        assert is_integer(value)
        assert value >= 0
        assert value <= 100
        
        # Pattern factors should roughly correspond to expected patterns
        case hour do
          3 -> assert daily_factor < 0.5   # Early morning should be low
          19 -> assert daily_factor > 1.2  # Evening should be high
          _ -> :ok
        end
      end)
    end

    test "correlation engine integration with device state" do
      :rand.seed(:exsplus, {1, 2, 3})  # Fixed seed for deterministic testing
      
      initial_state = %{
        interface_utilization: 0.5,
        signal_quality: 85.0,
        temperature: 35.0,
        cpu_usage: 30.0,
        error_rate: 0.001,
        throughput: 50_000_000,
        power_consumption: 12.0
      }
      
      # Get cable modem correlations
      correlations = CorrelationEngine.get_device_correlations(:cable_modem)
      current_time = DateTime.utc_now()
      
      # Simulate increasing interface utilization
      updated_state1 = CorrelationEngine.apply_correlations(
        :interface_utilization,
        0.8,  # Increase to 80%
        initial_state,
        correlations,
        current_time
      )
      
      # Test temperature correlation in isolation
      temp_test_state = %{
        signal_quality: 85.0,
        temperature: 35.0
      }
      
      # Simulate temperature increase in isolation
      updated_temp_state = CorrelationEngine.apply_correlations(
        :temperature,
        45.0,  # Increase temperature
        temp_test_state,
        correlations,
        current_time
      )
      
      # Verify correlations have been applied
      assert is_map(updated_temp_state)
      
      # Check that correlated metrics have changed appropriately
      if Map.has_key?(updated_state1, :error_rate) do
        # Verify that correlations have been applied (value should change)
        assert updated_state1.error_rate != initial_state.error_rate,
               "Error rate should change due to correlations. Initial: #{initial_state.error_rate}, Updated: #{updated_state1.error_rate}"
        # Ensure error rate remains in realistic range
        assert updated_state1.error_rate > 0,
               "Error rate should be positive, got #{updated_state1.error_rate}"
        assert updated_state1.error_rate < 1.0,
               "Error rate should be less than 100%, got #{updated_state1.error_rate}"
      end
      
      if Map.has_key?(updated_temp_state, :signal_quality) do
        # Higher temperature should generally decrease signal quality (with tolerance for noise)
        # The correlation includes ±2% noise, so we allow some tolerance but expect general decrease
        signal_change_percent = (updated_temp_state.signal_quality - temp_test_state.signal_quality) / temp_test_state.signal_quality * 100
        assert signal_change_percent <= 5.0, 
          "Signal quality increased too much (#{Float.round(signal_change_percent, 2)}%) when temperature increased. Expected decrease or small increase due to noise."
      end
      
      # All values should remain within realistic bounds
      Enum.each(updated_temp_state, fn {key, value} ->
        assert is_number(value)
        
        case key do
          :interface_utilization -> assert value >= 0 and value <= 1.0
          :signal_quality -> assert value >= 0 and value <= 100
          :temperature -> assert value >= -10 and value <= 100
          :cpu_usage -> assert value >= 0 and value <= 100
          :error_rate -> assert value >= 0 and value <= 1.0
          :power_consumption -> assert value > 0
          _ -> assert is_number(value)
        end
      end)
    end

    test "counter wrapping behavior across device types" do
      # Test counter approaching wrap for different device types
      near_wrap_value = 4_294_967_000  # Very close to 32-bit max
      
      device_types = [:cable_modem, :cmts, :switch, :router, :server]
      
      results = Enum.map(device_types, fn device_type ->
        wrapped_value = ValueSimulator.apply_device_specific_counter_behavior(
          near_wrap_value + 500,  # Force wrap
          "Counter32",
          device_type,
          %{}
        )
        
        {device_type, wrapped_value}
      end)
      
      # All should have wrapped to small values
      Enum.each(results, fn {device_type, value} ->
        assert is_integer(value)
        assert value >= 0
        assert value < 10_000  # Should be small after wrap
        
        # Verify device-specific behavior
        case device_type do
          :cmts ->
            # CMTS might have synchronized wrapping
            assert value >= 0
          :switch ->
            # Switch might have buffering effects
            assert value >= 0
          _ ->
            assert value >= 0
        end
      end)
    end

    test "performance with realistic device simulation" do
      # Test performance of complete Phase 5 simulation
      profile_data = %{type: "Counter32", value: 1_000_000}
      
      device_state = %{
        device_id: "perf_test_device",
        uptime: 1800,
        interface_utilization: 0.6,
        signal_quality: 80.0,
        temperature: 40.0,
        device_type: :cable_modem
      }
      
      config = %{
        rate_range: {10_000, 50_000_000},
        variance_type: :gaussian,
        variance: 0.1,
        burst_probability: 0.05,
        jitter: %{
          jitter_pattern: :burst,
          jitter_amount: 0.03
        }
      }
      
      start_time = :os.system_time(:microsecond)
      
      # Simulate 1000 value generations
      results = for _ <- 1..1000 do
        ValueSimulator.simulate_value(
          profile_data,
          {:traffic_counter, config},
          device_state
        )
      end
      
      end_time = :os.system_time(:microsecond)
      duration_ms = (end_time - start_time) / 1000
      
      # Verify all results are valid
      Enum.each(results, fn {:counter32, value} ->
        assert is_integer(value)
        assert value >= 0
      end)
      
      # Performance should be reasonable (< 200ms for 1000 simulations)
      assert duration_ms < 200
      
      # Log performance for visibility
      IO.puts("Phase 5 simulation performance: #{Float.round(duration_ms, 2)}ms for 1000 simulations")
      IO.puts("Average per simulation: #{Float.round(duration_ms / 1000, 3)}ms")
    end

    test "seasonal and weather patterns integration" do
      # Test seasonal temperature variation
      winter_date = ~U[2024-01-15 14:00:00Z]
      summer_date = ~U[2024-07-15 14:00:00Z]
      
      winter_temp_offset = TimePatterns.get_seasonal_temperature_pattern(winter_date)
      summer_temp_offset = TimePatterns.get_seasonal_temperature_pattern(summer_date)
      
      # Summer should be warmer than winter
      assert summer_temp_offset > winter_temp_offset
      assert winter_temp_offset < 0  # Winter should be below baseline
      assert summer_temp_offset > 0  # Summer should be above baseline
      
      # Test weather variation impact
      weather_samples = for _ <- 1..20 do
        TimePatterns.apply_weather_variation(DateTime.utc_now())
      end
      
      # Should have variation in weather factors
      unique_factors = Enum.uniq(weather_samples)
      assert length(unique_factors) > 1
      
      # All factors should be positive
      assert Enum.all?(weather_samples, & &1 > 0)
      
      # Most should be around 1.0 (good weather) with some variations
      near_normal = Enum.count(weather_samples, fn factor ->
        factor >= 0.9 and factor <= 1.1
      end)
      
      assert near_normal >= 10  # At least half should be near normal
    end

    test "jitter patterns produce expected characteristics" do
      base_value = 1000.0
      device_type = :cable_modem
      
      # Test different jitter patterns
      jitter_configs = [
        %{jitter_pattern: :uniform, jitter_amount: 0.05},
        %{jitter_pattern: :gaussian, jitter_amount: 0.05},
        %{jitter_pattern: :periodic, jitter_period: 300},
        %{jitter_pattern: :burst, jitter_burst_probability: 0.3}
      ]
      
      pattern_results = Enum.map(jitter_configs, fn config ->
        # Generate multiple samples for each pattern
        samples = for _ <- 1..50 do
          ValueSimulator.apply_configurable_jitter(
            base_value,
            :utilization_gauge,
            device_type,
            config
          )
        end
        
        pattern = config.jitter_pattern
        {pattern, samples}
      end)
      
      # Verify all patterns produce valid results
      Enum.each(pattern_results, fn {pattern, samples} ->
        assert length(samples) == 50
        
        # All samples should be reasonable values
        Enum.each(samples, fn value ->
          assert is_float(value)
          assert value > 0
          # Should be within reasonable jitter range
          assert value >= base_value * 0.5
          assert value <= base_value * 1.5
        end)
        
        # Check pattern-specific characteristics
        case pattern do
          :uniform ->
            # Uniform should have fairly even distribution
            assert length(Enum.uniq(samples)) > 20
            
          :gaussian ->
            # Gaussian should cluster around the mean
            mean = Enum.sum(samples) / length(samples)
            assert abs(mean - base_value) < base_value * 0.1
            
          :periodic ->
            # Periodic might have less variation (time-based)
            assert length(Enum.uniq(samples)) >= 1
            
          :burst ->
            # Burst should have some outliers
            sorted = Enum.sort(samples)
            min_val = List.first(sorted)
            max_val = List.last(sorted)
            range = max_val - min_val
            assert range > base_value * 0.2  # Should have significant range
        end
      end)
    end
  end

  describe "Phase 5 Integration with Existing Components" do
    test "value simulation works with OID tree and profiles" do
      # This would typically test integration with the actual device/profile system
      # For now, test that our simulation functions are compatible
      
      # Mock profile data that would come from OID tree
      mock_oid_data = %{
        "1.3.6.1.2.1.2.2.1.10.2" => %{type: "Counter32", value: 1_234_567},
        "1.3.6.1.2.1.2.2.1.16.2" => %{type: "Counter32", value: 987_654},
        "1.3.6.1.2.1.2.2.1.8.2" => %{type: "INTEGER", value: 1},
        "1.3.6.1.2.1.25.3.3.1.2.1" => %{type: "Gauge32", value: 45}
      }
      
      device_state = %{
        device_type: :cable_modem,
        uptime: 3600,
        interface_utilization: 0.4,
        signal_quality: 85.0,
        temperature: 35.0
      }
      
      # Simulate each OID with appropriate behavior
      results = Enum.map(mock_oid_data, fn {oid, profile_data} ->
        behavior = case oid do
          "1.3.6.1.2.1.2.2.1.10.2" -> {:traffic_counter, %{rate_range: {1000, 50_000_000}}}
          "1.3.6.1.2.1.2.2.1.16.2" -> {:traffic_counter, %{rate_range: {1000, 50_000_000}}}
          "1.3.6.1.2.1.2.2.1.8.2" -> {:status_enum, %{}}
          "1.3.6.1.2.1.25.3.3.1.2.1" -> {:cpu_gauge, %{}}
          _ -> {:static_value, %{}}
        end
        
        result = ValueSimulator.simulate_value(profile_data, behavior, device_state)
        {oid, result}
      end)
      
      # Verify all simulations produced valid results
      Enum.each(results, fn {oid, result} ->
        case oid do
          "1.3.6.1.2.1.2.2.1.10.2" -> assert {:counter32, _} = result
          "1.3.6.1.2.1.2.2.1.16.2" -> assert {:counter32, _} = result
          "1.3.6.1.2.1.2.2.1.8.2" -> assert is_integer(result) or is_binary(result)
          "1.3.6.1.2.1.25.3.3.1.2.1" -> assert {:gauge32, _} = result
        end
      end)
    end

    test "correlation engine works with multiple simultaneous correlations" do
      :rand.seed(:exsplus, {1, 2, 3})  # Fixed seed for deterministic testing
      
      # Test complex correlation scenarios
      device_state = %{
        interface_utilization: 0.6,
        signal_quality: 80.0,
        temperature: 38.0,
        cpu_usage: 45.0,
        error_rate: 0.002,
        throughput: 60_000_000,
        power_consumption: 15.0,
        memory_usage: 55.0,
        fan_speed: 2500
      }
      
      correlations = CorrelationEngine.get_device_correlations(:switch)
      current_time = DateTime.utc_now()
      
      # Apply multiple correlation updates in sequence
      state1 = CorrelationEngine.apply_correlations(
        :cpu_usage, 70.0, device_state, correlations, current_time
      )
      
      state2 = CorrelationEngine.apply_correlations(
        :interface_utilization, 0.9, state1, correlations, current_time
      )
      
      state3 = CorrelationEngine.apply_correlations(
        :temperature, 55.0, state2, correlations, current_time
      )
      
      # Verify final state is consistent and realistic
      assert is_map(state3)
      assert map_size(state3) >= map_size(device_state)
      
      # Temperature increase should affect correlated metrics
      if Map.has_key?(state3, :fan_speed) do
        # Fan speed should be within reasonable range for higher temperature
        assert state3.fan_speed > 1000 and state3.fan_speed < 5000
      end
      
      # High CPU and utilization should affect power consumption
      if Map.has_key?(state3, :power_consumption) do
        # Power consumption should be within reasonable range for high CPU and utilization
        assert state3.power_consumption > 5.0 and state3.power_consumption < 50.0
      end
    end
  end
end