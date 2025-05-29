defmodule SnmpSimEx.ValueSimulator do
  @moduledoc """
  Generate realistic values based on MIB-derived behavior patterns.
  Supports counters, gauges, enums, and correlated metrics with time-based variations.
  """

  alias SnmpSimEx.TimePatterns

  @doc """
  Simulate a value based on profile data, behavior configuration, and device state.
  
  ## Examples
  
      # Traffic counter simulation
      value = SnmpSimEx.ValueSimulator.simulate_value(
        %{type: "Counter32", value: 1000000},
        {:traffic_counter, %{rate_range: {1000, 125_000_000}}},
        %{device_id: "cm_001", uptime: 3600, interface_utilization: 0.3}
      )
      
  """
  def simulate_value(profile_data, behavior_config, device_state) do
    current_time = DateTime.utc_now()
    
    case behavior_config do
      {:traffic_counter, config} ->
        simulate_traffic_counter(profile_data, config, device_state, current_time)
        
      {:packet_counter, config} ->
        simulate_packet_counter(profile_data, config, device_state, current_time)
        
      {:error_counter, config} ->
        simulate_error_counter(profile_data, config, device_state, current_time)
        
      {:utilization_gauge, config} ->
        simulate_utilization_gauge(profile_data, config, device_state, current_time)
        
      {:cpu_gauge, config} ->
        simulate_cpu_gauge(profile_data, config, device_state, current_time)
        
      {:power_gauge, config} ->
        simulate_power_gauge(profile_data, config, device_state, current_time)
        
      {:snr_gauge, config} ->
        simulate_snr_gauge(profile_data, config, device_state, current_time)
        
      {:signal_gauge, config} ->
        simulate_signal_gauge(profile_data, config, device_state, current_time)
        
      {:temperature_gauge, config} ->
        simulate_temperature_gauge(profile_data, config, device_state, current_time)
        
      {:uptime_counter, config} ->
        simulate_uptime_counter(profile_data, config, device_state, current_time)
        
      {:status_enum, config} ->
        simulate_status_enum(profile_data, config, device_state, current_time)
        
      {:static_value, _config} ->
        # Return the original value from the profile
        format_static_value(profile_data)
        
      _ ->
        # Unknown behavior, return static value
        format_static_value(profile_data)
    end
  end

  # Traffic Counter Simulation
  defp simulate_traffic_counter(profile_data, config, device_state, current_time) do
    base_value = get_base_counter_value(profile_data)
    uptime_seconds = Map.get(device_state, :uptime, 0)
    
    # Calculate rate based on time of day and utilization patterns
    daily_factor = TimePatterns.get_daily_utilization_pattern(current_time)
    interface_utilization = Map.get(device_state, :interface_utilization, 0.3)
    
    # Base rate configuration
    {min_rate, max_rate} = Map.get(config, :rate_range, {1000, 10_000_000})
    
    # Calculate current rate
    base_rate = min_rate + (max_rate - min_rate) * interface_utilization * daily_factor
    
    # Add realistic variance and bursts
    variance = add_realistic_variance(base_rate, config)
    burst_factor = apply_burst_pattern(config, current_time)
    
    current_rate = base_rate * variance * burst_factor
    
    # Calculate total increment based on uptime
    total_increment = trunc(current_rate * uptime_seconds)
    
    # Apply counter wrapping for 32-bit counters
    final_value = apply_counter_wrapping(base_value + total_increment, profile_data.type)
    
    format_counter_value(final_value, profile_data.type)
  end

  # Packet Counter Simulation  
  defp simulate_packet_counter(profile_data, config, device_state, current_time) do
    base_value = get_base_counter_value(profile_data)
    uptime_seconds = Map.get(device_state, :uptime, 0)
    
    # Packet counters often correlate with traffic counters
    correlation_oid = Map.get(config, :correlation_with)
    correlation_factor = get_correlation_factor(correlation_oid, device_state)
    
    # Base packet rate
    {min_pps, max_pps} = Map.get(config, :rate_range, {10, 100_000})
    daily_factor = TimePatterns.get_daily_utilization_pattern(current_time)
    
    base_pps = min_pps + (max_pps - min_pps) * daily_factor * correlation_factor
    
    # Add packet-specific variance (more bursty than byte counters)
    packet_variance = add_packet_variance(base_pps, config)
    
    total_packets = trunc(base_pps * packet_variance * uptime_seconds)
    final_value = apply_counter_wrapping(base_value + total_packets, profile_data.type)
    
    format_counter_value(final_value, profile_data.type)
  end

  # Error Counter Simulation
  defp simulate_error_counter(profile_data, config, device_state, current_time) do
    base_value = get_base_counter_value(profile_data)
    uptime_seconds = Map.get(device_state, :uptime, 0)
    
    # Error rates correlate with utilization and environmental factors
    utilization = Map.get(device_state, :interface_utilization, 0.3)
    signal_quality = Map.get(device_state, :signal_quality, 1.0)
    
    # Base error rate (much lower than traffic)
    {min_rate, max_rate} = Map.get(config, :rate_range, {0, 100})
    
    # Higher utilization and poor signal quality increase errors
    error_factor = (utilization * 0.7) + ((1.0 - signal_quality) * 0.3)
    base_error_rate = min_rate + (max_rate - min_rate) * error_factor
    
    # Sporadic burst patterns for errors
    burst_probability = Map.get(config, :error_burst_probability, 0.05)
    burst_factor = if :rand.uniform() < burst_probability, do: 10, else: 1
    
    current_error_rate = base_error_rate * burst_factor
    total_errors = trunc(current_error_rate * uptime_seconds / 3600)  # Errors per hour
    
    final_value = apply_counter_wrapping(base_value + total_errors, profile_data.type)
    format_counter_value(final_value, profile_data.type)
  end

  # Utilization Gauge Simulation
  defp simulate_utilization_gauge(profile_data, config, device_state, current_time) do
    base_value = get_base_gauge_value(profile_data)
    
    # Get daily utilization pattern
    daily_pattern = TimePatterns.get_daily_utilization_pattern(current_time)
    
    # Apply weekly patterns (weekends are typically different)
    weekly_factor = TimePatterns.get_weekly_pattern(current_time)
    
    # Device-specific factors
    device_factor = Map.get(device_state, :utilization_bias, 1.0)
    
    # Calculate current utilization
    target_utilization = base_value * daily_pattern * weekly_factor * device_factor
    
    # Apply smooth transitions and variance
    current_utilization = apply_smooth_transition(target_utilization, device_state, config)
    
    # Clamp to valid range
    clamped_value = max(0, min(100, current_utilization))
    
    format_gauge_value(clamped_value, profile_data.type)
  end

  # CPU Gauge Simulation
  defp simulate_cpu_gauge(profile_data, config, device_state, current_time) do
    base_cpu = get_base_gauge_value(profile_data)
    
    # CPU usage often correlates with network activity
    network_utilization = Map.get(device_state, :interface_utilization, 0.3)
    
    # Time-based patterns
    daily_factor = TimePatterns.get_daily_utilization_pattern(current_time)
    
    # CPU has different patterns than network utilization
    cpu_factor = 0.3 + (network_utilization * 0.4) + (daily_factor * 0.3)
    
    # Add CPU-specific spikes
    spike_probability = 0.02
    spike_factor = if :rand.uniform() < spike_probability, do: 2.0, else: 1.0
    
    current_cpu = base_cpu * cpu_factor * spike_factor
    clamped_cpu = max(0, min(100, current_cpu))
    
    format_gauge_value(clamped_cpu, profile_data.type)
  end

  # Power Gauge Simulation (DOCSIS)
  defp simulate_power_gauge(profile_data, config, device_state, current_time) do
    base_power = get_base_gauge_value(profile_data)
    
    # Power levels affected by signal quality and environmental factors
    signal_quality = Map.get(device_state, :signal_quality, 1.0)
    temperature = Map.get(device_state, :temperature, 25.0)
    
    # Environmental correlation
    temp_factor = 1.0 + (temperature - 25.0) * 0.01  # 1% per degree
    
    # Signal quality correlation
    quality_factor = 0.8 + (signal_quality * 0.4)
    
    # Weather patterns (simplified)
    weather_factor = TimePatterns.apply_weather_variation(current_time)
    
    current_power = base_power * temp_factor * quality_factor * weather_factor
    
    # Apply power level constraints
    {min_power, max_power} = Map.get(config, :range, {-15, 15})
    clamped_power = max(min_power, min(max_power, current_power))
    
    format_gauge_value(clamped_power, profile_data.type)
  end

  # SNR Gauge Simulation
  defp simulate_snr_gauge(profile_data, config, device_state, current_time) do
    base_snr = get_base_gauge_value(profile_data)
    
    # SNR inversely correlates with utilization and environmental factors
    utilization = Map.get(device_state, :interface_utilization, 0.3)
    
    # Higher utilization typically means lower SNR
    utilization_impact = 1.0 - (utilization * 0.2)
    
    # Weather and environmental impact
    weather_factor = TimePatterns.apply_weather_variation(current_time)
    environmental_factor = 0.9 + (weather_factor * 0.2)
    
    # Add realistic noise
    noise_factor = 0.95 + (:rand.uniform() * 0.1)
    
    current_snr = base_snr * utilization_impact * environmental_factor * noise_factor
    
    # SNR typically ranges from 10-40 dB
    clamped_snr = max(10, min(40, current_snr))
    
    format_gauge_value(clamped_snr, profile_data.type)
  end

  # Signal Gauge Simulation
  defp simulate_signal_gauge(profile_data, config, device_state, current_time) do
    base_signal = get_base_gauge_value(profile_data)
    
    # Signal strength varies with environmental conditions
    weather_impact = TimePatterns.apply_weather_variation(current_time)
    distance_factor = Map.get(device_state, :distance_factor, 1.0)
    
    # Signal degrades with distance and weather
    signal_factor = weather_impact * distance_factor
    
    current_signal = base_signal * signal_factor
    
    # Apply signal-specific constraints
    {min_signal, max_signal} = Map.get(config, :range, {-20, 20})
    clamped_signal = max(min_signal, min(max_signal, current_signal))
    
    format_gauge_value(clamped_signal, profile_data.type)
  end

  # Temperature Gauge Simulation
  defp simulate_temperature_gauge(profile_data, config, device_state, current_time) do
    base_temp = get_base_gauge_value(profile_data)
    
    # Temperature varies with time of day and seasonal patterns
    daily_temp_variation = TimePatterns.get_daily_temperature_pattern(current_time)
    seasonal_variation = TimePatterns.get_seasonal_temperature_pattern(current_time)
    
    # Device load affects internal temperature
    cpu_load = Map.get(device_state, :cpu_utilization, 0.3)
    load_factor = 1.0 + (cpu_load * 0.1)  # 10% increase at full load
    
    current_temp = base_temp + daily_temp_variation + seasonal_variation
    current_temp = current_temp * load_factor
    
    # Reasonable temperature range
    clamped_temp = max(-10, min(85, current_temp))
    
    format_gauge_value(clamped_temp, profile_data.type)
  end

  # Uptime Counter Simulation
  defp simulate_uptime_counter(profile_data, _config, device_state, _current_time) do
    uptime_seconds = Map.get(device_state, :uptime, 0)
    
    # SNMP sysUpTime is in TimeTicks (1/100th of a second)
    uptime_timeticks = uptime_seconds * 100
    
    # Apply 32-bit wrapping for TimeTicks
    wrapped_timeticks = rem(uptime_timeticks, 4_294_967_296)
    
    {:timeticks, wrapped_timeticks}
  end

  # Status Enumeration Simulation
  defp simulate_status_enum(profile_data, config, device_state, _current_time) do
    base_status = get_base_enum_value(profile_data)
    
    # Status can change based on device health
    device_health = Map.get(device_state, :health_score, 1.0)
    error_rate = Map.get(device_state, :error_rate, 0.0)
    
    # Determine current status based on health metrics
    current_status = case {device_health, error_rate} do
      {health, _} when health < 0.5 -> "down"
      {_, error} when error > 0.1 -> "degraded"  
      {health, _} when health >= 0.9 -> "up"
      _ -> base_status
    end
    
    format_enum_value(current_status, profile_data.type)
  end

  # Helper Functions

  defp get_base_counter_value(profile_data) do
    case profile_data.value do
      value when is_integer(value) -> value
      _ -> 0
    end
  end

  defp get_base_gauge_value(profile_data) do
    case profile_data.value do
      value when is_number(value) -> value
      _ -> 50.0  # Default gauge value
    end
  end

  defp get_base_enum_value(profile_data) do
    case profile_data.value do
      value when is_binary(value) -> value
      value when is_integer(value) -> value
      _ -> "up"
    end
  end

  defp add_realistic_variance(base_rate, config) do
    variance_factor = Map.get(config, :variance, 0.1)
    1.0 + ((:rand.uniform() - 0.5) * 2 * variance_factor)
  end

  defp add_packet_variance(base_pps, _config) do
    # Packet counters are more bursty than byte counters
    burst_factor = :rand.uniform() * 0.3 + 0.85  # 85% to 115%
    burst_factor
  end

  defp apply_burst_pattern(config, current_time) do
    burst_probability = Map.get(config, :burst_probability, 0.1)
    
    # Check if we're in a burst period (simplified)
    minute = current_time.minute
    if rem(minute, 10) == 0 and :rand.uniform() < burst_probability do
      2.0  # 2x burst
    else
      1.0
    end
  end

  defp get_correlation_factor(nil, _device_state), do: 1.0
  defp get_correlation_factor(correlation_oid, device_state) do
    # Get value from correlated OID (simplified)
    Map.get(device_state, :correlation_factors, %{})
    |> Map.get(correlation_oid, 1.0)
  end

  defp apply_smooth_transition(target_value, device_state, _config) do
    previous_value = Map.get(device_state, :previous_utilization, target_value)
    
    # Smooth transition to prevent abrupt changes
    smoothing_factor = 0.1
    previous_value + (target_value - previous_value) * smoothing_factor
  end

  defp apply_counter_wrapping(value, type) do
    case String.downcase(type) do
      "counter32" -> rem(value, 4_294_967_296)  # 2^32
      "counter64" -> rem(value, 18_446_744_073_709_551_616)  # 2^64
      _ -> value
    end
  end

  defp format_static_value(profile_data) do
    case String.downcase(profile_data.type) do
      "counter32" -> {:counter32, profile_data.value}
      "counter64" -> {:counter64, profile_data.value}
      "gauge32" -> {:gauge32, profile_data.value}
      "gauge" -> {:gauge32, profile_data.value}
      "timeticks" -> {:timeticks, profile_data.value}
      "integer" -> profile_data.value
      _ -> to_string(profile_data.value)
    end
  end

  defp format_counter_value(value, type) do
    case String.downcase(type) do
      "counter32" -> {:counter32, value}
      "counter64" -> {:counter64, value}
      _ -> value
    end
  end

  defp format_gauge_value(value, type) do
    case String.downcase(type) do
      "gauge32" -> {:gauge32, trunc(value)}
      "gauge" -> {:gauge32, trunc(value)}
      _ -> trunc(value)
    end
  end

  defp format_enum_value(value, _type) do
    case value do
      value when is_binary(value) -> value
      value when is_integer(value) -> value
      _ -> to_string(value)
    end
  end
end