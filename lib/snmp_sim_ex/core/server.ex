defmodule SNMPSimEx.Core.Server do
  @moduledoc """
  High-performance UDP server for SNMP request handling.
  Supports concurrent packet processing with minimal latency.
  """

  use GenServer
  require Logger

  alias SNMPSimEx.Core.PDU

  defstruct [
    :socket,
    :port,
    :device_handler,
    :community,
    :stats
  ]

  @default_community "public"
  @socket_opts [:binary, {:active, true}, {:reuseaddr, true}]

  @doc """
  Start an SNMP UDP server on the specified port.
  
  ## Options
  
  - `:community` - SNMP community string (default: "public")
  - `:device_handler` - Module or function to handle device requests
  - `:socket_opts` - Additional socket options
  
  ## Examples
  
      {:ok, server} = SNMPSimEx.Core.Server.start_link(9001,
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
        Logger.info("SNMP server started on port #{port}")
        
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
    # Process SNMP packet asynchronously for better throughput
    # Pass server PID to avoid process identity issues
    server_pid = self()
    Task.start(fn ->
      handle_snmp_packet_async(server_pid, state, client_ip, client_port, packet)
    end)
    
    # Update stats for received packet
    new_stats = update_stats(state.stats, :packets_received)
    final_state = %{state | stats: new_stats}
    
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
  def terminate(reason, state) do
    if state.socket do
      :gen_udp.close(state.socket)
    end
    
    Logger.info("SNMP server on port #{state.port} terminated: #{inspect(reason)}")
    :ok
  end

  # Private functions

  defp handle_snmp_packet_async(server_pid, state, client_ip, client_port, packet) do
    start_time = :erlang.monotonic_time()
    
    try do
      case PDU.decode(packet) do
        {:ok, pdu} ->
          if validate_community(pdu, state.community) do
            process_snmp_request_async(server_pid, state, client_ip, client_port, pdu)
          else
            Logger.warning("Invalid community string from #{format_ip(client_ip)}:#{client_port}")
            send(server_pid, {:update_stats, :auth_failures})
          end
          
        {:error, reason} ->
          Logger.warning("Failed to decode SNMP packet from #{format_ip(client_ip)}:#{client_port}: #{inspect(reason)}")
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

  # Unused functions - kept for future use
  # defp handle_snmp_packet(state, client_ip, client_port, packet) do
  #   start_time = :erlang.monotonic_time()
  #   
  #   updated_state = try do
  #     case PDU.decode(packet) do
  #       {:ok, pdu} ->
  #         if validate_community(pdu, state.community) do
  #           process_snmp_request(state, client_ip, client_port, pdu)
  #         else
  #           Logger.warning("Invalid community string from #{format_ip(client_ip)}:#{client_port}")
  #           new_stats = update_stats(state.stats, :auth_failures)
  #           %{state | stats: new_stats}
  #         end
  #         
  #       {:error, reason} ->
  #         Logger.warning("Failed to decode SNMP packet from #{format_ip(client_ip)}:#{client_port}: #{inspect(reason)}")
  #         new_stats = update_stats(state.stats, :decode_errors)
  #         %{state | stats: new_stats}
  #     end
  #   rescue
  #     error ->
  #       Logger.error("Error processing SNMP packet: #{inspect(error)}")
  #       new_stats = update_stats(state.stats, :processing_errors)
  #       %{state | stats: new_stats}
  #   end
  #   
  #   # Track processing time
  #   end_time = :erlang.monotonic_time()
  #   processing_time = :erlang.convert_time_unit(end_time - start_time, :native, :microsecond)
  #   final_stats = update_stats(updated_state.stats, :processing_times, processing_time)
  #   %{updated_state | stats: final_stats}
  # end

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
            case GenServer.call(pid, {:handle_snmp, pdu, %{client_ip: client_ip, client_port: client_port}}, 5000) do
              {:ok, response_pdu} ->
                send_response_async(state, client_ip, client_port, response_pdu)
                send(server_pid, {:update_stats, :successful_responses})
                
              {:error, error_status} ->
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
    case PDU.encode(response_pdu) do
      {:ok, response_packet} ->
        case :gen_udp.send(state.socket, client_ip, client_port, response_packet) do
          :ok ->
            :ok
            
          {:error, reason} ->
            Logger.warning("Failed to send SNMP response to #{format_ip(client_ip)}:#{client_port}: #{inspect(reason)}")
        end
        
      {:error, reason} ->
        Logger.error("Failed to encode SNMP response: #{inspect(reason)}")
    end
  end


  defp validate_community(pdu, expected_community) do
    pdu.community == expected_community
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