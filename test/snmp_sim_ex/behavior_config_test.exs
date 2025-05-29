defmodule SnmpSimEx.BehaviorConfigTest do
  use ExUnit.Case, async: true
  
  alias SnmpSimEx.{BehaviorConfig, ProfileLoader}

  describe "Behavior Presets" do
    test "cable modem realistic preset contains appropriate behaviors" do
      behaviors = BehaviorConfig.get_preset(:cable_modem_realistic)
      
      assert is_list(behaviors)
      assert length(behaviors) > 5  # Should have multiple behavior configs
      
      # Should contain traffic counter configuration
      traffic_config = Enum.find(behaviors, fn
        {:increment_counters, %{oid_patterns: patterns}} ->
          "ifInOctets" in patterns or "ifOutOctets" in patterns
        _ -> false
      end)
      assert traffic_config != nil
      
      # Should contain error counter configuration
      error_config = Enum.find(behaviors, fn
        {:increment_counters, %{oid_patterns: patterns}} ->
          "ifInErrors" in patterns or "ifOutErrors" in patterns
        _ -> false
      end)
      assert error_config != nil
    end

    test "CMTS realistic preset has appropriate high-capacity settings" do
      behaviors = BehaviorConfig.get_preset(:cmts_realistic)
      
      # Should have high-capacity traffic handling
      traffic_config = Enum.find(behaviors, fn
        {:increment_counters, %{rate_range: {min, max}}} ->
          max > 100_000_000  # High capacity
        _ -> false
      end)
      assert traffic_config != nil
    end

    test "high traffic simulation preset has multipliers" do
      behaviors = BehaviorConfig.get_preset(:high_traffic_simulation)
      
      # Should contain rate multipliers
      multiplier_config = Enum.find(behaviors, fn
        {:increment_counters, %{rate_multiplier: multiplier}} ->
          multiplier > 1.0
        _ -> false
      end)
      assert multiplier_config != nil
    end

    test "returns error for unknown preset" do
      result = BehaviorConfig.get_preset(:unknown_preset)
      assert {:error, :unknown_preset} = result
    end
  end

  describe "Behavior Application" do
    test "applies realistic counters to walk file profile" do
      # Create a test profile with counter OIDs
      oid_map = %{
        "1.3.6.1.2.1.2.2.1.10.1" => %{type: "Counter32", value: 1000000},
        "1.3.6.1.2.1.2.2.1.16.1" => %{type: "Counter32", value: 500000},
        "1.3.6.1.2.1.1.1.0" => %{type: "STRING", value: "Test Device"}
      }
      
      profile = %ProfileLoader{
        device_type: :test_device,
        source_type: :walk_file,
        oid_map: oid_map,
        behaviors: [],
        metadata: %{}
      }
      
      enhanced_profile = BehaviorConfig.apply_behaviors(profile, [:realistic_counters])
      
      # Counter OIDs should have behaviors applied
      counter_oid = enhanced_profile.oid_map["1.3.6.1.2.1.2.2.1.10.1"]
      assert Map.has_key?(counter_oid, :behavior)
      
      # String OID should remain unchanged
      string_oid = enhanced_profile.oid_map["1.3.6.1.2.1.1.1.0"]
      assert string_oid.type == "STRING"
    end

    test "applies daily patterns to appropriate OIDs" do
      oid_map = %{
        "1.3.6.1.2.1.2.2.1.10.1" => %{type: "Counter32", value: 1000000},
        "1.3.6.1.2.1.2.2.1.5.1" => %{type: "Gauge32", value: 50}
      }
      
      profile = %ProfileLoader{
        device_type: :test_device,
        oid_map: oid_map,
        behaviors: [],
        metadata: %{}
      }
      
      enhanced_profile = BehaviorConfig.apply_behaviors(profile, [:daily_patterns])
      
      # Both counter and gauge should support daily patterns
      counter_oid = enhanced_profile.oid_map["1.3.6.1.2.1.2.2.1.10.1"]
      gauge_oid = enhanced_profile.oid_map["1.3.6.1.2.1.2.2.1.5.1"]
      
      assert Map.has_key?(counter_oid, :behavior)
      assert Map.has_key?(gauge_oid, :behavior)
    end

    test "applies increment counters with specific OID patterns" do
      oid_map = %{
        "1.3.6.1.2.1.2.2.1.10.1" => %{type: "Counter32", value: 1000000},  # ifInOctets
        "1.3.6.1.2.1.2.2.1.16.1" => %{type: "Counter32", value: 500000},   # ifOutOctets
        "1.3.6.1.2.1.2.2.1.14.1" => %{type: "Counter32", value: 5}         # ifInErrors
      }
      
      profile = %ProfileLoader{
        device_type: :test_device,
        oid_map: oid_map,
        behaviors: [],
        metadata: %{}
      }
      
      behavior_config = {:increment_counters, %{
        oid_patterns: ["ifInOctets", "ifOutOctets"],
        rate_range: {1000, 50_000_000}
      }}
      
      enhanced_profile = BehaviorConfig.apply_behaviors(profile, [behavior_config])
      
      # Traffic counters should have behavior applied
      in_octets = enhanced_profile.oid_map["1.3.6.1.2.1.2.2.1.10.1"]
      out_octets = enhanced_profile.oid_map["1.3.6.1.2.1.2.2.1.16.1"]
      
      assert Map.has_key?(in_octets, :behavior)
      assert Map.has_key?(out_octets, :behavior)
      
      # Error counter should not be affected (different pattern)
      errors = enhanced_profile.oid_map["1.3.6.1.2.1.2.2.1.14.1"]
      assert !Map.has_key?(errors, :behavior) or errors.behavior == nil
    end

    test "applies gauge behaviors with range constraints" do
      oid_map = %{
        "1.3.6.1.2.1.2.2.1.5.1" => %{type: "Gauge32", value: 50},  # ifSpeed
        "1.3.6.1.2.1.25.3.3.1.2.1" => %{type: "Gauge32", value: 30}  # CPU
      }
      
      profile = %ProfileLoader{
        device_type: :test_device,
        oid_map: oid_map,
        behaviors: [],
        metadata: %{}
      }
      
      behavior_config = {:vary_gauges, %{
        oid_patterns: ["ifSpeed"],
        range: {0, 100},
        pattern: :utilization_based
      }}
      
      enhanced_profile = BehaviorConfig.apply_behaviors(profile, [behavior_config])
      
      # Only ifSpeed should have behavior applied
      if_speed = enhanced_profile.oid_map["1.3.6.1.2.1.2.2.1.5.1"]
      cpu_gauge = enhanced_profile.oid_map["1.3.6.1.2.1.25.3.3.1.2.1"]
      
      assert Map.has_key?(if_speed, :behavior)
      assert !Map.has_key?(cpu_gauge, :behavior) or cpu_gauge.behavior == nil
    end
  end

  describe "Custom Behavior Creation" do
    test "creates custom behavior configuration" do
      behavior_specs = [
        {:traffic_counters, %{
          rate_multiplier: 2.0,
          daily_pattern: true
        }},
        {:signal_quality, %{
          base_snr: 25,
          weather_impact: true
        }}
      ]
      
      {:ok, normalized_behaviors} = BehaviorConfig.create_custom(behavior_specs)
      
      assert length(normalized_behaviors) == 2
      assert Enum.all?(normalized_behaviors, fn {type, config} ->
        is_atom(type) and is_map(config)
      end)
    end

    test "validates behavior specifications" do
      valid_specs = [
        {:increment_counters, %{rate_range: {100, 1000}}},
        {:vary_gauges, %{range: {0, 100}}}
      ]
      
      invalid_specs = [
        {:invalid_behavior, %{}},
        "not_a_tuple"
      ]
      
      assert {:ok, _} = BehaviorConfig.create_custom(valid_specs)
      assert {:error, _} = BehaviorConfig.create_custom(invalid_specs)
    end

    test "normalizes behavior specifications" do
      mixed_specs = [
        :realistic_counters,  # Atom form
        {:custom_utilization, %{peak_hours: {9, 17}}}  # Tuple form
      ]
      
      {:ok, normalized} = BehaviorConfig.create_custom(mixed_specs)
      
      # All should be normalized to tuple form
      assert Enum.all?(normalized, fn {type, config} ->
        is_atom(type) and is_map(config)
      end)
    end
  end

  describe "Available Behaviors Listing" do
    test "lists all available behavior categories" do
      behaviors = BehaviorConfig.list_available_behaviors()
      
      assert Map.has_key?(behaviors, :counter_behaviors)
      assert Map.has_key?(behaviors, :gauge_behaviors)
      assert Map.has_key?(behaviors, :time_patterns)
      assert Map.has_key?(behaviors, :signal_quality)
      assert Map.has_key?(behaviors, :error_simulation)
      
      # Each category should have multiple options
      assert length(behaviors.counter_behaviors) > 2
      assert length(behaviors.gauge_behaviors) > 2
      assert length(behaviors.time_patterns) > 2
    end
  end

  describe "Realistic Error Behaviors" do
    test "applies error behaviors to error counter OIDs" do
      oid_map = %{
        "1.3.6.1.2.1.2.2.1.14.1" => %{type: "Counter32", value: 5},      # ifInErrors
        "1.3.6.1.2.1.2.2.1.20.1" => %{type: "Counter32", value: 2},      # ifOutErrors
        "1.3.6.1.2.1.2.2.1.10.1" => %{type: "Counter32", value: 1000000} # ifInOctets
      }
      
      profile = %ProfileLoader{
        device_type: :test_device,
        oid_map: oid_map,
        behaviors: [],
        metadata: %{}
      }
      
      error_config = {:realistic_errors, %{
        error_rate_multiplier: 2.0,
        burst_probability: 0.1
      }}
      
      enhanced_profile = BehaviorConfig.apply_behaviors(profile, [error_config])
      
      # Error counters should have behavior applied
      in_errors = enhanced_profile.oid_map["1.3.6.1.2.1.2.2.1.14.1"]
      out_errors = enhanced_profile.oid_map["1.3.6.1.2.1.2.2.1.20.1"]
      
      assert Map.has_key?(in_errors, :behavior)
      assert Map.has_key?(out_errors, :behavior)
      
      # Traffic counter should not be affected
      in_octets = enhanced_profile.oid_map["1.3.6.1.2.1.2.2.1.10.1"]
      assert !Map.has_key?(in_octets, :behavior) or in_octets.behavior == nil
    end
  end

  describe "Multiple Behavior Application" do
    test "applies multiple behaviors in sequence" do
      oid_map = %{
        "1.3.6.1.2.1.2.2.1.10.1" => %{type: "Counter32", value: 1000000}
      }
      
      profile = %ProfileLoader{
        device_type: :test_device,
        oid_map: oid_map,
        behaviors: [],
        metadata: %{}
      }
      
      behaviors = [
        :realistic_counters,
        :daily_patterns,
        :weekly_patterns
      ]
      
      enhanced_profile = BehaviorConfig.apply_behaviors(profile, behaviors)
      
      # Should have behavior configuration applied
      counter_oid = enhanced_profile.oid_map["1.3.6.1.2.1.2.2.1.10.1"]
      assert Map.has_key?(counter_oid, :behavior)
      
      # Behavior should include patterns from multiple configs
      {_behavior_type, config} = counter_oid.behavior
      assert is_map(config)
    end
  end
end