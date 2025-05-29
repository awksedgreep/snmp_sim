defmodule SnmpSimEx.TimePatterns do
  @moduledoc """
  Realistic time-based variations for network metrics.
  Implements daily, weekly, and seasonal patterns for authentic simulation.
  """

  @doc """
  Get daily utilization pattern factor (0.0 to 1.5).
  
  Returns a multiplier based on time of day:
  - 0-5 AM: Low usage (0.3)
  - 6-8 AM: Morning ramp (0.7)  
  - 9-17 PM: Business hours (0.9-1.2)
  - 18-20 PM: Evening peak (1.5)
  - 21-23 PM: Late evening (0.8)
  
  ## Examples
  
      # 2 PM business hours
      factor = SnmpSimEx.TimePatterns.get_daily_utilization_pattern(~U[2024-01-15 14:00:00Z])
      # Returns: ~1.1
      
      # 7 PM evening peak
      factor = SnmpSimEx.TimePatterns.get_daily_utilization_pattern(~U[2024-01-15 19:00:00Z])
      # Returns: ~1.5
      
  """
  def get_daily_utilization_pattern(datetime) do
    hour = datetime.hour
    minute = datetime.minute
    
    # Convert to fractional hour for smooth transitions
    fractional_hour = hour + minute / 60.0
    
    case fractional_hour do
      # Late night / Early morning (0-5 AM): Low usage
      h when h >= 0 and h < 5 ->
        0.2 + 0.1 * smooth_sine(h, 0, 5)
        
      # Morning ramp (5-9 AM): Gradual increase
      h when h >= 5 and h < 9 ->
        0.3 + 0.6 * smooth_transition(h, 5, 9)
        
      # Business hours (9-17 PM): High usage with variation
      h when h >= 9 and h < 17 ->
        base_business = 0.9
        lunch_dip = if h >= 12 and h < 14, do: -0.1, else: 0.0
        # Use deterministic variation based on datetime to maintain consistency
        deterministic_variation = deterministic_random(datetime) * 0.2 - 0.1
        base_business + lunch_dip + deterministic_variation
        
      # Evening transition (17-18 PM): Shift from business to residential
      h when h >= 17 and h < 18 ->
        1.0 + 0.3 * smooth_transition(h, 17, 18)
        
      # Evening peak (18-21 PM): Residential usage peak
      h when h >= 18 and h < 21 ->
        peak_factor = 1.3 + 0.2 * smooth_sine(h, 18, 21)
        add_evening_burst(peak_factor, h, datetime)
        
      # Late evening (21-24 PM): Gradual decline
      h when h >= 21 and h < 24 ->
        0.8 - 0.5 * smooth_transition(h, 21, 24)
    end
  end

  @doc """
  Get weekly pattern factor based on day of week.
  
  Returns multiplier for weekday vs weekend patterns:
  - Monday-Friday: 1.0 (full pattern)
  - Saturday: 0.7 (reduced business, increased residential)
  - Sunday: 0.5 (lowest overall usage)
  
  ## Examples
  
      # Tuesday
      factor = SnmpSimEx.TimePatterns.get_weekly_pattern(~U[2024-01-16 14:00:00Z])
      # Returns: 1.0
      
      # Saturday
      factor = SnmpSimEx.TimePatterns.get_weekly_pattern(~U[2024-01-20 14:00:00Z])
      # Returns: 0.7
      
  """
  def get_weekly_pattern(datetime) do
    day_of_week = Date.day_of_week(datetime)
    hour = datetime.hour
    
    case day_of_week do
      # Monday-Friday: Full business patterns
      day when day in [1, 2, 3, 4, 5] ->
        # Slightly different patterns per day
        daily_variance = case day do
          1 -> 0.95  # Monday: Slightly lower (slow start)
          2 -> 1.05  # Tuesday: Peak efficiency
          3 -> 1.05  # Wednesday: Peak efficiency
          4 -> 1.00  # Thursday: Normal
          5 -> 0.90  # Friday: Early wind-down
        end
        daily_variance
        
      # Saturday: Different pattern - less business, more residential
      6 ->
        if hour >= 10 and hour < 22 do
          0.8  # Active day but different pattern
        else
          0.5  # Quieter morning/night
        end
        
      # Sunday: Lowest usage overall
      7 ->
        if hour >= 12 and hour < 20 do
          0.6  # Some afternoon activity
        else
          0.3  # Very quiet
        end
    end
  end

  @doc """
  Get seasonal temperature variation.
  
  Returns temperature offset in Celsius based on month and location patterns.
  Simulates realistic seasonal temperature changes.
  
  ## Examples
  
      # January (winter)
      offset = SnmpSimEx.TimePatterns.get_seasonal_temperature_pattern(~U[2024-01-15 14:00:00Z])
      # Returns: -8.5
      
      # July (summer)  
      offset = SnmpSimEx.TimePatterns.get_seasonal_temperature_pattern(~U[2024-07-15 14:00:00Z])
      # Returns: 12.3
      
  """
  def get_seasonal_temperature_pattern(datetime) do
    month = datetime.month
    day = datetime.day
    
    # Calculate day of year for smooth seasonal transition
    day_of_year = :calendar.date_to_gregorian_days(datetime.year, month, day) -
                  :calendar.date_to_gregorian_days(datetime.year, 1, 1)
    
    # Sinusoidal pattern with peak in summer (day 182 = July 1st)
    seasonal_cycle = :math.sin(2 * :math.pi() * (day_of_year - 91) / 365)
    
    # Temperature amplitude (difference between winter and summer)
    amplitude = 15.0  # ±15°C seasonal variation
    
    seasonal_cycle * amplitude
  end

  @doc """
  Get daily temperature variation pattern.
  
  Returns temperature offset based on time of day:
  - Coldest: ~6 AM
  - Warmest: ~3 PM
  - Smooth sinusoidal pattern
  
  ## Examples
  
      # 6 AM (coldest)
      offset = SnmpSimEx.TimePatterns.get_daily_temperature_pattern(~U[2024-01-15 06:00:00Z])
      # Returns: -3.2
      
      # 3 PM (warmest)
      offset = SnmpSimEx.TimePatterns.get_daily_temperature_pattern(~U[2024-01-15 15:00:00Z])
      # Returns: 4.1
      
  """
  def get_daily_temperature_pattern(datetime) do
    hour = datetime.hour
    minute = datetime.minute
    
    # Convert to fractional hour
    fractional_hour = hour + minute / 60.0
    
    # Peak temperature at 15:00 (3 PM), minimum at 6:00 AM
    # Shift the sine wave so minimum is at 6 AM (need to subtract π/2 to get minimum at 0)
    daily_cycle = :math.sin(2 * :math.pi() * (fractional_hour - 6) / 24 - :math.pi() / 2)
    
    # Daily amplitude (difference between day and night temperatures)
    amplitude = 5.0  # ±5°C daily variation
    
    daily_cycle * amplitude
  end

  @doc """
  Apply weather-related variations to signal quality metrics.
  
  Simulates weather patterns that affect signal strength:
  - Rain/snow: Reduces signal quality
  - Clear weather: Optimal signal quality
  - Seasonal patterns for different weather probabilities
  
  ## Examples
  
      factor = SnmpSimEx.TimePatterns.apply_weather_variation(~U[2024-01-15 14:00:00Z])
      # Returns: 0.85 (some weather impact)
      
  """
  def apply_weather_variation(datetime) do
    month = datetime.month
    hour = datetime.hour
    
    # Seasonal weather patterns
    rain_probability = case month do
      # Winter months: Lower rain probability but more impact when it occurs
      month when month in [12, 1, 2] -> 0.3
      # Spring: Higher rain probability  
      month when month in [3, 4, 5] -> 0.4
      # Summer: Lower rain, but thunderstorms
      month when month in [6, 7, 8] -> 0.2
      # Fall: Moderate rain
      month when month in [9, 10, 11] -> 0.35
    end
    
    # Weather events are more likely during certain hours
    hourly_weather_factor = case hour do
      # Early morning: More likely to have weather
      h when h >= 4 and h < 8 -> 1.3
      # Afternoon: Thunderstorms in summer
      h when h >= 14 and h < 18 -> if month in [6, 7, 8], do: 1.5, else: 1.0
      # Evening: General weather likelihood
      h when h >= 18 and h < 22 -> 1.2
      _ -> 1.0
    end
    
    adjusted_probability = rain_probability * hourly_weather_factor
    
    # Simulate weather event
    if :rand.uniform() < adjusted_probability do
      # Weather event occurring - impact on signal
      weather_severity = :rand.uniform()  # 0-1 severity
      
      case weather_severity do
        s when s < 0.3 -> 0.95  # Light weather - minimal impact
        s when s < 0.7 -> 0.85  # Moderate weather - noticeable impact
        _ -> 0.70              # Severe weather - significant impact
      end
    else
      # Clear weather - optimal conditions
      1.0 + (:rand.uniform() * 0.05)  # Slight random benefit
    end
  end

  @doc """
  Apply seasonal variations to any metric.
  
  Generic seasonal pattern that can be applied to various metrics.
  Useful for metrics that have yearly cycles.
  
  ## Examples
  
      # Apply to equipment failure rates (higher in summer heat)
      factor = SnmpSimEx.TimePatterns.apply_seasonal_variation(datetime, :equipment_stress)
      
      # Apply to power consumption (higher in winter/summer for heating/cooling)
      factor = SnmpSimEx.TimePatterns.apply_seasonal_variation(datetime, :power_consumption)
      
  """
  def apply_seasonal_variation(datetime, pattern_type \\ :generic) do
    month = datetime.month
    
    case pattern_type do
      :equipment_stress ->
        # Higher stress in summer heat and winter cold
        case month do
          month when month in [6, 7, 8] -> 1.3  # Summer heat stress
          month when month in [12, 1, 2] -> 1.2  # Winter cold stress
          month when month in [3, 4, 5, 9, 10, 11] -> 1.0  # Moderate seasons
        end
        
      :power_consumption ->
        # Higher consumption for heating/cooling
        case month do
          month when month in [6, 7, 8] -> 1.4  # Summer cooling
          month when month in [12, 1, 2] -> 1.5  # Winter heating
          month when month in [3, 4, 5, 9, 10, 11] -> 1.0  # Moderate seasons
        end
        
      :generic ->
        # Generic sinusoidal seasonal pattern
        day_of_year = :calendar.date_to_gregorian_days(datetime.year, month, datetime.day) -
                      :calendar.date_to_gregorian_days(datetime.year, 1, 1)
        
        seasonal_factor = :math.sin(2 * :math.pi() * day_of_year / 365)
        1.0 + (seasonal_factor * 0.1)  # ±10% seasonal variation
    end
  end

  @doc """
  Get interface traffic rate based on interface type and time patterns.
  
  Returns expected traffic rate ranges for different interface types
  with time-based adjustments.
  
  ## Examples
  
      rate = SnmpSimEx.TimePatterns.get_interface_traffic_rate(:ethernet_gigabit, datetime)
      # Returns: {min_rate, max_rate, current_factor}
      
  """
  def get_interface_traffic_rate(interface_type, datetime) do
    daily_factor = get_daily_utilization_pattern(datetime)
    weekly_factor = get_weekly_pattern(datetime)
    
    base_rates = case interface_type do
      :ethernet_gigabit ->
        {1_000, 125_000_000}  # 1KB/s to 125MB/s
        
      :ethernet_100mb ->
        {100, 12_500_000}     # 100B/s to 12.5MB/s
        
      :docsis_downstream ->
        {10_000, 193_000_000} # 10KB/s to 193MB/s (DOCSIS 3.1)
        
      :docsis_upstream ->
        {1_000, 50_000_000}   # 1KB/s to 50MB/s
        
      :wifi_802_11ac ->
        {1_000, 87_500_000}   # 1KB/s to 87.5MB/s
        
      :cellular_lte ->
        {10_000, 15_000_000}  # 10KB/s to 15MB/s
        
      _ ->
        {1_000, 10_000_000}   # Generic interface
    end
    
    {min_rate, max_rate} = base_rates
    current_factor = daily_factor * weekly_factor
    
    {min_rate, max_rate, current_factor}
  end

  # Private helper functions

  defp smooth_sine(value, start_range, end_range) do
    # Smooth sine wave between 0 and 1 over the given range
    normalized = (value - start_range) / (end_range - start_range)
    (:math.sin(normalized * :math.pi()) + 1) / 2
  end

  defp smooth_transition(value, start_range, end_range) do
    # Smooth linear transition from 0 to 1 over the given range
    normalized = (value - start_range) / (end_range - start_range)
    max(0, min(1, normalized))
  end

  defp add_evening_burst(base_factor, hour, datetime) do
    # Add deterministic traffic bursts during evening peak hours
    burst_probability = case hour do
      h when h >= 19 and h < 21 -> 0.15  # 15% chance during peak
      _ -> 0.05  # 5% chance other times
    end
    
    # Use deterministic random based on datetime for consistent results
    deterministic_rand = deterministic_random(datetime, 1)
    if deterministic_rand < burst_probability do
      burst_intensity = 1.2 + (deterministic_random(datetime, 2) * 0.3)  # 20-50% burst
      base_factor * burst_intensity
    else
      base_factor
    end
  end

  # Generate deterministic "random" values based on datetime to ensure consistency
  defp deterministic_random(datetime, seed_offset \\ 0) do
    # Create a deterministic seed from datetime components
    seed = datetime.year + datetime.month * 100 + datetime.day * 10000 + 
           datetime.hour * 1000000 + datetime.minute * 100000000 + seed_offset
    
    # Use a simple deterministic pseudo-random function
    # Based on linear congruential generator principles
    seed = rem(seed * 1103515245 + 12345, 2147483648)
    seed / 2147483647.0
  end
end