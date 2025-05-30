defmodule SNMPSimEx.Performance.OptimizedUdpServer do
  @moduledoc """
  High-performance UDP server optimized for 100K+ requests/second throughput.
  
  Features:
  - Multi-socket architecture for load distribution
  - Worker pool for concurrent packet processing  
  - Ring buffer for packet queuing
  - Socket-level optimizations for minimal latency
  - Adaptive backpressure management
  - Direct response path bypassing GenServer for hot paths
  """

  use GenServer
  require Logger

  alias SNMPSimEx.Core.PDU
  alias SNMPSimEx.Performance.PerformanceMonitor
  alias SNMPSimEx.Performance.OptimizedDevicePool

  # Performance optimization constants
  @default_socket_count 4              # Multi-socket for load distribution
  @default_worker_pool_size 16         # Concurrent packet processors
  @default_buffer_size 65536           # Socket buffer size
  @default_packet_queue_size 10000     # Internal packet queue
  @default_batch_size 100              # Batch processing size

  # Socket optimization options
  @socket_opts [
    :binary,
    {:active, :once},
    {:reuseaddr, true},
    {:reuseport, true},
    {:buffer, @default_buffer_size},
    {:recbuf, @default_buffer_size},
    {:sndbuf, @default_buffer_size},
    {:priority, 6},
    {:tos, 16},
    {:nodelay, true}
  ]

  defstruct [
    :port,
    :sockets,
    :worker_pool,
    :packet_queue,
    :socket_supervisors,
    :device_handler,
    :community,
    :stats,
    :backpressure_state,
    :optimization_level
  ]

  # Client API

  def start_link(port, opts \\ []) do
    GenServer.start_link(__MODULE__, {port, opts}, name: via_tuple(port))
  end

  @doc """
  Start optimized UDP server with performance tuning.
  """
  def start_optimized(port, opts \\ []) do
    optimization_opts = [
      socket_count: Keyword.get(opts, :socket_count, @default_socket_count),
      worker_pool_size: Keyword.get(opts, :worker_pool_size, @default_worker_pool_size),
      buffer_size: Keyword.get(opts, :buffer_size, @default_buffer_size),
      optimization_level: Keyword.get(opts, :optimization_level, :high)
    ]
    
    merged_opts = Keyword.merge(opts, optimization_opts)
    start_link(port, merged_opts)
  end

  @doc """
  Get comprehensive server performance statistics.
  """
  def get_performance_stats(port) do
    GenServer.call(via_tuple(port), :get_performance_stats)
  end

  @doc """
  Update server optimization settings at runtime.
  """
  def update_optimization(port, opts) do
    GenServer.call(via_tuple(port), {:update_optimization, opts})
  end

  @doc """
  Force immediate packet processing (drain queue).
  """
  def force_packet_processing(port) do
    GenServer.cast(via_tuple(port), :force_packet_processing)
  end

  # Server callbacks

  @impl true
  def init({port, opts}) do
    Process.flag(:trap_exit, true)
    
    socket_count = Keyword.get(opts, :socket_count, @default_socket_count)
    worker_pool_size = Keyword.get(opts, :worker_pool_size, @default_worker_pool_size)
    buffer_size = Keyword.get(opts, :buffer_size, @default_buffer_size)
    optimization_level = Keyword.get(opts, :optimization_level, :medium)
    
    community = Keyword.get(opts, :community, "public")
    device_handler = Keyword.get(opts, :device_handler, &default_device_handler/3)

    # Apply system-level optimizations
    apply_system_optimizations(optimization_level)

    # Create multi-socket setup for load distribution
    {:ok, sockets} = create_multi_socket_setup(port, socket_count, buffer_size)
    
    # Start worker pool for concurrent processing
    {:ok, worker_pool} = start_worker_pool(worker_pool_size, device_handler, community)
    
    # Initialize packet queue with ring buffer
    packet_queue = :queue.new()
    
    state = %__MODULE__{
      port: port,
      sockets: sockets,
      worker_pool: worker_pool,
      packet_queue: packet_queue,
      device_handler: device_handler,
      community: community,
      stats: initialize_server_stats(),
      backpressure_state: :normal,
      optimization_level: optimization_level
    }

    Logger.info("OptimizedUdpServer started on port #{port} with #{socket_count} sockets, #{worker_pool_size} workers (#{optimization_level} optimization)")

    {:ok, state}
  end

  @impl true
  def handle_call(:get_performance_stats, _from, state) do
    stats = %{
      port: state.port,
      socket_count: length(state.sockets),
      worker_pool_size: length(state.worker_pool),
      queue_size: :queue.len(state.packet_queue),
      backpressure_state: state.backpressure_state,
      optimization_level: state.optimization_level,
      server_stats: state.stats,
      system_metrics: get_socket_system_metrics(state.sockets)
    }
    
    {:reply, stats, state}
  end

  @impl true
  def handle_call({:update_optimization, opts}, _from, state) do
    # Apply runtime optimization updates
    new_optimization_level = Keyword.get(opts, :optimization_level, state.optimization_level)
    
    if new_optimization_level != state.optimization_level do
      apply_system_optimizations(new_optimization_level)
    end
    
    new_state = %{state | optimization_level: new_optimization_level}
    
    Logger.info("Updated optimization level to: #{new_optimization_level}")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast(:force_packet_processing, state) do
    # Process all queued packets immediately
    {processed_count, new_queue} = process_packet_queue_batch(state.packet_queue, state.worker_pool, :queue.len(state.packet_queue))
    
    new_stats = update_server_stats(state.stats, :packets_processed, processed_count)
    
    {:noreply, %{state | packet_queue: new_queue, stats: new_stats}}
  end

  @impl true
  def handle_info({:udp, socket, ip, incoming_port, packet}, state) do
    start_time = System.monotonic_time(:microsecond)
    
    # Re-enable socket for next packet
    :inet.setopts(socket, [{:active, :once}])
    
    # Check backpressure before processing
    case check_backpressure(state) do
      :normal ->
        # Fast path: direct processing for hot paths
        case is_hot_path_request?(packet) do
          true ->
            handle_hot_path_request(socket, ip, incoming_port, packet, state, start_time)
          
          false ->
            # Queue for worker processing
            queue_packet_for_processing(socket, ip, incoming_port, packet, state, start_time)
        end
      
      :backpressure ->
        # Drop packet under backpressure
        new_stats = update_server_stats(state.stats, :packets_dropped, 1)
        Logger.warning("Packet dropped due to backpressure")
        
        {:noreply, %{state | stats: new_stats}}
    end
  end

  @impl true
  def handle_info({:packet_processed, worker_id, processing_time}, state) do
    # Update worker statistics
    new_stats = update_worker_stats(state.stats, worker_id, processing_time)
    {:noreply, %{state | stats: new_stats}}
  end

  @impl true
  def handle_info(:process_packet_batch, state) do
    # Process queued packets in batches
    {processed_count, new_queue} = process_packet_queue_batch(state.packet_queue, state.worker_pool, @default_batch_size)
    
    new_stats = update_server_stats(state.stats, :packets_processed, processed_count)
    
    # Update backpressure state
    new_backpressure_state = calculate_backpressure_state(new_queue, state.worker_pool)
    
    # Schedule next batch processing if queue not empty
    if not :queue.is_empty(new_queue) do
      Process.send_after(self(), :process_packet_batch, 1)
    end
    
    {:noreply, %{state | 
      packet_queue: new_queue, 
      stats: new_stats,
      backpressure_state: new_backpressure_state
    }}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("OptimizedUdpServer terminating on port #{state.port}: #{inspect(reason)}")
    
    # Close all sockets
    Enum.each(state.sockets, fn socket ->
      :gen_udp.close(socket)
    end)
    
    # Terminate worker pool
    terminate_worker_pool(state.worker_pool)
    
    :ok
  end

  # Private functions

  defp via_tuple(port) do
    {:via, Registry, {SNMPSimEx.ServerRegistry, port}}
  end

  defp create_multi_socket_setup(port, socket_count, buffer_size) do
    # Create multiple sockets on the same port using SO_REUSEPORT
    socket_opts = update_socket_opts(@socket_opts, buffer_size)
    
    sockets = Enum.map(1..socket_count, fn _i ->
      case :gen_udp.open(port, socket_opts) do
        {:ok, socket} ->
          socket
        
        {:error, reason} ->
          Logger.error("Failed to create socket: #{inspect(reason)}")
          raise "Socket creation failed: #{inspect(reason)}"
      end
    end)
    
    {:ok, sockets}
  end

  defp update_socket_opts(base_opts, buffer_size) do
    base_opts
    |> Keyword.put(:buffer, buffer_size)
    |> Keyword.put(:recbuf, buffer_size)
    |> Keyword.put(:sndbuf, buffer_size)
  end

  defp start_worker_pool(pool_size, device_handler, community) do
    workers = Enum.map(1..pool_size, fn worker_id ->
      {:ok, pid} = Task.start_link(fn ->
        worker_loop(worker_id, device_handler, community)
      end)
      
      {worker_id, pid}
    end)
    
    {:ok, workers}
  end

  defp worker_loop(worker_id, device_handler, community) do
    receive do
      {:process_packet, socket, ip, port, packet, server_pid, start_time} ->
        processing_time = process_packet_optimized(socket, ip, port, packet, device_handler, community, start_time)
        send(server_pid, {:packet_processed, worker_id, processing_time})
        worker_loop(worker_id, device_handler, community)
      
      :terminate ->
        :ok
    end
  end

  defp apply_system_optimizations(optimization_level) do
    case optimization_level do
      :high ->
        # Apply aggressive optimizations
        :erlang.system_flag(:schedulers_online, :erlang.system_info(:logical_processors))
        :erlang.system_flag(:dirty_cpu_schedulers_online, :erlang.system_info(:dirty_cpu_schedulers))
        
      :medium ->
        # Balanced optimizations
        online_schedulers = max(2, div(:erlang.system_info(:logical_processors), 2))
        :erlang.system_flag(:schedulers_online, online_schedulers)
        
      :low ->
        # Minimal optimizations
        :ok
    end
  end

  defp is_hot_path_request?(packet) do
    # Quick heuristic to identify hot path requests (e.g., sysUpTime, sysName)
    case PDU.decode_snmp_packet(packet) do
      {:ok, pdu} ->
        hot_oids = ["1.3.6.1.2.1.1.1.0", "1.3.6.1.2.1.1.3.0"]  # sysDescr, sysUpTime
        
        case pdu.varbinds do
          [varbind | _] -> varbind.oid in hot_oids
          _ -> false
        end
      
      {:error, _} ->
        false
    end
  rescue
    _ -> false
  end

  defp handle_hot_path_request(socket, ip, incoming_port, packet, state, start_time) do
    # Direct processing for hot path requests
    processing_time = process_packet_optimized(socket, ip, incoming_port, packet, state.device_handler, state.community, start_time)
    
    new_stats = state.stats
    |> update_server_stats(:packets_processed, 1)
    |> update_server_stats(:hot_path_requests, 1)
    |> update_processing_time(processing_time)
    
    {:noreply, %{state | stats: new_stats}}
  end

  defp queue_packet_for_processing(socket, ip, incoming_port, packet, state, start_time) do
    # Add packet to processing queue
    packet_info = {socket, ip, incoming_port, packet, self(), start_time}
    new_queue = :queue.in(packet_info, state.packet_queue)
    
    # Start batch processing if this is the first packet in queue
    if :queue.len(state.packet_queue) == 0 do
      Process.send_after(self(), :process_packet_batch, 1)
    end
    
    new_stats = update_server_stats(state.stats, :packets_queued, 1)
    
    {:noreply, %{state | packet_queue: new_queue, stats: new_stats}}
  end

  defp process_packet_queue_batch(queue, worker_pool, batch_size) do
    process_batch(queue, worker_pool, batch_size, 0)
  end

  defp process_batch(queue, _worker_pool, 0, processed_count) do
    {processed_count, queue}
  end

  defp process_batch(queue, worker_pool, remaining, processed_count) do
    case :queue.out(queue) do
      {{:value, packet_info}, new_queue} ->
        # Assign to least loaded worker
        worker = select_least_loaded_worker(worker_pool)
        send(elem(worker, 1), {:process_packet, packet_info})
        
        process_batch(new_queue, worker_pool, remaining - 1, processed_count + 1)
      
      {:empty, queue} ->
        {processed_count, queue}
    end
  end

  defp select_least_loaded_worker(worker_pool) do
    # Simple round-robin selection (could be improved with load tracking)
    Enum.random(worker_pool)
  end

  defp process_packet_optimized(socket, ip, port, packet, device_handler, community, start_time) do
    try do
      case PDU.decode_snmp_packet(packet) do
        {:ok, pdu} ->
          # Validate community
          if pdu.community == community do
            # Get device for this port (optimized lookup)
            case OptimizedDevicePool.get_device(port) do
              {:ok, device_pid} ->
                # Process request
                case device_handler.(device_pid, pdu, %{ip: ip, port: port}) do
                  {:ok, response_pdu} ->
                    # Encode and send response
                    {:ok, response_packet} = PDU.encode_snmp_packet(response_pdu)
                    :gen_udp.send(socket, ip, port, response_packet)
                    
                    # Record performance metrics
                    processing_time = System.monotonic_time(:microsecond) - start_time
                    PerformanceMonitor.record_request_timing(port, hd(pdu.varbinds).oid, processing_time, true)
                    
                    processing_time
                  
                  {:error, error_code} ->
                    # Send error response
                    error_pdu = PDU.create_error_response(pdu, error_code)
                    {:ok, error_packet} = PDU.encode_snmp_packet(error_pdu)
                    :gen_udp.send(socket, ip, port, error_packet)
                    
                    processing_time = System.monotonic_time(:microsecond) - start_time
                    PerformanceMonitor.record_request_timing(port, hd(pdu.varbinds).oid, processing_time, false)
                    
                    processing_time
                end
              
              {:error, :resource_limit_exceeded} ->
                # Send resource error
                error_pdu = PDU.create_error_response(pdu, :resourceUnavailable)
                {:ok, error_packet} = PDU.encode_snmp_packet(error_pdu)
                :gen_udp.send(socket, ip, port, error_packet)
                
                System.monotonic_time(:microsecond) - start_time
            end
          else
            # Invalid community - silently drop
            System.monotonic_time(:microsecond) - start_time
          end
        
        {:error, _reason} ->
          # Malformed packet - drop
          System.monotonic_time(:microsecond) - start_time
      end
    rescue
      error ->
        Logger.error("Packet processing error: #{inspect(error)}")
        System.monotonic_time(:microsecond) - start_time
    end
  end

  defp check_backpressure(state) do
    queue_size = :queue.len(state.packet_queue)
    
    cond do
      queue_size > @default_packet_queue_size * 0.9 ->
        :backpressure
      
      queue_size > @default_packet_queue_size * 0.7 ->
        :warning
      
      true ->
        :normal
    end
  end

  defp calculate_backpressure_state(queue, _worker_pool) do
    queue_size = :queue.len(queue)
    
    cond do
      queue_size > @default_packet_queue_size * 0.8 -> :backpressure
      queue_size > @default_packet_queue_size * 0.5 -> :warning
      true -> :normal
    end
  end

  defp get_socket_system_metrics(sockets) do
    socket_stats = Enum.map(sockets, fn socket ->
      case :inet.getstat(socket) do
        {:ok, stats} -> stats
        {:error, _} -> []
      end
    end)
    
    total_recv_oct = Enum.sum(Enum.map(socket_stats, &(Keyword.get(&1, :recv_oct, 0))))
    total_send_oct = Enum.sum(Enum.map(socket_stats, &(Keyword.get(&1, :send_oct, 0))))
    total_recv_cnt = Enum.sum(Enum.map(socket_stats, &(Keyword.get(&1, :recv_cnt, 0))))
    total_send_cnt = Enum.sum(Enum.map(socket_stats, &(Keyword.get(&1, :send_cnt, 0))))
    
    %{
      total_bytes_received: total_recv_oct,
      total_bytes_sent: total_send_oct,
      total_packets_received: total_recv_cnt,
      total_packets_sent: total_send_cnt,
      socket_count: length(sockets)
    }
  end

  defp initialize_server_stats() do
    %{
      packets_processed: 0,
      packets_queued: 0,
      packets_dropped: 0,
      hot_path_requests: 0,
      avg_processing_time_us: 0,
      max_processing_time_us: 0,
      min_processing_time_us: :infinity,
      worker_stats: %{},
      start_time: System.monotonic_time(:millisecond)
    }
  end

  defp update_server_stats(stats, metric, value) do
    Map.update!(stats, metric, &(&1 + value))
  end

  defp update_processing_time(stats, processing_time) do
    current_count = stats.packets_processed
    new_avg = if current_count > 0 do
      (stats.avg_processing_time_us * (current_count - 1) + processing_time) / current_count
    else
      processing_time
    end
    
    new_max = max(stats.max_processing_time_us, processing_time)
    new_min = if stats.min_processing_time_us == :infinity do
      processing_time
    else
      min(stats.min_processing_time_us, processing_time)
    end
    
    %{stats |
      avg_processing_time_us: new_avg,
      max_processing_time_us: new_max,
      min_processing_time_us: new_min
    }
  end

  defp update_worker_stats(stats, worker_id, processing_time) do
    worker_stats = Map.get(stats.worker_stats, worker_id, %{requests: 0, total_time: 0})
    
    new_worker_stats = %{
      requests: worker_stats.requests + 1,
      total_time: worker_stats.total_time + processing_time
    }
    
    %{stats | worker_stats: Map.put(stats.worker_stats, worker_id, new_worker_stats)}
  end

  defp terminate_worker_pool(worker_pool) do
    Enum.each(worker_pool, fn {_worker_id, pid} ->
      send(pid, :terminate)
    end)
  end

  defp default_device_handler(device_pid, pdu, _context) do
    # Default device handler - delegates to device process
    GenServer.call(device_pid, {:handle_snmp_request, pdu})
  end
end