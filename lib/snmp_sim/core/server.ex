defmodule SnmpSim.Core.Server do
  @moduledoc """
  High-performance UDP server for SNMP request handling.
  Supports concurrent packet processing with minimal latency.
  """

  use GenServer
  require Logger
  alias SnmpLib.PDU, as: PDU

  # Suppress Dialyzer warnings for async functions and pattern matches
  @dialyzer [
    {:nowarn_function, process_snmp_request_async: 5},
    {:nowarn_function, send_response_async: 4}
  ]

  defstruct [
    :socket,
    :port,
    :device_handler,
    :community,
    :stats
  ]

  @default_community "public"
  @socket_opts [:binary, {:active, true}, {:reuseaddr, true}, {:ip, {0, 0, 0, 0}}]

  @doc """
  Start an SNMP UDP server on the specified port.

  ## Options

  - `:community` - SNMP community string (default: "public")
  - `:device_handler` - Module or function to handle device requests
  - `:socket_opts` - Additional socket options

  ## Examples

      {:ok, server} = SnmpSim.Core.Server.start_link(9001,
        community: "public",
        device_handler: &MyDevice.handle_request/2
      )

  """
  def start_link(port, opts \\ []) do
    GenServer.start_link(__MODULE__, {port, opts})
  end

  @doc """
  Get server statistics.
  """
  def get_stats(server_pid) do
    GenServer.call(server_pid, :get_stats)
  end

  @doc """
  Update the device handler function.
  """
  def set_device_handler(server_pid, handler) do
    GenServer.call(server_pid, {:set_device_handler, handler})
  end

  # GenServer callbacks

  @impl true
  def init({port, opts}) do
    community = Keyword.get(opts, :community, @default_community)
    device_handler = Keyword.get(opts, :device_handler)
    socket_opts = Keyword.get(opts, :socket_opts, []) ++ @socket_opts

    case :gen_udp.open(port, socket_opts) do
      {:ok, socket} ->
        # Debug: Check socket info
        case :inet.sockname(socket) do
          {:ok, {ip, bound_port}} ->
            Logger.info("SNMP server started on port #{port}, socket bound to #{:inet.ntoa(ip)}:#{bound_port}")
          {:error, reason} ->
            Logger.error("Failed to get socket name: #{inspect(reason)}")
        end

        state = %__MODULE__{
          socket: socket,
          port: port,
          device_handler: device_handler,
          community: community,
          stats: init_stats()
        }

        {:ok, state}

      {:error, reason} ->
        Logger.error("Failed to start SNMP server on port #{port}: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state.stats, state}
  end

  @impl true
  def handle_call({:set_device_handler, handler}, _from, state) do
    new_state = %{state | device_handler: handler}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info({:udp, socket, client_ip, client_port, packet}, %{socket: socket} = state) do
    Logger.debug("Received UDP packet from #{:inet.ntoa(client_ip)}:#{client_port}, #{byte_size(packet)} bytes")

    # Update stats
    new_stats = update_stats(state.stats, :packets_received)
    final_state = %{state | stats: new_stats}

    # Process SNMP packet asynchronously for better throughput
    # Pass server PID to avoid process identity issues
    server_pid = self()
    Task.start(fn ->
      handle_snmp_packet_async(server_pid, state, client_ip, client_port, packet)
    end)

    {:noreply, final_state}
  end

  @impl true
  def handle_info({:udp_closed, socket}, %{socket: socket} = state) do
    Logger.warning("SNMP server socket closed unexpectedly")
    {:stop, :socket_closed, state}
  end

  @impl true
  def handle_info({:update_stats, stat_type}, state) do
    new_stats = update_stats(state.stats, stat_type)
    {:noreply, %{state | stats: new_stats}}
  end

  @impl true
  def handle_info({:update_stats, stat_type, value}, state) do
    new_stats = update_stats(state.stats, stat_type, value)
    {:noreply, %{state | stats: new_stats}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    :gen_udp.close(state.socket)
    :ok
  end

  # Private functions

  defp handle_snmp_packet_async(server_pid, state, client_ip, client_port, packet) do
    start_time = :erlang.monotonic_time()

    # Debug: Log raw packet information
    packet_size = byte_size(packet)
    packet_hex = Base.encode16(packet)
    Logger.debug("Received SNMP packet from #{format_ip(client_ip)}:#{client_port}")
    Logger.debug("Packet size: #{packet_size} bytes")
    Logger.debug("Packet hex: #{packet_hex}")

    try do
      case PDU.decode_message(packet) do
        {:ok, message} ->
          Logger.debug("Decoded SNMP message: #{inspect(message)}")
          if validate_community(message, state.community) do
            Logger.debug("Processing PDU: #{inspect(message.pdu)}")
            # Create a complete PDU structure with version and community for handlers
            # Convert varbinds from {oid, type, value} to {oid, value} format for backward compatibility
            variable_bindings = case message.pdu.varbinds do
              varbinds when is_list(varbinds) ->
                Enum.map(varbinds, fn
                  {oid, _type, value} -> {oid, value}
                  {oid, value} -> {oid, value}
                end)
            end

            complete_pdu = %PDU{
              version: message.version,
              community: message.community,
              pdu_type: message.pdu.type,
              request_id: message.pdu.request_id,
              error_status: message.pdu[:error_status] || 0,
              error_index: message.pdu[:error_index] || 0,
              variable_bindings: variable_bindings,
              max_repetitions: message.pdu[:max_repetitions] || 0,
              non_repeaters: message.pdu[:non_repeaters] || 0
            }
            process_snmp_request_async(server_pid, state, client_ip, client_port, complete_pdu)
          else
            Logger.warning("Invalid community string from #{format_ip(client_ip)}:#{client_port}")
            send(server_pid, {:update_stats, :auth_failures})
          end

        {:error, reason} ->
          Logger.warning("Failed to decode SNMP packet from #{format_ip(client_ip)}:#{client_port}: #{inspect(reason)}")
          Logger.warning("Raw packet (#{packet_size} bytes): #{packet_hex}")
          send(server_pid, {:update_stats, :decode_errors})
      end
    rescue
      error ->
        Logger.error("Error processing SNMP packet: #{inspect(error)}")
        send(server_pid, {:update_stats, :processing_errors})
    end

    # Track processing time
    end_time = :erlang.monotonic_time()
    processing_time = :erlang.convert_time_unit(end_time - start_time, :native, :microsecond)
    send(server_pid, {:update_stats, :processing_times, processing_time})
  end

  defp process_snmp_request_async(server_pid, state, client_ip, client_port, pdu) do
    case state.device_handler do
      nil ->
        # No device handler - send generic error
        error_response = PDU.create_error_response(pdu, 5, 0)  # genErr
        send_response_async(state, client_ip, client_port, error_response)
        send(server_pid, {:update_stats, :error_responses})

      handler when is_function(handler, 2) ->
        # Function handler
        case handler.(pdu, %{client_ip: client_ip, client_port: client_port}) do
          {:ok, response_pdu} ->
            send_response_async(state, client_ip, client_port, response_pdu)
            send(server_pid, {:update_stats, :successful_responses})

          {:error, error_status} ->
            error_response = PDU.create_error_response(pdu, error_status, 0)
            send_response_async(state, client_ip, client_port, error_response)
            send(server_pid, {:update_stats, :error_responses})
        end

      {module, function} ->
        # Module/function handler
        case apply(module, function, [pdu, %{client_ip: client_ip, client_port: client_port}]) do
          {:ok, response_pdu} ->
            send_response_async(state, client_ip, client_port, response_pdu)
            send(server_pid, {:update_stats, :successful_responses})

          {:error, error_status} ->
            error_response = PDU.create_error_response(pdu, error_status, 0)
            send_response_async(state, client_ip, client_port, error_response)
            send(server_pid, {:update_stats, :error_responses})
        end

      pid when is_pid(pid) ->
        # GenServer handler (e.g., Device process)
        # Check if process is alive before attempting to call it
        if Process.alive?(pid) do
          try do
            Logger.debug("Calling device handler with PDU: #{inspect(pdu)}")
            case GenServer.call(pid, {:handle_snmp, pdu, %{client_ip: client_ip, client_port: client_port}}, 5000) do
              {:ok, response_pdu} ->
                Logger.debug("Device returned response: #{inspect(response_pdu)}")
                send_response_async(state, client_ip, client_port, response_pdu)
                send(server_pid, {:update_stats, :successful_responses})

              {:error, error_status} ->
                Logger.debug("Device returned error: #{inspect(error_status)}")
                error_response = PDU.create_error_response(pdu, error_status, 0)
                send_response_async(state, client_ip, client_port, error_response)
                send(server_pid, {:update_stats, :error_responses})
            end
          catch
            :exit, {:timeout, _} ->
              Logger.warning("Device process #{inspect(pid)} timed out responding to SNMP request")
              error_response = PDU.create_error_response(pdu, 5, 0)  # genErr
              send_response_async(state, client_ip, client_port, error_response)
              send(server_pid, {:update_stats, :timeout_errors})

            :exit, {:noproc, _} ->
              # Device process has died between alive check and call
              Logger.warning("Device process #{inspect(pid)} died during SNMP request")
              error_response = PDU.create_error_response(pdu, 5, 0)  # genErr
              send_response_async(state, client_ip, client_port, error_response)
              send(server_pid, {:update_stats, :dead_process_errors})

            :exit, {:normal, _} ->
              # Device process shut down normally
              Logger.info("Device process #{inspect(pid)} shut down normally during request")
              error_response = PDU.create_error_response(pdu, 5, 0)  # genErr
              send_response_async(state, client_ip, client_port, error_response)
              send(server_pid, {:update_stats, :dead_process_errors})

            :exit, {:shutdown, _} ->
              # Device process was shutdown
              Logger.info("Device process #{inspect(pid)} was shutdown during request")
              error_response = PDU.create_error_response(pdu, 5, 0)  # genErr
              send_response_async(state, client_ip, client_port, error_response)
              send(server_pid, {:update_stats, :dead_process_errors})

            :exit, reason ->
              # Other exit reasons
              Logger.warning("Device process #{inspect(pid)} exited with reason: #{inspect(reason)}")
              error_response = PDU.create_error_response(pdu, 5, 0)  # genErr
              send_response_async(state, client_ip, client_port, error_response)
              send(server_pid, {:update_stats, :error_responses})
          end
        else
          # Process is not alive
          Logger.warning("Device process #{inspect(pid)} is not alive")
          error_response = PDU.create_error_response(pdu, 5, 0)  # genErr
          send_response_async(state, client_ip, client_port, error_response)
          send(server_pid, {:update_stats, :dead_process_errors})
        end
    end
  end


  defp send_response_async(state, client_ip, client_port, response_pdu) do
    # Create message with PDU and community string
    community = to_string(state.community || "public")
    Logger.debug("Sending response PDU: #{inspect(response_pdu)}")

    # Convert response PDU to proper message format
    response_message = case response_pdu do
      # Handle SnmpLib.PDU struct format (returned by Device module)
      %SnmpLib.PDU{request_id: request_id, error_status: error_status, error_index: error_index, variable_bindings: variable_bindings} ->
        # Convert variable_bindings from Device format to snmp_lib varbinds format
        varbinds = Enum.map(variable_bindings, fn varbind ->
          case varbind do
            {oid_string, value} when is_binary(oid_string) ->
              oid_list = String.split(oid_string, ".") |> Enum.map(&String.to_integer/1)
              # Determine type based on value
              type = case value do
                {:no_such_object, _} -> :no_such_object
                {:no_such_instance, _} -> :no_such_instance
                {:end_of_mib_view, _} -> :end_of_mib_view
                {:counter32, _} -> :counter32
                {:counter64, _} -> :counter64
                {:gauge32, _} -> :gauge32
                {:timeticks, _} -> :timeticks
                {:object_identifier, _} -> :object_identifier
                {:ip_address, _} -> :ip_address
                {:opaque, _} -> :opaque
                _ when is_binary(value) -> :string
                _ when is_integer(value) -> :integer
                _ -> :string
              end
              # Extract actual value from typed tuples
              actual_value = case value do
                {:counter32, val} -> val
                {:counter64, val} -> val
                {:gauge32, val} -> val
                {:timeticks, val} -> val
                {:object_identifier, val} -> val
                {:ip_address, val} -> val
                {:opaque, val} -> val
                {:no_such_object, _} -> :no_such_object
                {:no_such_instance, _} -> :no_such_instance
                {:end_of_mib_view, _} -> :end_of_mib_view
                other -> other
              end
              Logger.debug("Converting varbind: OID=#{oid_string}, Value=#{inspect(value)}, Type=#{type}, ActualValue=#{inspect(actual_value)}")
              {oid_list, type, actual_value}
            {oid_list, value} when is_list(oid_list) ->
              # Determine type based on value
              type = case value do
                {:no_such_object, _} -> :no_such_object
                {:no_such_instance, _} -> :no_such_instance
                {:end_of_mib_view, _} -> :end_of_mib_view
                {:counter32, _} -> :counter32
                {:counter64, _} -> :counter64
                {:gauge32, _} -> :gauge32
                {:timeticks, _} -> :timeticks
                {:object_identifier, _} -> :object_identifier
                {:ip_address, _} -> :ip_address
                {:opaque, _} -> :opaque
                _ when is_binary(value) -> :string
                _ when is_integer(value) -> :integer
                _ -> :string
              end
              # Extract actual value from typed tuples
              actual_value = case value do
                {:counter32, val} -> val
                {:counter64, val} -> val
                {:gauge32, val} -> val
                {:timeticks, val} -> val
                {:object_identifier, val} -> val
                {:ip_address, val} -> val
                {:opaque, val} -> val
                {:no_such_object, _} -> :no_such_object
                {:no_such_instance, _} -> :no_such_instance
                {:end_of_mib_view, _} -> :end_of_mib_view
                other -> other
              end
              Logger.debug("Converting varbind: OID=#{inspect(oid_list)}, Value=#{inspect(value)}, Type=#{type}, ActualValue=#{inspect(actual_value)}")
              {oid_list, type, actual_value}
            other ->
              Logger.warning("Unexpected varbind format: #{inspect(other)}")
              other
          end
        end)

        # Create response PDU manually
        response_pdu = %{
          type: :get_response,
          request_id: request_id,
          error_status: error_status,
          error_index: error_index,
          varbinds: varbinds
        }

        Logger.debug("Built response PDU: #{inspect(response_pdu)}")
        pdu = PDU.build_response(request_id, error_status, error_index, varbinds)
        message = PDU.build_message(pdu, community, :v1)
        Logger.debug("Built message: #{inspect(message)}")
        message

      # Handle map format (legacy)
      %{type: _pdu_type, request_id: request_id, error_status: error_status, error_index: error_index, varbinds: varbinds} ->
        pdu = PDU.build_response(request_id, error_status, error_index, varbinds)
        PDU.build_message(pdu, community, :v1)

      other ->
        Logger.warning("Unexpected PDU format: #{inspect(other)}")
        # Create error response
        pdu = PDU.build_response(0, 5, 0, [])  # genErr
        PDU.build_message(pdu, community, :v1)
    end

    case PDU.encode_message(response_message) do
      {:ok, encoded_packet} ->
        Logger.debug("Encoded response packet (#{byte_size(encoded_packet)} bytes): #{Base.encode16(encoded_packet)}")
        :gen_udp.send(state.socket, client_ip, client_port, encoded_packet)
        Logger.debug("Response sent to #{:inet.ntoa(client_ip)}:#{client_port}")

      {:error, reason} ->
        Logger.error("Failed to encode SNMP response: #{inspect(reason)}")
    end
  end


  defp validate_community(message, expected_community) do
    message.community == expected_community
  end

  defp format_ip({a, b, c, d}) do
    "#{a}.#{b}.#{c}.#{d}"
  end

  defp format_ip(ip) when is_binary(ip) do
    ip
  end

  defp init_stats do
    %{
      packets_received: 0,
      packets_sent: 0,
      successful_responses: 0,
      error_responses: 0,
      auth_failures: 0,
      decode_errors: 0,
      encode_errors: 0,
      send_errors: 0,
      processing_errors: 0,
      timeout_errors: 0,
      dead_process_errors: 0,
      processing_times: [],
      started_at: DateTime.utc_now()
    }
  end

  defp update_stats(stats, :processing_times, time) do
    # Keep only the last 1000 processing times for memory efficiency
    times = [time | stats.processing_times] |> Enum.take(1000)
    Map.put(stats, :processing_times, times)
  end

  defp update_stats(stats, counter_key, _value) when is_atom(counter_key) do
    Map.update(stats, counter_key, 1, &(&1 + 1))
  end

  defp update_stats(stats, counter_key) when is_atom(counter_key) do
    Map.update(stats, counter_key, 1, &(&1 + 1))
  end

end
