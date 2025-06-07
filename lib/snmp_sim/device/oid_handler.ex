defmodule SnmpSim.Device.OidHandler do
  @moduledoc """
  OID handling and value generation for SNMP device simulation.
  Handles dynamic OID value generation, interface statistics, and MIB walking.
  """
  # Suppress Dialyzer warnings for pattern matches and guards
  @dialyzer [
    {:nowarn_function, get_dynamic_oid_value: 2},
    {:nowarn_function, walk_oid_recursive: 3}
  ]
  require Logger
  alias SnmpSim.MIB.SharedProfiles

  # I'll move the OID handling functions here from device.ex
  # This will be populated in the next step

  # Helper to extract OID from different varbind formats
  def extract_oid(varbind) do
    case varbind do
      {oid, _type, _value} ->
        oid

      {oid, _value} ->
        oid

      _ ->
        ""
    end
  end

  def oid_to_string(oid) when is_list(oid), do: Enum.join(oid, ".")
  def oid_to_string(oid) when is_binary(oid), do: oid
  def oid_to_string(oid), do: to_string(oid)

  def string_to_oid_list(oid_string) when is_binary(oid_string) do
    case oid_string do
      "" ->
        []

      _ ->
        try do
          oid_string
          |> String.split(".")
          |> Enum.map(&String.to_integer/1)
        rescue
          _ -> []
        end
    end
  end

  def string_to_oid_list(oid) when is_list(oid), do: oid
  def string_to_oid_list(oid), do: oid

  def extract_type_and_value({type, value}) do
    {type, value}
  end

  def extract_type_and_value(value) when is_binary(value) do
    {:octet_string, value}
  end

  def extract_type_and_value(value) when is_integer(value) do
    {:integer, value}
  end

  def extract_type_and_value(value) do
    {:unknown, value}
  end

  def get_oid_value(oid, state) do
    # Update last access time
    new_state = %{state | last_access: System.monotonic_time(:millisecond)}

    # Normalize OID to string format for consistent handling
    oid_string =
      case oid do
        oid when is_binary(oid) ->
          oid

        oid when is_list(oid) ->
          case SnmpLib.OID.list_to_string(oid) do
            {:ok, str} -> str
            {:error, _} -> Enum.join(oid, ".")
          end

        _ ->
          to_string(oid)
      end

    # Check for special dynamic OIDs first - these should always use typed responses
    cond do
      oid_string == "1.3.6.1.2.1.1.3.0" ->
        # sysUpTime - always dynamic
        get_dynamic_oid_value(oid_string, new_state)

      oid_string == "1.3.6.1.2.1.1.2.0" ->
        # sysObjectID - always use typed response
        get_dynamic_oid_value(oid_string, new_state)

      String.starts_with?(oid_string, "1.3.6.1.2.1.2.2.1.") ->
        # Interface table OIDs - always use typed responses
        get_dynamic_oid_value(oid_string, new_state)

      true ->
        # Try to get value from SharedProfiles first (if available)
        try do
          device_state = build_device_state(state)

          case SharedProfiles.get_oid_value(state.device_type, oid_string, device_state) do
            {:ok, value} ->
              {:ok, value}

            {:error, :no_such_object} ->
              # Fallback to device-specific dynamic OIDs
              get_dynamic_oid_value(oid_string, new_state)

            {:error, :no_such_name} ->
              # OID not found in SharedProfiles, fallback to dynamic OIDs
              get_dynamic_oid_value(oid_string, new_state)

            {:error, :device_type_not_found} ->
              # Device type not loaded in SharedProfiles, fallback to dynamic OIDs
              get_dynamic_oid_value(oid_string, new_state)
          end
        catch
          :exit, {:noproc, _} ->
            # SharedProfiles not available, use fallback directly
            get_dynamic_oid_value(oid_string, new_state)

          :exit, reason ->
            Logger.debug(
              "SharedProfiles unavailable (#{inspect(reason)}), using fallback for OID #{oid_string}"
            )

            get_dynamic_oid_value(oid_string, new_state)
        end
    end
  end

  def get_dynamic_oid_value("1.3.6.1.2.1.1.3.0", state) do
    # sysUpTime - calculate based on uptime_start
    uptime_ticks = calculate_uptime_ticks(state)
    {:ok, {:timeticks, uptime_ticks}}
  end

  def get_dynamic_oid_value(oid, state) do
    # Normalize OID to string format using SnmpLib.OID
    oid_string =
      case oid do
        oid when is_binary(oid) ->
          oid

        oid when is_list(oid) ->
          case SnmpLib.OID.list_to_string(oid) do
            {:ok, str} -> str
            {:error, _} -> Enum.join(oid, ".")
          end

        _ ->
          to_string(oid)
      end

    # Check if this OID matches any counter or gauge patterns
    cond do
      Map.has_key?(state.counters, oid_string) ->
        {:ok, {:counter32, Map.get(state.counters, oid_string, 0)}}

      Map.has_key?(state.gauges, oid_string) ->
        {:ok, {:gauge32, Map.get(state.gauges, oid_string, 0)}}

      # Fallback to basic system OIDs if not found in SharedProfiles
      oid_string == "1.3.6.1.2.1.1.1.0" ->
        # sysDescr - system description (OCTET STRING)
        device_type_str =
          case state.device_type do
            :cable_modem -> "Motorola SB6141 DOCSIS 3.0 Cable Modem"
            :cmts -> "Cisco CMTS Cable Modem Termination System"
            :router -> "Cisco Router"
            _ -> "SNMP Simulator Device"
          end

        {:ok, device_type_str}

      oid_string == "1.3.6.1.2.1.1.2.0" ->
        # sysObjectID - object identifier (OBJECT IDENTIFIER)
        {:ok, {:object_identifier, "1.3.6.1.4.1.4491.2.4.1"}}

      oid_string == "1.3.6.1.2.1.1.4.0" ->
        # sysContact - contact info (OCTET STRING)
        {:ok, "admin@example.com"}

      oid_string == "1.3.6.1.2.1.1.5.0" ->
        # sysName - system name (OCTET STRING)
        device_name = state.device_id || "device_#{state.port}"
        {:ok, device_name}

      oid_string == "1.3.6.1.2.1.1.6.0" ->
        # sysLocation - location (OCTET STRING)
        {:ok, "Customer Premises"}

      oid_string == "1.3.6.1.2.1.1.7.0" ->
        # sysServices - services (INTEGER)
        {:ok, 2}

      oid_string == "1.3.6.1.2.1.2.1.0" ->
        # ifNumber - number of network interfaces (INTEGER)
        {:ok, 2}

      # Interface table OIDs (1.3.6.1.2.1.2.2.1.x.y where x is column, y is interface index)
      String.starts_with?(oid_string, "1.3.6.1.2.1.2.2.1.") ->
        handle_interface_oid(oid_string, state)

      # High Capacity (HC) Interface Counters (1.3.6.1.2.1.31.1.1.1.x.y)
      String.starts_with?(oid_string, "1.3.6.1.2.1.31.1.1.1.") ->
        handle_hc_interface_oid(oid_string, state)

      # DOCSIS Cable Modem SNR (1.3.6.1.2.1.10.127.1.1.4.1.5.x)
      String.starts_with?(oid_string, "1.3.6.1.2.1.10.127.1.1.4.1.5.") ->
        handle_docsis_snr_oid(oid_string, state)

      # Host Resources MIB - Processor Load (1.3.6.1.2.1.25.3.3.1.2.x)
      String.starts_with?(oid_string, "1.3.6.1.2.1.25.3.3.1.2.") ->
        handle_host_processor_oid(oid_string, state)

      # Host Resources MIB - Storage Used (1.3.6.1.2.1.25.2.3.1.6.x)
      String.starts_with?(oid_string, "1.3.6.1.2.1.25.2.3.1.6.") ->
        handle_host_storage_oid(oid_string, state)

      true ->
        {:error, :no_such_name}
    end
  end

  def get_next_oid_value(oid, state) do
    try do
      device_state = build_device_state(state)

      case SharedProfiles.get_next_oid(oid, device_state) do
        {:ok, next_oid} ->
          # Get the value for the next OID
          case SharedProfiles.get_oid_value(state.device_type, next_oid, device_state) do
            {:ok, {type, value}} ->
              case {next_oid, type, value} do
                {_next_oid, :end_of_mib_view, {:end_of_mib_view, nil}} ->
                  {:error, :end_of_mib_view}

                {next_oid, _type, value} ->
                  {:ok, {oid_to_string(next_oid), type, value}}
              end
          end

        :end_of_mib ->
          {:error, :end_of_mib_view}

        {:error, :end_of_mib} ->
          {:error, :end_of_mib_view}

        {:error, :device_type_not_found} ->
          case get_fallback_next_oid(oid, state) do
            {_next_oid, :end_of_mib_view, {:end_of_mib_view, nil}} -> {:error, :end_of_mib_view}
            {next_oid, type, value} -> {:ok, {next_oid, type, value}}
          end

        {:error, _reason} ->
          case get_fallback_next_oid(oid, state) do
            {_next_oid, :end_of_mib_view, {:end_of_mib_view, nil}} -> {:error, :end_of_mib_view}
            {next_oid, type, value} -> {:ok, {next_oid, type, value}}
          end
      end
    catch
      :exit, {:noproc, _} ->
        case get_fallback_next_oid(oid, state) do
          {_next_oid, :end_of_mib_view, {:end_of_mib_view, nil}} -> {:error, :end_of_mib_view}
          {next_oid, type, value} -> {:ok, {next_oid, type, value}}
        end

      :exit, reason ->
        Logger.debug(
          "SharedProfiles unavailable (#{inspect(reason)}), using fallback for OID #{oid}"
        )

        case get_fallback_next_oid(oid, state) do
          {_next_oid, :end_of_mib_view, {:end_of_mib_view, nil}} -> {:error, :end_of_mib_view}
          {next_oid, type, value} -> {:ok, {next_oid, type, value}}
        end
    end
  end

  def get_bulk_oid_values(oid, count, state) do
    try do
      device_state = build_device_state(state)

      case SharedProfiles.get_bulk_oids(oid, count, device_state) do
        {:ok, oid_values} -> {:ok, oid_values}
        {:error, _reason} -> {:ok, get_fallback_bulk_oids(oid, count, state)}
      end
    catch
      :exit, {:noproc, _} ->
        {:ok, get_fallback_bulk_oids(oid, count, state)}

      :exit, reason ->
        Logger.debug(
          "SharedProfiles unavailable (#{inspect(reason)}), using fallback for OID #{oid}"
        )

        {:ok, get_fallback_bulk_oids(oid, count, state)}
    end
  end

  def walk_oid_values(oid, state) do
    # Simple walk implementation - get next OIDs until end of MIB or subtree
    walk_oid_recursive(oid, state, [])
  end

  def walk_oid_recursive(oid, state, acc) when length(acc) < 100 do
    case get_next_oid_value(oid, state) do
      {:ok, {next_oid, _type, value}} ->
        # Convert both OIDs to strings for comparison
        oid_str = oid_to_string(oid)
        next_oid_str = oid_to_string(next_oid)

        # Check if still in the same subtree
        if String.starts_with?(next_oid_str, oid_str) do
          walk_oid_recursive(next_oid_str, state, [{next_oid_str, value} | acc])
        else
          {:ok, Enum.reverse(acc)}
        end

      {:error, :end_of_mib_view} ->
        {:ok, Enum.reverse(acc)}

      {:error, _reason} ->
        {:ok, Enum.reverse(acc)}
    end
  end

  def walk_oid_recursive(_oid, _state, acc) do
    # Limit recursion depth to prevent infinite loops
    {:ok, Enum.reverse(acc)}
  end

  def get_fallback_next_oid(oid, state) do
    # Convert OID to string format for pattern matching
    oid_string =
      case oid do
        oid when is_list(oid) -> oid_to_string(oid)
        oid when is_binary(oid) -> oid
        _ -> to_string(oid)
      end

    Logger.debug(
      "get_fallback_next_oid called with OID: #{inspect(oid)} -> string: #{oid_string}"
    )

    result =
      case oid_string do
        "1.3.6.1.2.1.1.1.0" ->
          {"1.3.6.1.2.1.1.2.0", :object_identifier, "1.3.6.1.4.1.4491.2.4.1"}

        "1.3.6.1.2.1.1.2.0" ->
          {"1.3.6.1.2.1.1.3.0", :timeticks, calculate_uptime_ticks(state)}

        "1.3.6.1.2.1.1.3.0" ->
          {"1.3.6.1.2.1.1.4.0", :octet_string, "admin@example.com"}

        "1.3.6.1.2.1.1.4.0" ->
          device_name = state.device_id || "device_#{state.port}"
          {"1.3.6.1.2.1.1.5.0", :octet_string, device_name}

        "1.3.6.1.2.1.1.5.0" ->
          {"1.3.6.1.2.1.1.6.0", :octet_string, "Customer Premises"}

        "1.3.6.1.2.1.1.6.0" ->
          {"1.3.6.1.2.1.1.7.0", :integer, 2}

        "1.3.6.1.2.1.2.1.0" ->
          {"1.3.6.1.2.1.2.2.1.1.1", :integer, 1}

        "1.3.6.1.2.1.2.2.1.1" ->
          {"1.3.6.1.2.1.2.2.1.1.1", :integer, 1}

        "1.3.6.1.2.1.2.2.1.1.1" ->
          {"1.3.6.1.2.1.2.2.1.1.2", :integer, 2}

        "1.3.6.1.2.1.2.2.1.2.1" ->
          {"1.3.6.1.2.1.2.2.1.2.1", :octet_string, get_interface_description(state)}

        "1.3.6.1.2.1.2.2.1.3.1" ->
          {"1.3.6.1.2.1.2.2.1.3.1", :integer, 6}

        "1.3.6.1.2.1.2.2.1.4.1" ->
          {"1.3.6.1.2.1.2.2.1.4.1", :gauge32, 100_000_000}

        # Handle various starting points for SNMP walk - all redirect to first system OID
        oid_string
        when oid_string in [
               "1.3.6.1",
               "1.3.6",
               "1.3",
               "1",
               "1.3.6.1.2",
               "1.3.6.1.2.1",
               "1.3.6.1.2.1.1"
             ] ->
          # Starting from various root points - go to first system OID
          device_type_str =
            case state.device_type do
              :cable_modem -> "Motorola SB6141 DOCSIS 3.0 Cable Modem"
              :cmts -> "Cisco CMTS Cable Modem Termination System"
              :router -> "Cisco Router"
              _ -> "SNMP Simulator Device"
            end

          {"1.3.6.1.2.1.1.1.0", :octet_string, device_type_str}

        _ ->
          # For non-existent roots, return the special end of MIB value
          oid_str =
            case oid do
              oid when is_list(oid) -> oid_to_string(oid)
              oid when is_binary(oid) -> oid
              _ -> to_string(oid)
            end

          {oid_str, :end_of_mib_view, {:end_of_mib_view, nil}}
      end

    result
  end

  def get_fallback_bulk_oids(start_oid, max_repetitions, state) do
    # Simple fallback that generates a few basic interface OIDs
    case start_oid do
      "1.3.6.1.2.1.2.2.1.1" ->
        # Generate interface indices
        for i <- 1..min(max_repetitions, 3) do
          {"1.3.6.1.2.1.2.2.1.1.#{i}", :integer, i}
        end

      "1.3.6.1.2.1.2.2.1.10" ->
        # Generate interface octet counters
        for i <- 1..min(max_repetitions, 3) do
          {"1.3.6.1.2.1.2.2.1.10.#{i}", :counter32, i * 1000}
        end

      _ ->
        # Just return one fallback OID as 3-tuple
        [get_fallback_next_oid(start_oid, state)]
    end
  end

  def handle_interface_oid(oid, state) do
    # Parse the interface OID: 1.3.6.1.2.1.2.2.1.column.interface_index
    case String.split(oid, ".") do
      ["1", "3", "6", "1", "2", "1", "2", "2", "1", column, interface_index] ->
        case {column, interface_index} do
          {"1", "1"} ->
            # ifIndex.1 - interface index (INTEGER)
            {:ok, 1}

          {"2", "1"} ->
            # ifDescr.1 - interface description (OCTET STRING)
            interface_desc =
              case state.device_type do
                :cable_modem -> "Ethernet Interface"
                :cmts -> "Cable Interface 1/0/0"
                :router -> "GigabitEthernet0/0"
                _ -> "Interface 1"
              end

            {:ok, interface_desc}

          {"3", "1"} ->
            # ifType.1 - interface type (INTEGER - 6 = ethernetCsmacd)
            {:ok, 6}

          {"4", "1"} ->
            # ifMtu.1 - MTU (INTEGER)
            {:ok, 1500}

          {"5", "1"} ->
            # ifSpeed.1 - interface speed (GAUGE32 - 100 Mbps)
            {:ok, {:gauge32, 100_000_000}}

          {"6", "1"} ->
            # ifPhysAddress.1 - MAC address (OCTET STRING)
            {:ok, "00:11:22:33:44:55"}

          {"7", "1"} ->
            # ifAdminStatus.1 - admin status (INTEGER - 1 = up)
            {:ok, 1}

          {"8", "1"} ->
            # ifOperStatus.1 - operational status (INTEGER - 1 = up)
            {:ok, 1}

          {"9", "1"} ->
            # ifLastChange.1 - last change (TimeTicks)
            {:ok, {:timeticks, 0}}

          {"10", "1"} ->
            # ifInOctets.1 - input octets (Counter32)
            base_count = 1_000_000
            increment = calculate_traffic_increment(state, :in_octets)
            {:ok, {:counter32, base_count + increment}}

          {"16", "1"} ->
            # ifOutOctets.1 - output octets (Counter32)
            base_count = 800_000
            increment = calculate_traffic_increment(state, :out_octets)
            {:ok, {:counter32, base_count + increment}}

          {"11", "1"} ->
            # ifInUcastPkts.1 - input unicast packets (Counter32)
            base_count = 50_000
            increment = calculate_packet_increment(state, :in_ucast_pkts)
            {:ok, {:counter32, base_count + increment}}

          {"17", "1"} ->
            # ifOutUcastPkts.1 - output unicast packets (Counter32)
            base_count = 40_000
            increment = calculate_packet_increment(state, :out_ucast_pkts)
            {:ok, {:counter32, base_count + increment}}

          {"14", "1"} ->
            # ifInErrors.1 - input errors (Counter32)
            base_count = 5
            increment = calculate_error_increment(state, :in_errors)
            {:ok, {:counter32, base_count + increment}}

          {"20", "1"} ->
            # ifOutErrors.1 - output errors (Counter32)
            base_count = 3
            increment = calculate_error_increment(state, :out_errors)
            {:ok, {:counter32, base_count + increment}}

          _ ->
            # Unsupported interface column or index
            {:error, :no_such_name}
        end

      _ ->
        # Invalid OID format
        {:error, :no_such_name}
    end
  end

  def handle_hc_interface_oid(oid, state) do
    # Parse HC interface OID: 1.3.6.1.2.1.31.1.1.1.column.interface_index
    case String.split(oid, ".") do
      ["1", "3", "6", "1", "2", "1", "31", "1", "1", "1", column, interface_index] ->
        case {column, interface_index} do
          {"6", "1"} ->
            # ifHCInOctets.1 - high capacity input octets (Counter64)
            # 50GB base
            base_count = 50_000_000_000
            increment = calculate_traffic_increment(state, :hc_in_octets)
            {:ok, {:counter64, base_count + increment}}

          {"10", "1"} ->
            # ifHCOutOctets.1 - high capacity output octets (Counter64)
            # 35GB base
            base_count = 35_000_000_000
            increment = calculate_traffic_increment(state, :hc_out_octets)
            {:ok, {:counter64, base_count + increment}}

          _ ->
            {:error, :no_such_name}
        end

      _ ->
        {:error, :no_such_name}
    end
  end

  def handle_docsis_snr_oid(oid, state) do
    # Parse DOCSIS SNR OID: 1.3.6.1.2.1.10.127.1.1.4.1.5.channel_index
    case String.split(oid, ".") do
      ["1", "3", "6", "1", "2", "1", "10", "127", "1", "1", "4", "1", "5", channel_index] ->
        case channel_index do
          "3" ->
            # docsIfSigQSignalNoise.3 - SNR for downstream channel 3
            snr_value = calculate_snr_gauge(state)
            {:ok, {:gauge32, snr_value}}

          _ ->
            {:error, :no_such_name}
        end

      _ ->
        {:error, :no_such_name}
    end
  end

  def handle_host_processor_oid(oid, state) do
    # Parse Host Resources processor OID: 1.3.6.1.2.1.25.3.3.1.2.processor_index
    case String.split(oid, ".") do
      ["1", "3", "6", "1", "2", "1", "25", "3", "3", "1", "2", processor_index] ->
        case processor_index do
          "1" ->
            # hrProcessorLoad.1 - CPU utilization percentage
            cpu_load = calculate_cpu_gauge(state)
            {:ok, {:gauge32, cpu_load}}

          _ ->
            {:error, :no_such_name}
        end

      _ ->
        {:error, :no_such_name}
    end
  end

  def handle_host_storage_oid(oid, state) do
    # Parse Host Resources storage OID: 1.3.6.1.2.1.25.2.3.1.6.storage_index
    case String.split(oid, ".") do
      ["1", "3", "6", "1", "2", "1", "25", "2", "3", "1", "6", storage_index] ->
        case storage_index do
          "1" ->
            # hrStorageUsed.1 - Storage units used (typically memory)
            storage_used = calculate_storage_gauge(state)
            {:ok, {:gauge32, storage_used}}

          _ ->
            {:error, :no_such_name}
        end

      _ ->
        {:error, :no_such_name}
    end
  end

  def calculate_uptime(%{uptime_start: uptime_start}) when is_integer(uptime_start) do
    current_time = :erlang.monotonic_time()
    uptime_monotonic = current_time - uptime_start
    :erlang.convert_time_unit(uptime_monotonic, :native, :millisecond)
  end

  def calculate_uptime(_state) do
    0
  end

  def calculate_uptime_ticks(state) do
    # SNMP TimeTicks are in 1/100th of a second (centiseconds)
    uptime_milliseconds = calculate_uptime(state)
    # Convert milliseconds to centiseconds
    div(uptime_milliseconds, 10)
  end

  def build_device_state(state) do
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

  def get_interface_description(state) do
    case state.device_type do
      :cable_modem -> "Ethernet Interface"
      :cmts -> "Cable Interface 1/0/0"
      :router -> "GigabitEthernet0/0"
      _ -> "Interface 1"
    end
  end

  def calculate_traffic_increment(state, counter_type) do
    uptime_seconds = div(calculate_uptime(state), 1000)

    # Base rate depends on device type and counter type
    base_rate =
      case {state.device_type, counter_type} do
        # ~1 Mbps
        {:cable_modem, :in_octets} -> 125_000
        # ~500 Kbps
        {:cable_modem, :out_octets} -> 62_500
        # ~10 Mbps
        {:cable_modem, :hc_in_octets} -> 1_250_000
        # ~5 Mbps
        {:cable_modem, :hc_out_octets} -> 625_000
        # ~100 Mbps
        {:cmts, :in_octets} -> 12_500_000
        # ~100 Mbps
        {:cmts, :out_octets} -> 12_500_000
        # ~1 Gbps
        {:cmts, :hc_in_octets} -> 125_000_000
        # ~1 Gbps
        {:cmts, :hc_out_octets} -> 125_000_000
        # Default ~80 Kbps
        _ -> 10_000
      end

    # Add time-of-day variation (peak evening hours)
    time_factor = get_time_factor()

    # Higher utilization = more errors (congestion)
    # 0.6x to 2.4x
    utilization_impact = 1.0 + (time_factor - 0.8) * 2.0

    # Signal quality impact (simulated via random factor)
    # 0.7 to 1.3
    signal_quality = 0.7 + :rand.uniform(6) / 10
    # Worse signal = more errors
    signal_impact = 2.0 - signal_quality

    # Calculate total increment
    rate_with_variation = base_rate * utilization_impact * signal_impact
    total_increment = trunc(rate_with_variation * uptime_seconds)

    # Add some accumulated variance
    # 5% base variance
    base_variance = div(total_increment, 20)
    variance = :rand.uniform(base_variance * 2) - base_variance

    max(0, total_increment + variance)
  end

  def calculate_packet_increment(state, counter_type) do
    uptime_seconds = div(calculate_uptime(state), 1000)

    # Packet rates are typically much lower than byte rates
    # Average packet size ~1000 bytes for mixed traffic
    base_pps =
      case {state.device_type, counter_type} do
        # ~125 pps
        {:cable_modem, :in_ucast_pkts} -> 125
        # ~63 pps
        {:cable_modem, :out_ucast_pkts} -> 63
        # ~12.5K pps
        {:cmts, :in_ucast_pkts} -> 12_500
        # ~12.5K pps
        {:cmts, :out_ucast_pkts} -> 12_500
        # Default ~10 pps
        _ -> 10
      end

    # Add time-of-day variation
    time_factor = get_time_factor()
    # -15% to +15%
    jitter = :rand.uniform(31) - 15
    jitter_factor = 1.0 + jitter / 100.0

    # Calculate total packets
    rate_with_variation = trunc(base_pps * time_factor * jitter_factor)
    total_packets = rate_with_variation * uptime_seconds

    # Add some accumulated variance
    # ~7% variance
    base_variance = div(total_packets, 15)
    variance = :rand.uniform(base_variance * 2) - base_variance

    max(0, total_packets + variance)
  end

  def calculate_error_increment(state, counter_type) do
    uptime_seconds = div(calculate_uptime(state), 1000)

    # Error rates should be very low under normal conditions
    # Higher during poor signal quality or high utilization
    base_error_rate =
      case {state.device_type, counter_type} do
        # ~1 error per 100 seconds
        {:cable_modem, :in_errors} -> 0.01
        # ~1 error per 200 seconds
        {:cable_modem, :out_errors} -> 0.005
        # ~1 error per 10 seconds (more traffic)
        {:cmts, :in_errors} -> 0.1
        # ~1 error per 20 seconds
        {:cmts, :out_errors} -> 0.05
        # Very low default
        _ -> 0.001
      end

    # Environmental factors affect error rates
    time_factor = get_time_factor()

    # Higher utilization = more errors (congestion)
    # 0.6x to 2.4x
    utilization_impact = 1.0 + (time_factor - 0.8) * 2.0

    # Signal quality impact (simulated via random factor)
    # 0.7 to 1.3
    signal_quality = 0.7 + :rand.uniform(6) / 10
    # Worse signal = more errors
    signal_impact = 2.0 - signal_quality

    # Calculate error increment
    effective_rate = base_error_rate * utilization_impact * signal_impact
    total_errors = trunc(effective_rate * uptime_seconds)

    # Add burst errors occasionally
    # 5% chance of error burst
    burst_probability = 0.05

    if :rand.uniform() < burst_probability do
      # 5-15 extra errors
      burst_errors = :rand.uniform(10) + 5
      max(0, total_errors + burst_errors)
    else
      total_errors
    end
  end

  def calculate_snr_gauge(state) do
    # Base SNR for cable modem (typically 25-40 dB, higher is better)
    base_snr =
      case state.device_type do
        # Good signal quality
        :cable_modem -> 32
        # Default
        _ -> 25
      end

    # Add environmental factors
    time_factor = get_time_factor()
    # -3 to +3 dB weather variation
    weather_impact = :rand.uniform(6) - 3

    # Traffic load affects SNR (higher utilization = slightly lower SNR)
    # Small impact
    utilization_factor = 1.0 - (time_factor - 0.7) * 0.1

    # Calculate final SNR with realistic bounds
    snr = trunc(base_snr * utilization_factor + weather_impact)

    # Clamp to realistic cable modem SNR range (15-45 dB)
    max(15, min(45, snr))
  end

  def calculate_cpu_gauge(state) do
    # Base CPU load depends on device type
    base_cpu =
      case state.device_type do
        # Light load for residential device
        :cable_modem -> 15
        # Higher load for head-end equipment
        :cmts -> 45
        # Moderate load for network equipment
        :switch -> 25
        # Higher load for routing
        :router -> 35
        # Default
        _ -> 20
      end

    # Add time-of-day variation (more load during peak hours)
    time_factor = get_time_factor()
    # 0-14% additional load during peak
    time_cpu_impact = trunc((time_factor - 0.8) * 20)

    # Add traffic correlation (higher traffic = higher CPU)
    # Cap at 1.2x
    traffic_factor = min(time_factor, 1.2)
    # 0-3% additional load
    traffic_cpu_impact = trunc((traffic_factor - 1.0) * 15)

    # Add random variation for realistic simulation
    # -10% to +10%
    cpu_jitter = :rand.uniform(21) - 10
    jitter_impact = trunc(base_cpu * (cpu_jitter / 100.0))

    # Occasional CPU spikes (process startup, background tasks)
    # 2% chance
    spike_probability = 0.02

    spike_impact =
      if :rand.uniform() < spike_probability do
        # 10-40% spike
        :rand.uniform(30) + 10
      else
        0
      end

    # Calculate final CPU percentage
    final_cpu = base_cpu + time_cpu_impact + traffic_cpu_impact + jitter_impact + spike_impact

    # Clamp to realistic range (0-100%)
    max(0, min(100, final_cpu))
  end

  def calculate_storage_gauge(state) do
    # Base storage usage depends on device type (in allocation units)
    # Typical allocation unit is 1KB, so values represent KB used
    base_storage =
      case state.device_type do
        # ~64MB for embedded device
        :cable_modem -> 65_536
        # ~512MB for head-end equipment
        :cmts -> 524_288
        # ~128MB for network equipment
        :switch -> 131_072
        # ~256MB for routing equipment
        :router -> 262_144
        # ~32MB default
        _ -> 32_768
      end

    # Add uptime-based growth (memory leaks, log files, etc.)
    # Convert to hours
    uptime_hours = div(calculate_uptime(state), 3_600_000)
    # 0.1% growth per hour
    growth_factor = 1.0 + uptime_hours * 0.001

    # Add traffic-based memory usage (buffers, connection tables)
    time_factor = get_time_factor()
    # Up to 1% more during peak
    traffic_memory_factor = 1.0 + (time_factor - 0.8) * 0.05

    # Add random variation for cache usage, temporary files, etc.
    # -5% to +5%
    usage_jitter = :rand.uniform(11) - 5
    jitter_factor = 1.0 + usage_jitter / 100.0

    # Calculate final storage usage
    final_storage = trunc(base_storage * growth_factor * traffic_memory_factor * jitter_factor)

    # Ensure reasonable bounds
    # Never below 80% of base
    min_storage = trunc(base_storage * 0.8)
    # Never above 130% of base
    max_storage = trunc(base_storage * 1.3)

    max(min_storage, min(max_storage, final_storage))
  end

  def get_time_factor do
    # Simple time-of-day factor (peak at 8-10 PM)
    hour = DateTime.utc_now().hour

    case hour do
      # Peak evening
      h when h >= 20 and h <= 22 -> 1.5
      # Early evening
      h when h >= 18 and h <= 19 -> 1.3
      # Business hours
      h when h >= 8 and h <= 17 -> 1.0
      # Overnight
      h when h >= 0 and h <= 6 -> 0.6
      # Other times
      _ -> 0.8
    end
  end


  def calculate_interface_utilization(_state) do
    # Calculate based on current traffic levels
    # For now, return a random utilization between 0.1 and 0.8
    0.1 + :rand.uniform() * 0.7
  end

  def calculate_signal_quality(_state) do
    # Calculate signal quality (0.0 to 1.0)
    # Could be based on SNR, power levels, etc.
    base_quality = 0.8
    random_variation = (:rand.uniform() - 0.5) * 0.2
    max(0.0, min(1.0, base_quality + random_variation))
  end

  def calculate_cpu_utilization(state) do
    # CPU utilization often correlates with network activity
    interface_util = calculate_interface_utilization(state)
    base_cpu = 0.2 + interface_util * 0.4
    random_variation = (:rand.uniform() - 0.5) * 0.1
    max(0.0, min(1.0, base_cpu + random_variation))
  end

  def calculate_temperature(state) do
    # Device temperature in Celsius
    # Could be affected by CPU load, ambient temperature, etc.
    base_temp = 35.0
    cpu_util = calculate_cpu_utilization(state)
    # Up to 15°C increase under load
    load_factor = cpu_util * 15.0
    ambient_variation = (:rand.uniform() - 0.5) * 10.0

    base_temp + load_factor + ambient_variation
  end

  def calculate_error_rate(state) do
    # Error rate as a percentage
    signal_quality = calculate_signal_quality(state)
    # Up to 5% errors with poor signal
    base_error_rate = (1.0 - signal_quality) * 0.05
    max(0.0, base_error_rate)
  end

  def calculate_health_score(state) do
    # Overall device health score (0.0 to 1.0)
    signal_quality = calculate_signal_quality(state)
    error_rate = calculate_error_rate(state)
    uptime = calculate_uptime(state)

    # Health improves with good signal, low errors, and stable uptime
    # Normalize to days
    uptime_factor = min(1.0, uptime / 86400.0)
    health = (signal_quality + (1.0 - error_rate) + uptime_factor) / 3.0
    max(0.0, min(1.0, health))
  end

  def build_correlation_factors(_state) do
    # Build correlation factors for related OIDs
    # This could be expanded to track actual relationships
    %{}
  end

end
