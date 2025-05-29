defmodule SNMPSimEx.Device do
  @moduledoc """
  Lightweight Device GenServer for handling SNMP requests.
  Uses shared profiles and minimal device-specific state for scalability.
  
  Features:
  - Minimal memory footprint per device
  - Shared profile data via ETS tables
  - On-demand value simulation
  - Integrated with LazyDevicePool management
  """

  use GenServer
  require Logger

  alias SNMPSimEx.{SharedProfiles, OIDTree, BulkOperations, DeviceDistribution}
  alias SnmpSimEx.Core.{Server, PDU}

  defstruct [
    :device_id,
    :port,
    :device_type,
    :server_pid,
    :mac_address,
    :uptime_start,
    :counters,        # Device-specific counter state
    :gauges,          # Device-specific gauge state  
    :status_vars,     # Device-specific status variables
    :community,
    :last_access      # For tracking access time
  ]

  @default_community "public"

  # SNMP PDU Types
  @get_request 0xA0
  @getnext_request 0xA1
  @get_response 0xA2
  @set_request 0xA3
  @getbulk_request 0xA5

  # SNMP Error Status
  @no_error 0
  @too_big 1
  @no_such_name 2
  @bad_value 3
  @read_only 4
  @gen_err 5

  @doc """
  Start a device with the given device configuration.
  
  ## Device Config
  
  Device config should contain:
  - `:port` - UDP port for the device (required)
  - `:device_type` - Type of device (:cable_modem, :switch, etc.)
  - `:device_id` - Unique device identifier
  - `:community` - SNMP community string (default: "public")
  - `:mac_address` - MAC address (auto-generated if not provided)
  
  ## Examples
  
      device_config = %{
        port: 9001,
        device_type: :cable_modem,
        device_id: "cable_modem_9001",
        community: "public"
      }
      
      {:ok, device} = SNMPSimEx.Device.start_link(device_config)
      
  """
  def start_link(device_config) when is_map(device_config) do
    GenServer.start_link(__MODULE__, device_config)
  end

  @doc """
  Stop a device gracefully.
  """
  def stop(device_pid) when is_pid(device_pid) do
    GenServer.stop(device_pid, :normal)
  end

  @doc """
  Get device information and statistics.
  """
  def get_info(device_pid) do
    GenServer.call(device_pid, :get_info)
  end

  @doc """
  Update device counters manually (useful for testing).
  """
  def update_counter(device_pid, oid, increment) do
    GenServer.call(device_pid, {:update_counter, oid, increment})
  end

  @doc """
  Set a gauge value manually (useful for testing).
  """
  def set_gauge(device_pid, oid, value) do
    GenServer.call(device_pid, {:set_gauge, oid, value})
  end

  @doc """
  Simulate a device reboot.
  """
  def reboot(device_pid) do
    GenServer.call(device_pid, :reboot)
  end

  # GenServer callbacks

  @impl true
  def init(device_config) when is_map(device_config) do
    port = Map.fetch!(device_config, :port)
    device_type = Map.fetch!(device_config, :device_type)
    device_id = Map.fetch!(device_config, :device_id)
    community = Map.get(device_config, :community, @default_community)
    mac_address = Map.get(device_config, :mac_address, generate_mac_address(device_type, port))

    # Start the UDP server for this device  
    case Server.start_link(port, community: community) do
      {:ok, server_pid} ->
        
        state = %__MODULE__{
          device_id: device_id,
          port: port,
          device_type: device_type,
          server_pid: server_pid,
          mac_address: mac_address,
          uptime_start: :erlang.monotonic_time(),
          counters: %{},
          gauges: %{},
          status_vars: %{},
          community: community,
          last_access: System.monotonic_time(:millisecond)
        }
        
        # Set up the SNMP handler for this device
        device_pid = self()
        handler_fn = fn pdu, context ->
          GenServer.call(device_pid, {:handle_snmp, pdu, context})
        end
        :ok = Server.set_device_handler(server_pid, handler_fn)
        
        # Initialize device state from shared profile
        case initialize_device_state(state) do
          {:ok, initialized_state} -> 
            Logger.info("Device #{device_id} started on port #{port}")
            {:ok, initialized_state}
          {:error, reason} -> 
            {:stop, reason}
        end
        
      {:error, reason} ->
        Logger.error("Failed to start UDP server for device #{device_id} on port #{port}: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:get_info, _from, state) when is_map(state) do
    # Get OID count from shared profile
    oid_count = case SharedProfiles.get_profile_info(state.device_type) do
      {:ok, profile_info} -> Map.get(profile_info, :oid_count, 0)
      {:error, _} -> 0
    end
    
    info = %{
      device_id: state.device_id,
      port: state.port,
      device_type: state.device_type,
      mac_address: state.mac_address,
      uptime: calculate_uptime(state),
      oid_count: oid_count,
      counters: map_size(state.counters),
      gauges: map_size(state.gauges),
      status_vars: map_size(state.status_vars),
      last_access: state.last_access
    }
    
    # Update last access time
    new_state = %{state | last_access: System.monotonic_time(:millisecond)}
    {:reply, info, new_state}
  end


  @impl true
  def handle_call({:handle_snmp, pdu, _context}, _from, state) do
    response = process_snmp_pdu(pdu, state)
    {:reply, response, state}
  end

  @impl true
  def handle_call({:update_counter, oid, increment}, _from, state) do
    new_counters = Map.update(state.counters, oid, increment, &(&1 + increment))
    new_state = %{state | counters: new_counters}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:set_gauge, oid, value}, _from, state) do
    new_gauges = Map.put(state.gauges, oid, value)
    new_state = %{state | gauges: new_gauges}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:reboot, _from, state) do
    Logger.info("Device #{state.device_id} rebooting")
    
    new_state = %{state |
      uptime_start: :erlang.monotonic_time(),
      counters: %{},
      gauges: %{},
      status_vars: %{}
    }
    
    case initialize_device_state(new_state) do
      {:ok, initialized_state} -> {:reply, :ok, initialized_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def terminate(reason, %{server_pid: server_pid, device_id: device_id} = _state) when is_pid(server_pid) do
    GenServer.stop(server_pid)
    Logger.info("Device #{device_id} terminated: #{inspect(reason)}")
    :ok
  end

  def terminate(reason, %{device_id: device_id} = _state) do
    Logger.info("Device #{device_id} terminated: #{inspect(reason)}")
    :ok
  end

  def terminate(reason, state) do
    Logger.info("Device terminated with invalid state: #{inspect(reason)}, state: #{inspect(state)}")
    :ok
  end

  # Private functions

  defp process_snmp_pdu(%PDU{pdu_type: @get_request} = pdu, state) do
    variable_bindings = process_get_request(pdu.variable_bindings, state)
    
    response_pdu = %PDU{
      version: pdu.version,
      community: pdu.community,
      pdu_type: @get_response,
      request_id: pdu.request_id,
      error_status: @no_error,
      error_index: 0,
      variable_bindings: variable_bindings
    }
    
    {:ok, response_pdu}
  end

  defp process_snmp_pdu(%PDU{pdu_type: @getnext_request} = pdu, state) do
    variable_bindings = process_getnext_request(pdu.variable_bindings, state)
    
    response_pdu = %PDU{
      version: pdu.version,
      community: pdu.community,
      pdu_type: @get_response,
      request_id: pdu.request_id,
      error_status: @no_error,
      error_index: 0,
      variable_bindings: variable_bindings
    }
    
    {:ok, response_pdu}
  end

  defp process_snmp_pdu(%PDU{pdu_type: @getbulk_request} = pdu, state) do
    # GETBULK support - simplified implementation
    variable_bindings = process_getbulk_request(pdu, state)
    
    response_pdu = %PDU{
      version: pdu.version,
      community: pdu.community,
      pdu_type: @get_response,
      request_id: pdu.request_id,
      error_status: @no_error,
      error_index: 0,
      variable_bindings: variable_bindings
    }
    
    {:ok, response_pdu}
  end

  defp process_snmp_pdu(%PDU{pdu_type: @set_request} = pdu, state) do
    # SET operations not supported in this phase
    error_response = PDU.create_error_response(pdu, @read_only, 1)
    {:ok, error_response}
  end

  defp process_snmp_pdu(pdu, _state) do
    # Unknown PDU type
    error_response = PDU.create_error_response(pdu, @gen_err, 0)
    {:ok, error_response}
  end

  defp process_get_request(variable_bindings, state) do
    Enum.map(variable_bindings, fn {oid, _value} ->
      case get_oid_value(oid, state) do
        {:ok, value} -> {oid, value}
        {:error, :no_such_name} -> {oid, {:no_such_object, nil}}
      end
    end)
  end

  defp process_getnext_request(variable_bindings, state) do
    Enum.map(variable_bindings, fn {oid, _value} ->
      case SharedProfiles.get_next_oid(state.device_type, oid) do
        {:ok, next_oid, value, behavior} -> 
          # Apply device-specific behaviors
          device_state = build_device_state(state)
          dynamic_value = apply_device_behavior(next_oid, value, behavior, device_state)
          {next_oid, dynamic_value}
        :end_of_mib ->
          {oid, {:end_of_mib_view, nil}}
      end
    end)
  end

  defp process_getbulk_request(%PDU{} = pdu, state) do
    non_repeaters = pdu.non_repeaters || 0
    max_repetitions = pdu.max_repetitions || 10
    
    # Use shared profiles for bulk operations
    case SharedProfiles.handle_bulk_request(
      state.device_type,
      non_repeaters, 
      max_repetitions, 
      pdu.variable_bindings
    ) do
      {:ok, results} ->
        # Apply device-specific behaviors to results
        device_state = build_device_state(state)
        Enum.map(results, fn {oid, value, behavior} ->
          dynamic_value = apply_device_behavior(oid, value, behavior, device_state)
          {oid, dynamic_value}
        end)
      
      {:error, :too_big} ->
        # Return a smaller set or error
        [{List.first(pdu.variable_bindings) |> elem(0), {:too_big, nil}}]
      
      {:error, _reason} ->
        # Return error for first OID
        [{List.first(pdu.variable_bindings) |> elem(0), {:gen_err, nil}}]
    end
  end


  defp get_oid_value(oid, state) do
    # Update last access time
    new_state = %{state | last_access: System.monotonic_time(:millisecond)}
    
    # Check for special dynamic OIDs first
    case oid do
      "1.3.6.1.2.1.1.3.0" ->
        # sysUpTime - always dynamic
        get_dynamic_oid_value(oid, new_state)
      _ ->
        # Check shared profile for this device type
        case SharedProfiles.get_oid_value(state.device_type, oid) do
          {:ok, value, behavior} ->
            # Apply device-specific state and behaviors
            device_state = build_device_state(new_state)
            dynamic_value = apply_device_behavior(oid, value, behavior, device_state)
            {:ok, dynamic_value}
            
          {:error, :not_found} ->
            # Check if it's a device-specific dynamic OID
            case get_dynamic_oid_value(oid, new_state) do
              {:error, :no_such_name} = error -> error
              {:ok, value} = success -> success
            end
        end
    end
  end

  defp get_dynamic_oid_value("1.3.6.1.2.1.1.3.0", state) do
    # sysUpTime - calculate based on uptime_start
    uptime_ticks = calculate_uptime_ticks(state)
    {:ok, {:timeticks, uptime_ticks}}
  end

  defp get_dynamic_oid_value(oid, state) do
    # Check if this OID matches any counter or gauge patterns
    cond do
      Map.has_key?(state.counters, oid) ->
        {:ok, {:counter32, Map.get(state.counters, oid, 0)}}
        
      Map.has_key?(state.gauges, oid) ->
        {:ok, {:gauge32, Map.get(state.gauges, oid, 0)}}
        
      true ->
        {:error, :no_such_name}
    end
  end

  defp apply_behaviors(oid, base_value, type, state) do
    # Apply any configured behaviors to modify the base value
    # This is a simplified implementation - full behavior engine comes in Phase 5
    case type do
      "Counter32" ->
        # Simple counter increment
        increment = get_counter_increment(oid, state)
        base_value + increment
        
      "Gauge32" ->
        # Simple gauge variation
        variation = get_gauge_variation(oid, state)
        max(0, base_value + variation)
        
      _ ->
        base_value
    end
  end

  defp get_counter_increment(oid, state) do
    # Simple implementation - increment based on uptime
    uptime_seconds = calculate_uptime(state)
    base_rate = 1000  # 1000 units per second
    
    # Apply some randomness to make it realistic
    jitter = :rand.uniform(200) - 100  # ±100 variation
    max(0, base_rate + jitter) * uptime_seconds
  end

  defp get_gauge_variation(oid, state) do
    # Simple gauge variation - random walk
    case :rand.uniform(3) do
      1 -> -:rand.uniform(10)  # Decrease
      2 -> :rand.uniform(10)   # Increase  
      3 -> 0                   # No change
    end
  end

  defp format_snmp_value(value, type) do
    case String.upcase(type) do
      "INTEGER" -> value
      "COUNTER32" -> {:counter32, value}
      "COUNTER64" -> {:counter64, value}
      "GAUGE32" -> {:gauge32, value}
      "GAUGE" -> {:gauge32, value}
      "TIMETICKS" -> {:timeticks, value}
      "STRING" -> to_string(value)
      "OCTET" -> to_string(value)
      _ -> to_string(value)
    end
  end

  defp calculate_uptime(%{uptime_start: uptime_start}) when is_integer(uptime_start) do
    current_time = :erlang.monotonic_time()
    uptime_monotonic = current_time - uptime_start
    :erlang.convert_time_unit(uptime_monotonic, :native, :millisecond)
  end

  defp calculate_uptime(_state) do
    0
  end

  defp calculate_uptime_ticks(state) do
    # SNMP TimeTicks are in 1/100th of a second (centiseconds)
    uptime_milliseconds = calculate_uptime(state)
    div(uptime_milliseconds, 10)  # Convert milliseconds to centiseconds
  end

  defp initialize_device_state(state) do
    # Initialize counters and gauges from shared profile
    case SharedProfiles.get_device_profile(state.device_type) do
      {:ok, profile_info} ->
        # Initialize device-specific counter and gauge state
        counters = initialize_counters(profile_info, state)
        gauges = initialize_gauges(profile_info, state)
        status_vars = initialize_status_vars(state)
        
        oid_count = Map.get(profile_info, :oid_count, 0)
        Logger.info("Device #{state.device_id} initialized with #{oid_count} OIDs from shared profile")
        
        {:ok, %{state | 
          counters: counters, 
          gauges: gauges, 
          status_vars: status_vars
        }}
        
      {:error, :not_found} ->
        Logger.warning("No shared profile found for device type #{state.device_type}")
        # Initialize with minimal state
        {:ok, %{state | counters: %{}, gauges: %{}, status_vars: %{}}}
        
      {:error, reason} ->
        Logger.error("Failed to load shared profile for #{state.device_type}: #{inspect(reason)}")
        {:error, {:profile_load_failed, reason}}
    end
  end

  defp build_device_state(state) do
    %{
      device_id: state.device_id,
      device_type: state.device_type,
      uptime: calculate_uptime(state),
      mac_address: state.mac_address,
      port: state.port,
      interface_utilization: calculate_interface_utilization(state),
      signal_quality: calculate_signal_quality(state),
      cpu_utilization: calculate_cpu_utilization(state),
      temperature: calculate_temperature(state),
      error_rate: calculate_error_rate(state),
      health_score: calculate_health_score(state),
      correlation_factors: build_correlation_factors(state)
    }
  end

  defp calculate_interface_utilization(state) do
    # Calculate based on current traffic levels
    # For now, return a random utilization between 0.1 and 0.8
    0.1 + (:rand.uniform() * 0.7)
  end

  defp calculate_signal_quality(state) do
    # Calculate signal quality (0.0 to 1.0)
    # Could be based on SNR, power levels, etc.
    base_quality = 0.8
    random_variation = (:rand.uniform() - 0.5) * 0.2
    max(0.0, min(1.0, base_quality + random_variation))
  end

  defp calculate_cpu_utilization(state) do
    # CPU utilization often correlates with network activity
    interface_util = calculate_interface_utilization(state)
    base_cpu = 0.2 + (interface_util * 0.4)
    random_variation = (:rand.uniform() - 0.5) * 0.1
    max(0.0, min(1.0, base_cpu + random_variation))
  end

  defp calculate_temperature(state) do
    # Device temperature in Celsius
    # Could be affected by CPU load, ambient temperature, etc.
    base_temp = 35.0
    cpu_util = calculate_cpu_utilization(state)
    load_factor = cpu_util * 15.0  # Up to 15°C increase under load
    ambient_variation = (:rand.uniform() - 0.5) * 10.0
    
    base_temp + load_factor + ambient_variation
  end

  defp calculate_error_rate(state) do
    # Error rate as a percentage
    signal_quality = calculate_signal_quality(state)
    base_error_rate = (1.0 - signal_quality) * 0.05  # Up to 5% errors with poor signal
    max(0.0, base_error_rate)
  end

  defp calculate_health_score(state) do
    # Overall device health score (0.0 to 1.0)
    signal_quality = calculate_signal_quality(state)
    error_rate = calculate_error_rate(state)
    uptime = calculate_uptime(state)
    
    # Health improves with good signal, low errors, and stable uptime
    uptime_factor = min(1.0, uptime / 86400.0)  # Normalize to days
    health = (signal_quality + (1.0 - error_rate) + uptime_factor) / 3.0
    max(0.0, min(1.0, health))
  end

  defp build_correlation_factors(_state) do
    # Build correlation factors for related OIDs
    # This could be expanded to track actual relationships
    %{}
  end

  defp generate_mac_address(device_type, port) do
    # Generate MAC address using DeviceDistribution module
    DeviceDistribution.generate_device_id(device_type, port, format: :mac_based)
  end
  
  defp initialize_counters(profile_info, state) do
    # Initialize counters to zero for this device instance
    counter_oids = Map.get(profile_info, :counter_oids, [])
    Enum.map(counter_oids, fn oid -> {oid, 0} end) |> Map.new()
  end
  
  defp initialize_gauges(profile_info, state) do
    # Initialize gauges with base values from profile
    gauge_oids = Map.get(profile_info, :gauge_oids, [])
    Enum.map(gauge_oids, fn oid -> 
      base_value = get_base_gauge_value(oid, state.device_type)
      {oid, base_value}
    end) |> Map.new()
  end
  
  defp initialize_status_vars(state) do
    # Initialize device-specific status variables
    %{
      "admin_status" => 1,  # up
      "oper_status" => 1,   # up
      "last_change" => 0
    }
  end
  
  defp get_base_gauge_value(oid, device_type) do
    # Get realistic base values for gauge OIDs based on device type
    characteristics = DeviceDistribution.get_device_characteristics(device_type)
    
    cond do
      String.contains?(oid, "ifSpeed") ->
        # Interface speed based on device type
        case device_type do
          :cable_modem -> 100_000_000  # 100 Mbps
          :switch -> 1_000_000_000     # 1 Gbps
          :router -> 1_000_000_000     # 1 Gbps
          :cmts -> 10_000_000_000      # 10 Gbps
          _ -> 10_000_000              # 10 Mbps default
        end
        
      String.contains?(oid, "ifMtu") ->
        1500  # Standard Ethernet MTU
        
      String.contains?(oid, "Temperature") ->
        25 + :rand.uniform(20)  # 25-45°C
        
      true ->
        :rand.uniform(100)  # Default gauge value
    end
  end
  
  defp apply_device_behavior(oid, base_value, behavior, device_state) do
    # Apply device-specific behavior to the base value
    case behavior do
      {:counter, config} ->
        # Apply counter increment based on uptime and device characteristics
        apply_counter_behavior(oid, base_value, config, device_state)
        
      {:gauge, config} ->
        # Apply gauge variation based on device state
        apply_gauge_behavior(oid, base_value, config, device_state)
        
      {:enum, possible_values} ->
        # Select enum value based on device state
        apply_enum_behavior(oid, possible_values, device_state)
        
      _ ->
        # Return base value for static or unknown behaviors
        base_value
    end
  end
  
  defp apply_counter_behavior(oid, base_value, config, device_state) do
    # Calculate counter increment based on uptime and rate
    uptime_seconds = device_state.uptime / 1000
    rate = Map.get(config, :rate, 1000)  # Default 1000 units/second
    jitter = Map.get(config, :jitter, 0.1)  # 10% jitter
    
    # Apply jitter
    actual_rate = rate * (1.0 + ((:rand.uniform() - 0.5) * 2 * jitter))
    increment = trunc(actual_rate * uptime_seconds)
    
    base_value + increment
  end
  
  defp apply_gauge_behavior(oid, base_value, config, device_state) do
    # Apply gauge variation based on device characteristics
    variance = Map.get(config, :variance, 0.1)  # 10% variance
    min_val = Map.get(config, :min, 0)
    max_val = Map.get(config, :max, base_value * 2)
    
    # Apply random variation
    variation = ((:rand.uniform() - 0.5) * 2 * variance * base_value)
    new_value = base_value + variation
    
    # Clamp to min/max bounds
    max(min_val, min(max_val, trunc(new_value)))
  end
  
  defp apply_enum_behavior(oid, possible_values, device_state) do
    # Select enum value based on device health/state
    health_score = device_state.health_score
    
    # Higher health scores favor better enum values
    if health_score > 0.8 do
      Enum.at(possible_values, 0)  # Best value
    else
      Enum.random(possible_values)  # Random selection
    end
  end
  
end