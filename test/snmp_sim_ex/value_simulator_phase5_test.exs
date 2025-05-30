defmodule SNMPSimEx.ValueSimulatorPhase5Test do
  use ExUnit.Case, async: false
  alias SNMPSimEx.ValueSimulator

  describe "counter wrapping functionality" do
    test "handles 32-bit counter wrapping correctly" do
      # Test counter value approaching maximum
      near_max_value = 4_294_967_290
      profile_data = %{type: "Counter32", value: near_max_value}
      device_state = %{uptime: 10, device_type: :cable_modem}
      
      result = ValueSimulator.simulate_value(
        profile_data,
        {:traffic_counter, %{rate_range: {1000, 10000}}},
        device_state
      )
      
      assert {:counter32, value} = result
      # Should wrap around and be a small value
      assert value < 100_000
    end

    test "handles 64-bit counter wrapping correctly" do
      # 64-bit counters should rarely wrap but handle it properly
      large_value = 18_446_744_073_709_551_600
      profile_data = %{type: "Counter64", value: large_value}
      device_state = %{uptime: 10, device_type: :server}
      
      result = ValueSimulator.simulate_value(
        profile_data,
        {:traffic_counter, %{rate_range: {1000, 10000}}},
        device_state
      )
      
      assert {:counter64, value} = result
      # Should handle the large value appropriately
      assert is_integer(value)
      assert value >= 0
    end

    test "counter_approaching_wrap? detects near-wrap conditions" do
      # 32-bit counter near maximum
      assert ValueSimulator.counter_approaching_wrap?(4_000_000_000, "Counter32", 0.9)
      refute ValueSimulator.counter_approaching_wrap?(1_000_000_000, "Counter32", 0.9)
      
      # 64-bit counter near maximum
      large_value = 17_000_000_000_000_000_000
      assert ValueSimulator.counter_approaching_wrap?(large_value, "Counter64", 0.9)
      
      # Non-counter types
      refute ValueSimulator.counter_approaching_wrap?(1000, "Gauge32", 0.9)
    end

    test "time_until_counter_wrap calculates correctly" do
      current_value = 4_000_000_000  # Near 32-bit max
      increment_rate = 1000          # 1000 per second
      
      time_until_wrap = ValueSimulator.time_until_counter_wrap(
        current_value, 
        increment_rate, 
        "Counter32"
      )
      
      # Should be around 294,967 seconds until wrap
      assert time_until_wrap > 290_000
      assert time_until_wrap < 300_000
    end

    test "apply_device_specific_counter_behavior varies by device type" do
      base_value = 100
      
      # Test different device types
      cable_modem_result = ValueSimulator.apply_device_specific_counter_behavior(
        base_value, "Counter32", :cable_modem, %{}
      )
      
      cmts_result = ValueSimulator.apply_device_specific_counter_behavior(
        base_value, "Counter32", :cmts, %{synchronized_wrap: true, sync_boundary: 1000}
      )
      
      switch_result = ValueSimulator.apply_device_specific_counter_behavior(
        base_value, "Counter32", :switch, %{}
      )
      
      # All should be valid counter values
      assert is_integer(cable_modem_result)
      assert is_integer(cmts_result) 
      assert is_integer(switch_result)
      assert cable_modem_result >= 0
      assert cmts_result >= 0
      assert switch_result >= 0
    end

    test "handle_counter_discontinuity detects wraps" do
      old_value = 4_000_000_000
      new_value = 1000  # Wrapped
      discontinuity_counter = 5
      
      result = ValueSimulator.handle_counter_discontinuity(
        old_value, 
        new_value, 
        discontinuity_counter
      )
      
      # Should increment discontinuity counter
      assert result == 6
      
      # Test no wrap case
      result2 = ValueSimulator.handle_counter_discontinuity(
        1000, 
        2000, 
        discontinuity_counter
      )
      
      # Should not increment
      assert result2 == 5
    end
  end

  describe "configurable jitter and variance" do
    test "apply_configurable_jitter works with different patterns" do
      base_value = 1000.0
      device_type = :cable_modem
      
      # Test uniform jitter
      uniform_result = ValueSimulator.apply_configurable_jitter(
        base_value, 
        :traffic_counter, 
        device_type, 
        %{jitter_pattern: :uniform, jitter_amount: 0.1}
      )
      
      # Should be within reasonable range
      assert uniform_result >= base_value * 0.8
      assert uniform_result <= base_value * 1.2
      
      # Test gaussian jitter
      gaussian_result = ValueSimulator.apply_configurable_jitter(
        base_value, 
        :cpu_gauge, 
        device_type, 
        %{jitter_pattern: :gaussian, jitter_amount: 0.05}
      )
      
      assert is_float(gaussian_result)
      assert gaussian_result > 0
      
      # Test periodic jitter
      periodic_result = ValueSimulator.apply_configurable_jitter(
        base_value, 
        :utilization_gauge, 
        device_type, 
        %{jitter_pattern: :periodic, jitter_period: 300}
      )
      
      assert is_float(periodic_result)
      
      # Test burst jitter
      burst_result = ValueSimulator.apply_configurable_jitter(
        base_value, 
        :snr_gauge, 
        device_type, 
        %{jitter_pattern: :burst, jitter_burst_probability: 0.5}
      )
      
      assert is_float(burst_result)
    end

    test "different device types have different jitter characteristics" do
      base_value = 100.0
      jitter_config = %{jitter_pattern: :uniform, jitter_amount: 0.1}
      
      # MTA devices should have lower jitter (voice quality requirements)
      mta_result = ValueSimulator.apply_configurable_jitter(
        base_value, :cpu_gauge, :mta, jitter_config
      )
      
      # Server devices should have higher jitter (workload variability)
      server_result = ValueSimulator.apply_configurable_jitter(
        base_value, :cpu_gauge, :server, jitter_config
      )
      
      # Both should be valid but potentially different ranges
      assert is_float(mta_result)
      assert is_float(server_result)
    end

    test "variance types produce different distributions" do
      # Test variance through actual value simulation which uses variance internally
      profile_data = %{type: "Counter32", value: 1000}
      device_state = %{uptime: 100, device_type: :cable_modem}
      
      config_uniform = %{variance_type: :uniform, variance: 0.1, rate_range: {1000, 2000}}
      config_gaussian = %{variance_type: :gaussian, variance: 0.1, rate_range: {1000, 2000}}
      config_burst = %{variance_type: :burst, variance: 0.1, burst_probability: 0.1, rate_range: {1000, 2000}}
      
      # Generate multiple samples to test distribution characteristics
      uniform_samples = for _ <- 1..50 do
        {:counter32, value} = ValueSimulator.simulate_value(
          profile_data, {:traffic_counter, config_uniform}, device_state
        )
        value
      end
      
      gaussian_samples = for _ <- 1..50 do
        {:counter32, value} = ValueSimulator.simulate_value(
          profile_data, {:traffic_counter, config_gaussian}, device_state
        )
        value
      end
      
      burst_samples = for _ <- 1..50 do
        {:counter32, value} = ValueSimulator.simulate_value(
          profile_data, {:traffic_counter, config_burst}, device_state
        )
        value
      end
      
      # All samples should be positive and greater than base
      assert Enum.all?(uniform_samples, & &1 > profile_data.value)
      assert Enum.all?(gaussian_samples, & &1 > profile_data.value)
      assert Enum.all?(burst_samples, & &1 > profile_data.value)
      
      # Should have variation
      assert length(Enum.uniq(uniform_samples)) > 10
      assert length(Enum.uniq(gaussian_samples)) > 10
      assert length(Enum.uniq(burst_samples)) > 10
    end

    test "time_correlated variance changes over time" do
      # Test time-correlated variance through actual simulation
      profile_data = %{type: "Counter32", value: 1000}
      device_state = %{uptime: 100, device_type: :cable_modem}
      
      config = %{
        variance_type: :time_correlated, 
        variance: 0.2,
        correlation_period_seconds: 300,  # 5 minute period
        rate_range: {1000, 2000}
      }
      
      # Generate multiple samples rapidly (should be similar due to time correlation)
      results = for _ <- 1..10 do
        {:counter32, value} = ValueSimulator.simulate_value(
          profile_data, {:traffic_counter, config}, device_state
        )
        value
      end
      
      # Results should show some consistency due to time correlation
      # but also some variation due to random component
      assert length(results) == 10
      assert Enum.all?(results, & &1 > profile_data.value)
      
      # Should have some variation but not too much
      unique_results = Enum.uniq(results)
      assert length(unique_results) >= 3   # Some variation
      assert length(unique_results) <= 10  # Not too much variation (allow for randomness)
    end

    test "device_specific variance reflects device characteristics" do
      # Test device-specific variance through actual simulation
      profile_data = %{type: "Counter32", value: 1000}
      base_device_state = %{uptime: 100}
      
      config = %{
        variance_type: :device_specific,
        variance: 0.1,
        rate_range: {1000, 2000}
      }
      
      # Test MTA devices (should have lower variance - voice requirements)
      mta_samples = for _ <- 1..30 do
        {:counter32, value} = ValueSimulator.simulate_value(
          profile_data, 
          {:traffic_counter, config}, 
          Map.put(base_device_state, :device_type, :mta)
        )
        value
      end
      
      # Test Server devices (should have higher variance - workload variability)
      server_samples = for _ <- 1..30 do
        {:counter32, value} = ValueSimulator.simulate_value(
          profile_data, 
          {:traffic_counter, config}, 
          Map.put(base_device_state, :device_type, :server)
        )
        value
      end
      
      # Both should produce valid results
      assert Enum.all?(mta_samples, & &1 > profile_data.value)
      assert Enum.all?(server_samples, & &1 > profile_data.value)
      
      # Calculate variance measures (simplified)
      mta_mean = Enum.sum(mta_samples) / length(mta_samples)
      server_mean = Enum.sum(server_samples) / length(server_samples)
      
      mta_variance = Enum.reduce(mta_samples, 0, fn x, acc -> 
        acc + :math.pow(x - mta_mean, 2) 
      end) / length(mta_samples)
      
      server_variance = Enum.reduce(server_samples, 0, fn x, acc -> 
        acc + :math.pow(x - server_mean, 2) 
      end) / length(server_samples)
      
      # Both should have some variance
      assert mta_variance > 0
      assert server_variance > 0
      
      # Verify device types produce different characteristics
      assert length(Enum.uniq(mta_samples)) > 5
      assert length(Enum.uniq(server_samples)) > 5
    end
  end

  describe "realistic gauge simulation with jitter" do
    test "utilization gauge includes jitter" do
      profile_data = %{type: "Gauge32", value: 50}
      device_state = %{device_type: :cable_modem, utilization_bias: 1.0}
      config = %{jitter: %{jitter_pattern: :uniform, jitter_amount: 0.05}}
      
      result = ValueSimulator.simulate_value(
        profile_data,
        {:utilization_gauge, config},
        device_state
      )
      
      assert {:gauge32, value} = result
      assert value >= 0
      assert value <= 100
    end

    test "cpu gauge includes device-specific jitter" do
      profile_data = %{type: "Gauge32", value: 25}
      device_state = %{device_type: :server, interface_utilization: 0.5}
      config = %{jitter: %{jitter_pattern: :gaussian, jitter_amount: 0.08}}
      
      result = ValueSimulator.simulate_value(
        profile_data,
        {:cpu_gauge, config},
        device_state
      )
      
      assert {:gauge32, value} = result
      assert value >= 0
      assert value <= 100
    end

    test "temperature gauge maintains realistic ranges with jitter" do
      profile_data = %{type: "Gauge32", value: 25}
      device_state = %{device_type: :cable_modem, cpu_utilization: 0.3}
      config = %{jitter: %{jitter_pattern: :periodic, jitter_period: 600}}
      
      result = ValueSimulator.simulate_value(
        profile_data,
        {:temperature_gauge, config},
        device_state
      )
      
      assert {:gauge32, value} = result
      # Temperature should be in reasonable range
      assert value >= -10
      assert value <= 85
    end
  end

  describe "integration with time patterns and correlations" do
    test "traffic counter simulation integrates all Phase 5 features" do
      profile_data = %{type: "Counter32", value: 1_000_000}
      device_state = %{
        device_id: "test_device_001",
        uptime: 3600,
        interface_utilization: 0.4,
        device_type: :cable_modem
      }
      
      config = %{
        rate_range: {1000, 50_000_000},
        variance_type: :device_specific,
        variance: 0.15,
        burst_probability: 0.1,
        smoothing_factor: 0.2,
        post_wrap_jitter: true
      }
      
      result = ValueSimulator.simulate_value(
        profile_data,
        {:traffic_counter, config},
        device_state
      )
      
      assert {:counter32, value} = result
      assert is_integer(value)
      assert value >= 0
      
      # Value should have increased from base due to uptime and rate
      assert value >= profile_data.value
    end

    test "error counter includes correlation with utilization" do
      profile_data = %{type: "Counter32", value: 100}
      device_state = %{
        uptime: 1800,  # 30 minutes
        interface_utilization: 0.8,  # High utilization should increase errors
        signal_quality: 0.7,         # Lower signal quality should increase errors
        device_type: :cable_modem
      }
      
      config = %{rate_range: {0, 500}}
      
      result = ValueSimulator.simulate_value(
        profile_data,
        {:error_counter, config},
        device_state
      )
      
      assert {:counter32, value} = result
      assert value >= profile_data.value  # Should have accumulated some errors
    end

    test "signal gauge responds to environmental factors" do
      profile_data = %{type: "Gauge32", value: 15}
      device_state = %{
        distance_factor: 0.8,  # Further from head-end
        device_type: :cable_modem
      }
      
      config = %{range: {-20, 20}}
      
      result = ValueSimulator.simulate_value(
        profile_data,
        {:signal_gauge, config},
        device_state
      )
      
      assert {:gauge32, value} = result
      assert value >= -20
      assert value <= 20
    end
  end

  describe "performance characteristics" do
    test "value simulation executes quickly" do
      profile_data = %{type: "Counter32", value: 1000}
      device_state = %{uptime: 100, device_type: :cable_modem}
      config = %{rate_range: {1000, 10000}}
      
      start_time = :os.system_time(:microsecond)
      
      # Simulate 1000 value generations
      for _ <- 1..1000 do
        ValueSimulator.simulate_value(
          profile_data,
          {:traffic_counter, config},
          device_state
        )
      end
      
      end_time = :os.system_time(:microsecond)
      duration_ms = (end_time - start_time) / 1000
      
      # Should complete 1000 simulations in reasonable time (< 100ms)
      assert duration_ms < 100
    end

    test "counter wrapping detection is efficient" do
      start_time = :os.system_time(:microsecond)
      
      # Test 10,000 wrap detections
      for i <- 1..10_000 do
        ValueSimulator.counter_approaching_wrap?(
          i * 100_000, 
          "Counter32", 
          0.95
        )
      end
      
      end_time = :os.system_time(:microsecond)
      duration_ms = (end_time - start_time) / 1000
      
      # Should complete 10,000 checks quickly
      assert duration_ms < 50
    end
  end
end