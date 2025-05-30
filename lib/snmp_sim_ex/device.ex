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

  alias SNMPSimEx.{DeviceDistribution}
  alias SnmpSimEx.Core.{Server, PDU}
  alias SnmpSimEx.MIB.SharedProfiles

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
    :last_access,     # For tracking access time
    :error_conditions # Active error injection conditions
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
          last_access: System.monotonic_time(:millisecond),
          error_conditions: %{}
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
    # Get OID count (simplified for testing)
    oid_count = 100  # Mock value for testing
    
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
    # Check for error conditions before processing the request
    case check_error_conditions(pdu, state) do
      {:error, error_response} ->
        {:reply, error_response, state}
      :continue ->
        response = process_snmp_pdu(pdu, state)
        {:reply, response, state}
    end
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
      status_vars: %{},
      error_conditions: %{}
    }
    
    case initialize_device_state(new_state) do
      {:ok, initialized_state} -> {:reply, :ok, initialized_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  # Error injection message handlers
  @impl true
  def handle_info({:error_injection, :timeout, config}, state) do
    Logger.debug("Applying timeout error injection to device #{state.device_id}")
    new_error_conditions = Map.put(state.error_conditions, :timeout, config)
    {:noreply, %{state | error_conditions: new_error_conditions}}
  end

  @impl true
  def handle_info({:error_injection, :packet_loss, config}, state) do
    Logger.debug("Applying packet loss error injection to device #{state.device_id}")
    new_error_conditions = Map.put(state.error_conditions, :packet_loss, config)
    {:noreply, %{state | error_conditions: new_error_conditions}}
  end

  @impl true
  def handle_info({:error_injection, :snmp_error, config}, state) do
    Logger.debug("Applying SNMP error injection to device #{state.device_id}")
    new_error_conditions = Map.put(state.error_conditions, :snmp_error, config)
    {:noreply, %{state | error_conditions: new_error_conditions}}
  end

  @impl true
  def handle_info({:error_injection, :malformed, config}, state) do
    Logger.debug("Applying malformed response error injection to device #{state.device_id}")
    new_error_conditions = Map.put(state.error_conditions, :malformed, config)
    {:noreply, %{state | error_conditions: new_error_conditions}}
  end

  @impl true
  def handle_info({:error_injection, :device_failure, config}, state) do
    Logger.info("Applying device failure error injection to device #{state.device_id}: #{config.failure_type}")
    new_error_conditions = Map.put(state.error_conditions, :device_failure, config)
    
    case config.failure_type do
      :reboot ->
        # Schedule device recovery after duration
        Process.send_after(self(), {:error_injection, :recovery, config}, config.duration_ms)
        {:noreply, %{state | error_conditions: new_error_conditions}}
        
      :power_failure ->
        # Simulate complete power loss - device becomes unreachable
        new_status_vars = Map.put(state.status_vars, "oper_status", 2)  # down
        {:noreply, %{state | 
          error_conditions: new_error_conditions,
          status_vars: new_status_vars
        }}
        
      :network_disconnect ->
        # Simulate network connectivity loss
        new_status_vars = Map.put(state.status_vars, "admin_status", 2)  # administratively down
        {:noreply, %{state | 
          error_conditions: new_error_conditions,
          status_vars: new_status_vars
        }}
        
      _ ->
        {:noreply, %{state | error_conditions: new_error_conditions}}
    end
  end

  @impl true
  def handle_info({:error_injection, :recovery, config}, state) do
    Logger.info("Device #{state.device_id} recovering from #{config.failure_type}")
    
    # Remove device failure condition
    new_error_conditions = Map.delete(state.error_conditions, :device_failure)
    
    # Restore device status based on recovery behavior
    case config[:recovery_behavior] do
      :reset_counters ->
        # Reset counters and restore status
        new_state = %{state |
          error_conditions: new_error_conditions,
          counters: %{},
          status_vars: %{"admin_status" => 1, "oper_status" => 1, "last_change" => 0}
        }
        {:noreply, new_state}
        
      :gradual ->
        # Gradual recovery - restore status but keep some impact
        new_status_vars = Map.merge(state.status_vars, %{
          "admin_status" => 1, 
          "oper_status" => 1,
          "last_change" => calculate_uptime(state)
        })
        {:noreply, %{state | 
          error_conditions: new_error_conditions,
          status_vars: new_status_vars
        }}
        
      _ ->
        # Normal recovery
        new_status_vars = Map.merge(state.status_vars, %{
          "admin_status" => 1, 
          "oper_status" => 1
        })
        {:noreply, %{state | 
          error_conditions: new_error_conditions,
          status_vars: new_status_vars
        }}
    end
  end

  @impl true
  def handle_info({:error_injection, :clear_all}, state) do
    Logger.info("Clearing all error conditions for device #{state.device_id}")
    {:noreply, %{state | error_conditions: %{}}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Device #{state.device_id} received unhandled message: #{inspect(msg)}")
    {:noreply, state}
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

  defp check_error_conditions(pdu, state) do
    # Check device failure conditions first
    if device_failure_active?(state) do
      {:error, {:error, :device_unreachable}}
    else
      # Check other error conditions in order of priority
      check_timeout_conditions(pdu, state) ||
      check_packet_loss_conditions(pdu, state) ||
      check_snmp_error_conditions(pdu, state) ||
      check_malformed_conditions(pdu, state) ||
      :continue
    end
  end

  defp device_failure_active?(state) do
    case Map.get(state.error_conditions, :device_failure) do
      %{failure_type: :power_failure} -> true
      %{failure_type: :network_disconnect} -> true
      _ -> false
    end
  end

  defp check_timeout_conditions(pdu, state) do
    case Map.get(state.error_conditions, :timeout) do
      nil -> false
      config ->
        if should_apply_error?(config.probability) and oid_matches_target?(pdu, config.target_oids) do
          # Simulate timeout by not responding (let the client timeout)
          Process.sleep(config.duration_ms)
          {:error, {:error, :timeout}}
        else
          false
        end
    end
  end

  defp check_packet_loss_conditions(pdu, state) do
    case Map.get(state.error_conditions, :packet_loss) do
      nil -> false
      config ->
        if should_apply_error?(config.loss_rate) and oid_matches_target?(pdu, config.target_oids) do
          # Simulate packet loss by dropping the request silently
          {:error, {:error, :packet_lost}}
        else
          false
        end
    end
  end

  defp check_snmp_error_conditions(pdu, state) do
    case Map.get(state.error_conditions, :snmp_error) do
      nil -> false
      config ->
        if should_apply_error?(config.probability) and oid_matches_target?(pdu, config.target_oids) do
          error_status = case config.error_type do
            :noSuchName -> @no_such_name
            :genErr -> @gen_err
            :tooBig -> @too_big
            :badValue -> @bad_value
            :readOnly -> @read_only
            _ -> @gen_err
          end
          
          error_response = PDU.create_error_response(pdu, error_status, config[:error_index] || 1)
          {:error, {:ok, error_response}}
        else
          false
        end
    end
  end

  defp check_malformed_conditions(pdu, state) do
    case Map.get(state.error_conditions, :malformed) do
      nil -> false
      config ->
        if should_apply_error?(config.probability) and oid_matches_target?(pdu, config.target_oids) do
          # Create a malformed response based on corruption type
          malformed_response = create_malformed_response(pdu, config)
          {:error, {:ok, malformed_response}}
        else
          false
        end
    end
  end

  defp should_apply_error?(probability) do
    :rand.uniform() < probability
  end

  defp oid_matches_target?(pdu, target_oids) do
    case target_oids do
      :all -> true
      [] -> true
      oids when is_list(oids) ->
        requested_oids = Enum.map(pdu.variable_bindings, fn {oid, _} -> oid end)
        Enum.any?(requested_oids, fn oid -> 
          Enum.any?(oids, fn target -> String.starts_with?(oid, target) end)
        end)
      _ -> true
    end
  end

  defp create_malformed_response(pdu, config) do
    case config.corruption_type do
      :truncated ->
        # Create a truncated response by limiting variable bindings
        truncated_bindings = Enum.take(pdu.variable_bindings, 1)
        %PDU{pdu | 
          pdu_type: @get_response,
          variable_bindings: truncated_bindings,
          error_status: @no_error
        }
        
      :invalid_ber ->
        # Create response with invalid BER encoding simulation
        %PDU{pdu |
          pdu_type: @get_response,
          variable_bindings: [{<<0xFF, 0xFF>>, {:invalid_ber, nil}}],
          error_status: @gen_err
        }
        
      :wrong_community ->
        # Create response with wrong community string
        %PDU{pdu |
          community: "invalid_community",
          pdu_type: @get_response,
          error_status: @gen_err
        }
        
      :invalid_pdu_type ->
        # Create response with invalid PDU type
        %PDU{pdu |
          pdu_type: 0xFF,  # Invalid PDU type
          error_status: @gen_err
        }
        
      :corrupted_varbinds ->
        # Create response with corrupted variable bindings
        corrupted_bindings = Enum.map(pdu.variable_bindings, fn {oid, _} ->
          {oid <> ".invalid", {:corrupted, <<0x00, 0xFF, 0x00>>}}
        end)
        %PDU{pdu |
          pdu_type: @get_response,
          variable_bindings: corrupted_bindings,
          error_status: @gen_err
        }
        
      _ ->
        # Default to general error
        PDU.create_error_response(pdu, @gen_err, 1)
    end
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
      case SharedProfiles.get_next_oid(state.device_type, oid) do
        {:ok, next_oid} ->
          # Get the value for the next OID
          device_state = build_device_state(state)
          case SharedProfiles.get_oid_value(state.device_type, next_oid, device_state) do
            {:ok, value} -> {next_oid, value}
            {:error, _} -> 
              # If we can't get the value, try our fallback
              get_fallback_next_oid(oid, state)
          end
        :end_of_mib ->
          {oid, {:end_of_mib_view, nil}}
        {:error, :end_of_mib} ->
          {oid, {:end_of_mib_view, nil}}
        {:error, :device_type_not_found} ->
          # Fallback: try to get next from current OID pattern
          get_fallback_next_oid(oid, state)
        {:error, _reason} ->
          {oid, {:end_of_mib_view, nil}}
      end
    end)
  end

  defp process_getbulk_request(%PDU{} = pdu, state) do
    non_repeaters = pdu.non_repeaters || 0
    max_repetitions = pdu.max_repetitions || 10
    
    case pdu.variable_bindings do
      [] -> []
      variable_bindings ->
        # Process non-repeaters first
        {non_rep_vars, repeat_vars} = Enum.split(variable_bindings, non_repeaters)
        
        # Get non-repeater results (one result per variable)
        non_rep_results = Enum.map(non_rep_vars, fn {oid, _value} ->
          case SharedProfiles.get_next_oid(state.device_type, oid) do
            {:ok, next_oid, value} -> {next_oid, value}
            {:error, :end_of_mib} -> {oid, {:end_of_mib_view, nil}}
            {:error, :device_type_not_found} -> get_fallback_next_oid(oid, state)
            {:error, _reason} -> {oid, {:end_of_mib_view, nil}}
          end
        end)
        
        # Get bulk results for repeating variables
        bulk_results = case repeat_vars do
          [] -> []
          [first_repeat | _] ->
            start_oid = elem(first_repeat, 0)
            case SharedProfiles.get_bulk_oids(state.device_type, start_oid, max_repetitions) do
              {:ok, bulk_oids} -> bulk_oids
              {:error, :device_type_not_found} -> get_fallback_bulk_oids(start_oid, max_repetitions, state)
              {:error, _reason} -> []
            end
        end
        
        non_rep_results ++ bulk_results
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
        # Try to get value from SharedProfiles first
        device_state = build_device_state(new_state)
        case SharedProfiles.get_oid_value(state.device_type, oid, device_state) do
          {:ok, value} -> {:ok, value}
          {:error, :no_such_object} -> 
            # Fallback to device-specific dynamic OIDs
            get_dynamic_oid_value(oid, new_state)
          {:error, :no_such_name} -> 
            # OID not found in SharedProfiles, fallback to dynamic OIDs
            get_dynamic_oid_value(oid, new_state)
          {:error, :device_type_not_found} ->
            # Device type not loaded in SharedProfiles, fallback to dynamic OIDs
            get_dynamic_oid_value(oid, new_state)
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
        
      # Fallback to basic system OIDs if not found in SharedProfiles
      oid == "1.3.6.1.2.1.1.1.0" ->
        # sysDescr - system description
        device_type_str = case state.device_type do
          :cable_modem -> "Motorola SB6141 DOCSIS 3.0 Cable Modem"
          :cmts -> "Cisco CMTS Cable Modem Termination System"
          :router -> "Cisco Router"
          _ -> "SNMP Simulator Device"
        end
        {:ok, device_type_str}
        
      oid == "1.3.6.1.2.1.1.2.0" ->
        # sysObjectID - object identifier
        {:ok, "1.3.6.1.4.1.4491.2.4.1"}
        
      oid == "1.3.6.1.2.1.1.4.0" ->
        # sysContact - contact info
        {:ok, "admin@example.com"}
        
      oid == "1.3.6.1.2.1.1.5.0" ->
        # sysName - system name
        device_name = state.device_id || "device_#{state.port}"
        {:ok, device_name}
        
      oid == "1.3.6.1.2.1.1.6.0" ->
        # sysLocation - location
        {:ok, "Customer Premises"}
        
      oid == "1.3.6.1.2.1.1.7.0" ->
        # sysServices - services
        {:ok, 2}
        
      # Interface table OIDs (1.3.6.1.2.1.2.2.1.x.y where x is column, y is interface index)
      String.starts_with?(oid, "1.3.6.1.2.1.2.2.1.") ->
        handle_interface_oid(oid, state)
        
      true ->
        {:error, :no_such_name}
    end
  end

  defp handle_interface_oid(oid, state) do
    # Parse the interface OID: 1.3.6.1.2.1.2.2.1.column.interface_index
    case String.split(oid, ".") do
      ["1", "3", "6", "1", "2", "1", "2", "2", "1", column, interface_index] ->
        case {column, interface_index} do
          {"1", "1"} ->
            # ifIndex.1 - interface index
            {:ok, 1}
            
          {"2", "1"} ->
            # ifDescr.1 - interface description
            interface_desc = case state.device_type do
              :cable_modem -> "Ethernet Interface"
              :cmts -> "Cable Interface 1/0/0"
              :router -> "GigabitEthernet0/0"
              _ -> "Interface 1"
            end
            {:ok, interface_desc}
            
          {"3", "1"} ->
            # ifType.1 - interface type (6 = ethernetCsmacd)
            {:ok, 6}
            
          {"4", "1"} ->
            # ifMtu.1 - MTU
            {:ok, 1500}
            
          {"5", "1"} ->
            # ifSpeed.1 - interface speed (100 Mbps)
            {:ok, 100000000}
            
          {"6", "1"} ->
            # ifPhysAddress.1 - MAC address (as hex string)
            {:ok, "00:11:22:33:44:55"}
            
          {"7", "1"} ->
            # ifAdminStatus.1 - admin status (1 = up)
            {:ok, 1}
            
          {"8", "1"} ->
            # ifOperStatus.1 - operational status (1 = up)
            {:ok, 1}
            
          {"9", "1"} ->
            # ifLastChange.1 - last change (TimeTicks)
            {:ok, {:timeticks, 0}}
            
          _ ->
            # Unsupported interface column or index
            {:error, :no_such_name}
        end
        
      _ ->
        # Invalid OID format
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
    # Mock implementation for testing - initialize with minimal state
    Logger.info("Device #{state.device_id} initialized with mock profile for testing")
    
    # Initialize basic counters and gauges for testing
    counters = %{
      "1.3.6.1.2.1.2.2.1.10.1" => 0,  # ifInOctets
      "1.3.6.1.2.1.2.2.1.16.1" => 0   # ifOutOctets
    }
    
    gauges = %{
      "1.3.6.1.2.1.2.2.1.5.1" => 100_000_000,  # ifSpeed
      "1.3.6.1.2.1.2.2.1.4.1" => 1500          # ifMtu
    }
    
    status_vars = initialize_status_vars(state)
    
    {:ok, %{state | 
      counters: counters, 
      gauges: gauges, 
      status_vars: status_vars,
      error_conditions: state.error_conditions || %{}
    }}
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
    # Mock implementation for testing
    counter_oids = Map.get(profile_info, :counter_oids, [])
    Enum.map(counter_oids, fn oid -> {oid, 0} end) |> Map.new()
  end
  
  defp initialize_gauges(profile_info, state) do
    # Mock implementation for testing  
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

  defp get_fallback_next_oid(oid, state) do
    # Simple fallback for common OID patterns
    case oid do
      "1.3.6.1.2.1.1.1.0" -> {"1.3.6.1.2.1.1.2.0", {:object_identifier, "1.3.6.1.4.1.99999"}}
      "1.3.6.1.2.1.1.2.0" -> {"1.3.6.1.2.1.1.3.0", {:timeticks, calculate_uptime_ticks(state)}}
      "1.3.6.1.2.1.1.3.0" -> {"1.3.6.1.2.1.1.4.0", {:string, "Fallback Contact"}}
      "1.3.6.1.2.1.1.4.0" -> {"1.3.6.1.2.1.1.5.0", {:string, "Fallback System Name"}}
      "1.3.6.1.2.1.1.5.0" -> {"1.3.6.1.2.1.1.6.0", {:string, "Fallback Location"}}
      "1.3.6.1.2.1.1.6.0" -> {"1.3.6.1.2.1.1.7.0", {:integer, 72}}
      "1.3.6.1.2.1.1.7.0" -> {"1.3.6.1.2.1.2.1.0", {:integer, 2}}
      "1.3.6.1.2.1.2.1.0" -> {"1.3.6.1.2.1.2.2.1.1.1", {:integer, 1}}
      "1.3.6.1.2.1.2.2.1.1" -> {"1.3.6.1.2.1.2.2.1.1.1", {:integer, 1}}
      "1.3.6.1.2.1.2.2.1.1.1" -> {"1.3.6.1.2.1.2.2.1.1.2", {:integer, 2}}
      "1.3.6.1.2.1.2.2.1.1.2" -> {"1.3.6.1.2.1.2.2.1.1.3", {:integer, 3}}
      "1.3.6.1.2.1.2.2.1.1.3" -> {"1.3.6.1.2.1.2.2.1.2.1", {:string, "eth0"}}
      "1.3.6.1.2.1.2.2.1.2.1" -> {"1.3.6.1.2.1.2.2.1.2.2", {:string, "eth1"}}
      "1.3.6.1.2.1.2.2.1.2.2" -> {"1.3.6.1.2.1.2.2.1.2.3", {:string, "eth2"}}
      "1.3.6.1.2.1.1" -> {"1.3.6.1.2.1.1.1.0", {:string, "Default System Description"}}
      _ -> {oid, {:end_of_mib_view, nil}}
    end
  end

  defp get_fallback_bulk_oids(start_oid, max_repetitions, state) do
    # Simple fallback that generates a few basic interface OIDs
    case start_oid do
      "1.3.6.1.2.1.2.2.1.1" ->
        # Generate interface indices
        for i <- 1..min(max_repetitions, 3) do
          {"1.3.6.1.2.1.2.2.1.1.#{i}", {:integer, i}}
        end
      "1.3.6.1.2.1.2.2.1.10" ->
        # Generate interface octet counters  
        for i <- 1..min(max_repetitions, 3) do
          {"1.3.6.1.2.1.2.2.1.10.#{i}", {:counter32, i * 1000}}
        end
      _ ->
        # Just return one fallback OID
        [get_fallback_next_oid(start_oid, state)]
    end
  end
  
end