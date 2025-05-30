defmodule SNMPSimEx.CorrelationEngine do
  @moduledoc """
  Implement realistic correlations between different metrics.
  
  Network metrics don't exist in isolation - they influence each other in predictable ways:
  - Signal quality degrades with higher utilization
  - Error rates increase with poor signal quality
  - Temperature affects equipment performance
  - Power consumption correlates with activity levels
  
  This module provides sophisticated correlation modeling for authentic network simulation.
  """
  
  alias SnmpSimEx.TimePatterns
  
  @type correlation_type :: 
    :positive |     # Metrics increase together
    :negative |     # One increases as other decreases
    :threshold |    # Step change at threshold
    :exponential |  # Exponential relationship
    :logarithmic    # Logarithmic relationship
  
  @type correlation_config :: %{
    type: correlation_type(),
    strength: float(),        # 0.0-1.0
    delay_seconds: integer(), # Lag time between metrics
    threshold: float(),       # For threshold correlations
    noise_factor: float()     # Random variation 0.0-1.0
  }
  
  @doc """
  Apply correlations to a device's metrics based on primary metric changes.
  
  ## Examples
  
      device_state = %{
        interface_utilization: 0.8,
        signal_quality: 85.0,
        temperature: 45.0
      }
      
      correlations = [
        {:interface_utilization, :error_rate, :positive, 0.7},
        {:signal_quality, :throughput, :positive, 0.9},
        {:temperature, :cpu_usage, :positive, 0.6}
      ]
      
      updated_state = SNMPSimEx.CorrelationEngine.apply_correlations(
        :interface_utilization, 0.8, device_state, correlations, DateTime.utc_now()
      )
      
  """
  @spec apply_correlations(atom(), number(), map(), list(), DateTime.t()) :: map()
  def apply_correlations(primary_oid, primary_value, device_state, correlations, current_time) do
    # Find all correlations involving the primary OID
    relevant_correlations = Enum.filter(correlations, fn
      {^primary_oid, _secondary, _type, _strength} -> true
      {_primary, ^primary_oid, _type, _strength} -> true
      _ -> false
    end)
    
    # Apply each correlation
    Enum.reduce(relevant_correlations, device_state, fn correlation, state_acc ->
      apply_single_correlation(primary_oid, primary_value, correlation, state_acc, current_time)
    end)
  end
  
  @doc """
  Get standard correlation configurations for common device types.
  
  ## Examples
  
      correlations = SNMPSimEx.CorrelationEngine.get_device_correlations(:cable_modem)
      
  """
  @spec get_device_correlations(atom()) :: list()
  def get_device_correlations(device_type) do
    case device_type do
      :cable_modem ->
        cable_modem_correlations()
        
      :mta ->
        mta_correlations()
        
      :switch ->
        switch_correlations()
        
      :router ->
        router_correlations()
        
      :cmts ->
        cmts_correlations()
        
      :server ->
        server_correlations()
        
      _ ->
        generic_correlations()
    end
  end
  
  @doc """
  Calculate signal quality impact on throughput for DOCSIS devices.
  
  Signal quality (SNR, power levels) directly affects achievable throughput
  in cable modem systems.
  """
  @spec calculate_signal_throughput_correlation(float(), float(), float()) :: float()
  def calculate_signal_throughput_correlation(snr_db, power_level_dbmv, max_throughput) do
    # SNR impact (minimum 20 dB for stable operation)
    snr_factor = cond do
      snr_db >= 35 -> 1.0        # Excellent signal
      snr_db >= 30 -> 0.95       # Good signal
      snr_db >= 25 -> 0.85       # Adequate signal
      snr_db >= 20 -> 0.70       # Marginal signal
      true -> 0.30               # Poor signal
    end
    
    # Power level impact (optimal range: -7 to +7 dBmV)
    power_factor = cond do
      power_level_dbmv >= -7 and power_level_dbmv <= 7 -> 1.0   # Optimal
      power_level_dbmv >= -10 and power_level_dbmv <= 10 -> 0.9 # Good
      power_level_dbmv >= -15 and power_level_dbmv <= 15 -> 0.7 # Marginal
      true -> 0.4                                                # Poor
    end
    
    # Combined impact with some random variation
    base_throughput = max_throughput * snr_factor * power_factor
    variation = 1.0 + ((:rand.uniform() - 0.5) * 0.1)  # ±5% variation
    
    base_throughput * variation
  end
  
  @doc """
  Calculate utilization impact on error rates.
  
  Higher utilization typically leads to increased error rates due to:
  - Buffer overflows
  - Increased collision probability
  - Thermal effects
  """
  @spec calculate_utilization_error_correlation(float(), atom()) :: float()
  def calculate_utilization_error_correlation(utilization_percent, interface_type) do
    # Base error rates by interface type
    base_error_rate = case interface_type do
      :ethernet_gigabit -> 0.00001   # Very low base error rate
      :ethernet_100mb -> 0.0001      # Low base error rate
      :docsis -> 0.001               # Higher base error rate (wireless/cable)
      :wifi -> 0.005                 # Higher base error rate (wireless)
      _ -> 0.001                     # Default
    end
    
    # Utilization factor (exponential increase)
    utilization_factor = utilization_percent / 100.0
    
    # Error rate increases exponentially with utilization
    utilization_multiplier = :math.pow(utilization_factor, 2) * 10
    
    # Apply interface-specific scaling
    interface_scaling = case interface_type do
      :wifi -> 3.0          # Wireless is more sensitive to utilization
      :docsis -> 2.0        # Cable modems somewhat sensitive
      _ -> 1.0              # Wired interfaces are most stable
    end
    
    final_error_rate = base_error_rate * (1 + utilization_multiplier * interface_scaling)
    
    # Cap at reasonable maximum (10% error rate)
    min(0.1, final_error_rate)
  end
  
  @doc """
  Calculate temperature impact on equipment performance.
  
  Higher temperatures affect:
  - CPU performance (thermal throttling)
  - Signal quality (thermal noise)
  - Error rates (increased bit errors)
  """
  @spec calculate_temperature_performance_correlation(float(), atom()) :: %{
    cpu_impact: float(),
    signal_impact: float(),
    error_impact: float()
  }
  def calculate_temperature_performance_correlation(temperature_celsius, equipment_type) do
    # Operating temperature ranges by equipment type
    {optimal_temp, warning_temp, critical_temp} = case equipment_type do
      :cable_modem -> {25.0, 60.0, 75.0}   # Consumer equipment
      :switch -> {20.0, 50.0, 65.0}        # Network equipment
      :router -> {20.0, 50.0, 65.0}        # Network equipment
      :server -> {18.0, 45.0, 60.0}        # Server equipment
      :cmts -> {15.0, 40.0, 55.0}          # Data center equipment
      _ -> {25.0, 50.0, 70.0}               # Generic
    end
    
    # CPU impact (thermal throttling)
    cpu_impact = cond do
      temperature_celsius <= optimal_temp -> 1.0
      temperature_celsius <= warning_temp -> 
        1.0 - ((temperature_celsius - optimal_temp) / (warning_temp - optimal_temp)) * 0.2
      temperature_celsius <= critical_temp ->
        0.8 - ((temperature_celsius - warning_temp) / (critical_temp - warning_temp)) * 0.6
      true -> 0.2  # Severe throttling
    end
    
    # Signal quality impact (thermal noise)
    signal_impact = cond do
      temperature_celsius <= optimal_temp -> 1.0
      temperature_celsius <= warning_temp ->
        1.0 - ((temperature_celsius - optimal_temp) / (warning_temp - optimal_temp)) * 0.1
      temperature_celsius <= critical_temp ->
        0.9 - ((temperature_celsius - warning_temp) / (critical_temp - warning_temp)) * 0.4
      true -> 0.5  # Significant signal degradation
    end
    
    # Error rate impact (exponential increase with temperature)
    temp_excess = max(0, temperature_celsius - optimal_temp)
    error_multiplier = 1.0 + :math.pow(temp_excess / 20.0, 2)
    
    %{
      cpu_impact: cpu_impact,
      signal_impact: signal_impact,
      error_impact: error_multiplier
    }
  end
  
  @doc """
  Model power consumption correlations with activity and temperature.
  
  Power consumption correlates with:
  - CPU utilization
  - Network activity
  - Temperature (cooling requirements)
  """
  @spec calculate_power_consumption_correlation(map(), atom()) :: float()
  def calculate_power_consumption_correlation(device_metrics, device_type) do
    cpu_utilization = Map.get(device_metrics, :cpu_utilization, 0.0) / 100.0
    network_utilization = Map.get(device_metrics, :interface_utilization, 0.0)
    temperature = Map.get(device_metrics, :temperature, 25.0)
    
    # Base power consumption by device type (watts)
    base_power = case device_type do
      :cable_modem -> 12.0
      :mta -> 8.0
      :switch -> 45.0
      :router -> 35.0
      :cmts -> 500.0
      :server -> 200.0
      _ -> 25.0
    end
    
    # CPU impact on power
    cpu_power = base_power * 0.4 * cpu_utilization  # Up to 40% increase
    
    # Network activity impact
    network_power = base_power * 0.2 * network_utilization  # Up to 20% increase
    
    # Temperature impact (cooling requirements)
    temp_excess = max(0, temperature - 25.0)  # Above 25°C needs cooling
    cooling_power = temp_excess * 0.8  # ~0.8W per degree above 25°C
    
    total_power = base_power + cpu_power + network_power + cooling_power
    
    # Add some random variation
    variation = 1.0 + ((:rand.uniform() - 0.5) * 0.1)  # ±5% variation
    
    total_power * variation
  end
  
  # Private helper functions
  
  defp apply_single_correlation(primary_oid, primary_value, correlation, device_state, current_time) do
    {primary_metric, secondary_metric, correlation_type, strength} = correlation
    
    # Determine if we're updating the secondary metric
    secondary_oid = if primary_metric == primary_oid, do: secondary_metric, else: primary_metric
    
    # Skip if the secondary metric doesn't exist in device state
    if not Map.has_key?(device_state, secondary_oid) do
      device_state
    else
      # Calculate new secondary value based on correlation
      current_secondary = Map.get(device_state, secondary_oid)
      new_secondary_value = calculate_correlated_value(
        primary_value, current_secondary, correlation_type, strength, 
        primary_oid, secondary_oid, current_time
      )
      
      Map.put(device_state, secondary_oid, new_secondary_value)
    end
  end
  
  defp calculate_correlated_value(primary_value, current_secondary, correlation_type, strength, 
                                  primary_oid, secondary_oid, current_time) do
    # Base correlation calculation
    base_correlation = case correlation_type do
      :positive ->
        # Positive correlation: both increase together
        change_factor = (primary_value - 50) / 50  # Normalize around 50
        current_secondary * (1 + change_factor * strength * 0.1)
        
      :negative ->
        # Negative correlation: one increases as other decreases
        change_factor = (primary_value - 50) / 50
        current_secondary * (1 - change_factor * strength * 0.1)
        
      :threshold ->
        # Threshold correlation: step change at specific value
        threshold = get_threshold_value(primary_oid, secondary_oid)
        if primary_value > threshold do
          current_secondary * (1 + strength)
        else
          current_secondary * (1 - strength * 0.5)
        end
        
      :exponential ->
        # Exponential correlation: exponential relationship
        normalized_primary = primary_value / 100.0
        base_value = get_base_value(secondary_oid)
        base_value * :math.pow(normalized_primary, strength * 2)
        
      :logarithmic ->
        # Logarithmic correlation: logarithmic relationship
        normalized_primary = max(0.01, primary_value / 100.0)
        base_value = get_base_value(secondary_oid)
        base_value * (1 + strength * :math.log(normalized_primary))
    end
    
    # Apply time-based factors
    time_factor = TimePatterns.get_daily_utilization_pattern(current_time)
    time_adjusted = base_correlation * time_factor
    
    # Add realistic noise
    noise_factor = 0.05  # 5% noise
    noise = 1.0 + ((:rand.uniform() - 0.5) * 2 * noise_factor)
    
    final_value = time_adjusted * noise
    
    # Apply bounds checking
    apply_value_bounds(final_value, secondary_oid)
  end
  
  defp get_threshold_value(primary_oid, secondary_oid) do
    # Define threshold values for common correlations
    case {primary_oid, secondary_oid} do
      {:interface_utilization, :error_rate} -> 70.0  # 70% utilization threshold
      {:temperature, :cpu_usage} -> 60.0             # 60°C temperature threshold
      {:signal_quality, :throughput} -> 25.0         # 25 dB SNR threshold
      _ -> 50.0  # Default threshold
    end
  end
  
  defp get_base_value(secondary_oid) do
    # Define base values for metrics
    case secondary_oid do
      :error_rate -> 0.001          # 0.1% base error rate
      :cpu_usage -> 15.0            # 15% base CPU usage
      :throughput -> 10_000_000     # 10 Mbps base throughput
      :temperature -> 25.0          # 25°C base temperature
      :power_consumption -> 50.0    # 50W base power
      _ -> 50.0                     # Default base value
    end
  end
  
  defp apply_value_bounds(value, metric_oid) do
    # Apply realistic bounds to prevent impossible values
    case metric_oid do
      :error_rate ->
        max(0.0, min(1.0, value))        # 0-100%
      :cpu_usage ->
        max(0.0, min(100.0, value))      # 0-100%
      :interface_utilization ->
        max(0.0, min(100.0, value))      # 0-100%
      :temperature ->
        max(-10.0, min(100.0, value))    # -10°C to 100°C
      :signal_quality ->
        max(0.0, min(100.0, value))      # 0-100%
      :power_consumption ->
        max(0.0, value)                  # Non-negative power
      :throughput ->
        max(0.0, value)                  # Non-negative throughput
      _ ->
        max(0.0, value)                  # Default: non-negative
    end
  end
  
  # Device-specific correlation configurations
  
  defp cable_modem_correlations do
    [
      # Signal quality affects throughput
      {:signal_quality, :throughput, :exponential, 0.85},
      # Utilization increases error rates
      {:interface_utilization, :error_rate, :exponential, 0.70},
      # Temperature affects signal quality
      {:temperature, :signal_quality, :negative, 0.60},
      # Power consumption correlates with activity
      {:interface_utilization, :power_consumption, :positive, 0.75},
      # SNR affects error rates
      {:signal_quality, :error_rate, :negative, 0.80}
    ]
  end
  
  defp mta_correlations do
    [
      # Voice quality metrics
      {:signal_quality, :jitter, :negative, 0.70},
      {:interface_utilization, :packet_loss, :exponential, 0.60},
      {:temperature, :signal_quality, :negative, 0.50},
      # Power and thermal
      {:cpu_usage, :temperature, :positive, 0.65},
      {:temperature, :power_consumption, :positive, 0.55}
    ]
  end
  
  defp switch_correlations do
    [
      # Network performance
      {:interface_utilization, :error_rate, :exponential, 0.60},
      {:cpu_usage, :interface_utilization, :positive, 0.70},
      # Thermal management
      {:cpu_usage, :temperature, :positive, 0.75},
      {:temperature, :fan_speed, :positive, 0.90},
      # Power correlations
      {:cpu_usage, :power_consumption, :positive, 0.80},
      {:interface_utilization, :power_consumption, :positive, 0.65}
    ]
  end
  
  defp router_correlations do
    [
      # Routing performance
      {:cpu_usage, :routing_table_misses, :positive, 0.65},
      {:interface_utilization, :cpu_usage, :positive, 0.70},
      # Error correlations
      {:interface_utilization, :error_rate, :threshold, 0.75},
      # Thermal and power
      {:cpu_usage, :temperature, :positive, 0.80},
      {:temperature, :power_consumption, :positive, 0.70}
    ]
  end
  
  defp cmts_correlations do
    [
      # Aggregation effects
      {:downstream_utilization, :upstream_utilization, :positive, 0.60},
      {:total_modems_online, :cpu_usage, :positive, 0.85},
      # Signal aggregation
      {:average_snr, :total_throughput, :positive, 0.90},
      # Thermal management (critical for CMTS)
      {:cpu_usage, :temperature, :positive, 0.90},
      {:temperature, :power_consumption, :positive, 0.85}
    ]
  end
  
  defp server_correlations do
    [
      # Server performance
      {:cpu_usage, :memory_usage, :positive, 0.75},
      {:memory_usage, :disk_io, :positive, 0.60},
      {:network_utilization, :cpu_usage, :positive, 0.65},
      # Thermal and power (critical for servers)
      {:cpu_usage, :temperature, :positive, 0.85},
      {:memory_usage, :temperature, :positive, 0.50},
      {:temperature, :power_consumption, :positive, 0.80}
    ]
  end
  
  defp generic_correlations do
    [
      # Basic correlations for unknown device types
      {:interface_utilization, :error_rate, :positive, 0.50},
      {:cpu_usage, :temperature, :positive, 0.60},
      {:temperature, :power_consumption, :positive, 0.55}
    ]
  end
end