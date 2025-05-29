defmodule SnmpSimEx.Device do
  @moduledoc """
  Individual device GenServer for handling SNMP requests.
  Uses shared profiles and device-specific state only.
  """

  use GenServer
  require Logger

  alias SnmpSimEx.{ProfileLoader, Core.Server, Core.PDU, OIDTree, BulkOperations}

  defstruct [
    :device_id,
    :port,
    :device_type,
    :profile,
    :oid_tree,       # OID tree for efficient GETNEXT/GETBULK operations
    :server_pid,
    :mac_address,
    :uptime_start,
    :counters,
    :gauges,
    :status_vars,
    :community,
    :behaviors
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
  Start a device with the given profile.
  
  ## Options
  
  - `:port` - UDP port for the device (required)
  - `:community` - SNMP community string (default: "public")
  - `:mac_address` - MAC address for the device (auto-generated if not provided)
  - `:behaviors` - List of behavior configurations
  
  ## Examples
  
      profile = SnmpSimEx.ProfileLoader.load_profile(
        :cable_modem,
        {:walk_file, "priv/walks/cable_modem.walk"}
      )
      
      {:ok, device} = SnmpSimEx.Device.start_link(profile, port: 9001)
      
  """
  def start_link(profile, opts \\ []) do
    GenServer.start_link(__MODULE__, {profile, opts})
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
  def init({%ProfileLoader{} = profile, opts}) do
    port = Keyword.fetch!(opts, :port)
    community = Keyword.get(opts, :community, @default_community)
    mac_address = Keyword.get(opts, :mac_address, generate_mac_address())
    behaviors = Keyword.get(opts, :behaviors, profile.behaviors || [])

    device_id = "#{profile.device_type}_#{port}"
    
    # Start the UDP server for this device  
    case Server.start_link(port, community: community) do
      {:ok, server_pid} ->
        
        # Build OID tree from profile for efficient operations
        oid_tree = build_oid_tree_from_profile(profile)
        
        state = %__MODULE__{
          device_id: device_id,
          port: port,
          device_type: profile.device_type,
          profile: profile,
          oid_tree: oid_tree,
          server_pid: server_pid,
          mac_address: mac_address,
          uptime_start: :erlang.monotonic_time(),
          counters: %{},
          gauges: %{},
          status_vars: %{},
          community: community,
          behaviors: behaviors
        }
        
        # Set up the SNMP handler for this device
        # Capture the device PID explicitly to avoid "process attempted to call itself" errors
        device_pid = self()
        handler_fn = fn pdu, context ->
          GenServer.call(device_pid, {:handle_snmp, pdu, context})
        end
        :ok = Server.set_device_handler(server_pid, handler_fn)
        
        # Initialize device state from profile
        case initialize_device_state(state) do
          {:ok, initialized_state} -> {:ok, initialized_state}
          {:error, reason} -> {:stop, reason}
        end
        
      {:error, reason} ->
        Logger.error("Failed to start UDP server for device #{device_id} on port #{port}: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:get_info, _from, %{device_id: device_id} = state) when is_map(state) do
    info = %{
      device_id: Map.get(state, :device_id, "unknown"),
      port: Map.get(state, :port, 0),
      device_type: Map.get(state, :device_type, :unknown),
      mac_address: Map.get(state, :mac_address, "unknown"),
      uptime: calculate_uptime(state),
      oid_count: case Map.get(state, :profile) do
        %{oid_map: oid_map} -> map_size(oid_map)
        _ -> 0
      end,
      counters: map_size(Map.get(state, :counters, %{})),
      gauges: map_size(Map.get(state, :gauges, %{})),
      behaviors: length(Map.get(state, :behaviors, []))
    }
    
    {:reply, info, state}
  end

  def handle_call(:get_info, _from, state) do
    Logger.warning("Device get_info called with invalid state: #{inspect(state)}")
    {:reply, {:error, {:invalid_state, state}}, state}
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

  @impl true
  def handle_call({:handle_snmp, pdu, _context}, _from, state) do
    response = process_snmp_pdu(pdu, state)
    {:reply, response, state}
  end

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
      case OIDTree.get_next(state.oid_tree, oid) do
        {:ok, next_oid, value, _behavior} -> 
          # Apply dynamic value simulation if needed
          dynamic_value = apply_dynamic_value(next_oid, value, state)
          {next_oid, dynamic_value}
        :end_of_mib ->
          {oid, {:end_of_mib_view, nil}}
      end
    end)
  end

  defp process_getbulk_request(%PDU{} = pdu, state) do
    non_repeaters = pdu.non_repeaters || 0
    max_repetitions = pdu.max_repetitions || 10
    
    # Use the efficient bulk operations module
    case BulkOperations.handle_bulk_request(
      state.oid_tree, 
      non_repeaters, 
      max_repetitions, 
      pdu.variable_bindings
    ) do
      {:ok, results} ->
        # Apply dynamic value simulation to results
        Enum.map(results, fn {oid, value, _behavior} ->
          dynamic_value = apply_dynamic_value(oid, value, state)
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

  defp process_bulk_repeating_oids(oids, max_repetitions, state) do
    Enum.flat_map(oids, fn {start_oid, _} ->
      get_bulk_sequence(start_oid, max_repetitions, state, [])
    end)
  end

  defp get_bulk_sequence(_oid, 0, _state, acc), do: Enum.reverse(acc)
  
  defp get_bulk_sequence(oid, remaining, state, acc) do
    case ProfileLoader.get_next_oid(state.profile, oid) do
      {:ok, next_oid} ->
        case get_oid_value(next_oid, state) do
          {:ok, value} ->
            get_bulk_sequence(next_oid, remaining - 1, state, [{next_oid, value} | acc])
          {:error, :no_such_name} ->
            Enum.reverse([{oid, {:end_of_mib_view, nil}} | acc])
        end
      :end_of_mib ->
        Enum.reverse([{oid, {:end_of_mib_view, nil}} | acc])
    end
  end

  defp get_oid_value(oid, state) do
    # Check for special dynamic OIDs first (before checking profile)
    case oid do
      "1.3.6.1.2.1.1.3.0" ->
        # sysUpTime - always dynamic
        get_dynamic_oid_value(oid, state)
      _ ->
        case ProfileLoader.get_oid_value(state.profile, oid) do
          nil ->
            # Check if it's a special system OID that needs dynamic values
            case get_dynamic_oid_value(oid, state) do
              {:error, :no_such_name} = error -> error
              {:ok, value} = success -> success
            end
            
          %{value: _value, type: _type, behavior: behavior} = profile_data ->
            # Use the new value simulator with behavior configuration
            device_state = build_device_state(state)
            current_value = SnmpSimEx.ValueSimulator.simulate_value(profile_data, behavior, device_state)
            {:ok, current_value}
            
          %{value: value, type: type} = profile_data ->
            # Fallback for profiles without behavior configuration
            behavior = {:static_value, %{}}
            device_state = build_device_state(state)
            current_value = SnmpSimEx.ValueSimulator.simulate_value(profile_data, behavior, device_state)
            {:ok, current_value}
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
    # Initialize counters and gauges from profile
    profile_oids = state.profile.oid_map
    
    counters = 
      profile_oids
      |> Enum.filter(fn {_oid, %{type: type}} -> 
        String.contains?(String.upcase(type), "COUNTER") 
      end)
      |> Enum.map(fn {oid, _} -> {oid, 0} end)
      |> Map.new()
    
    gauges = 
      profile_oids
      |> Enum.filter(fn {_oid, %{type: type}} -> 
        String.contains?(String.upcase(type), "GAUGE") 
      end)
      |> Enum.map(fn {oid, %{value: value}} -> {oid, value} end)
      |> Map.new()
    
    Logger.info("Device #{state.device_id} initialized with #{map_size(profile_oids)} OIDs")
    
    {:ok, %{state | counters: counters, gauges: gauges}}
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

  defp generate_mac_address do
    # Generate a random MAC address in the form "00:1A:2B:XX:XX:XX"
    # Use a fixed prefix to indicate simulated devices
    prefix = "00:1A:2B"
    suffix = for _ <- 1..3 do
      :rand.uniform(255) |> Integer.to_string(16) |> String.pad_leading(2, "0")
    end |> Enum.join(":")
    
    "#{prefix}:#{suffix}"
  end
  
  # Phase 3: OID Tree and GETBULK support functions
  
  defp build_oid_tree_from_profile(%ProfileLoader{oid_map: oid_map}) do
    # Build OID tree from profile's OID map
    tree = OIDTree.new()
    
    Enum.reduce(oid_map, tree, fn {oid, value_info}, acc_tree ->
      # Extract behavior information if available
      behavior = Map.get(value_info, :behavior)
      
      # Insert OID with its value and behavior into tree
      OIDTree.insert(acc_tree, oid, value_info.value, behavior)
    end)
  end
  
  defp apply_dynamic_value(oid, base_value, state) do
    # Apply dynamic value simulation based on behaviors
    # This integrates with Phase 2 value simulation
    case Map.get(state.counters, oid) do
      nil ->
        case Map.get(state.gauges, oid) do
          nil -> base_value  # Return base value if no dynamic state
          gauge_value -> gauge_value
        end
      counter_value -> 
        # For counters, apply increment based on behavior
        apply_counter_increment(oid, counter_value, state)
    end
  end
  
  defp apply_counter_increment(oid, current_value, state) do
    # Get behavior for this OID from the tree
    case OIDTree.get(state.oid_tree, oid) do
      {:ok, _value, behavior} when not is_nil(behavior) ->
        # Apply behavior-based increment (simplified)
        increment = calculate_behavior_increment(behavior, state)
        current_value + increment
      _ ->
        # Default increment for counters without specific behavior
        current_value + :rand.uniform(100)
    end
  end
  
  defp calculate_behavior_increment(behavior, _state) do
    # Simple behavior-based increment calculation
    # This would integrate with the Phase 2 value simulation system
    case behavior do
      {:traffic_counter, config} ->
        {min_rate, max_rate} = Map.get(config, :rate_range, {100, 10000})
        min_rate + :rand.uniform(max_rate - min_rate)
      
      {:packet_counter, config} ->
        {min_rate, max_rate} = Map.get(config, :rate_range, {10, 1000})
        min_rate + :rand.uniform(max_rate - min_rate)
      
      {:error_counter, config} ->
        {min_rate, max_rate} = Map.get(config, :rate_range, {0, 10})
        min_rate + :rand.uniform(max(1, max_rate - min_rate))
      
      _ ->
        # Default increment
        :rand.uniform(50)
    end
  end
end