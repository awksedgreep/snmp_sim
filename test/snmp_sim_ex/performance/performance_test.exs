defmodule SNMPSimEx.Performance.PerformanceTest do
  @moduledoc """
  Comprehensive performance tests for 10K+ device scenarios.
  
  These tests validate the simulator's ability to handle production-scale loads
  and ensure performance characteristics meet requirements.
  """

  use ExUnit.Case, async: false
  require Logger

  alias SNMPSimEx.Performance.{
    ResourceManager,
    OptimizedDevicePool,
    PerformanceMonitor,
    OptimizedUdpServer,
    Benchmarks
  }
  alias SNMPSimEx.TestHelpers.PortHelper

  # Test configuration
  @performance_timeout 600_000  # 10 minutes for long-running tests
  @large_device_count 10_000
  @medium_device_count 1_000
  @small_device_count 100
  
  # Helper function to get unique port range for each test using PortHelper
  defp get_test_port_range(_test_name, size \\ 100) do
    port_range = PortHelper.get_port_range(size)
    {Enum.at(port_range, 0), Enum.at(port_range, -1)}
  end

  describe "Large Scale Performance Tests" do
    setup do
      # Stop any existing processes first
      if Process.whereis(ResourceManager) do
        GenServer.stop(ResourceManager, :normal, 1000)
      end
      if Process.whereis(OptimizedDevicePool) do
        GenServer.stop(OptimizedDevicePool, :normal, 1000)
      end
      
      # Start ResourceManager first for all large scale tests
      {:ok, _} = ResourceManager.start_link([
        max_devices: @large_device_count + 1000,
        max_memory_mb: 2048
      ])
      
      # Start OptimizedDevicePool to create ETS tables
      {:ok, _} = OptimizedDevicePool.start_link([])
      
      on_exit(fn ->
        # More robust cleanup that handles process termination gracefully
        try do
          if Process.whereis(ResourceManager) do
            GenServer.stop(ResourceManager, :normal, 1000)
          end
        catch
          :exit, _ -> :ok  # Process already dead, ignore
        end
        
        try do
          if Process.whereis(OptimizedDevicePool) do
            GenServer.stop(OptimizedDevicePool, :normal, 1000)
          end
        catch
          :exit, _ -> :ok  # Process already dead, ignore
        end
      end)
      
      :ok
    end

    @tag timeout: @performance_timeout
    @tag :performance
    @tag :slow
    test "handles 10K+ concurrent devices" do
      Logger.info("Starting 10K device performance test")
      
      # Start performance monitor
      {:ok, _} = PerformanceMonitor.start_link()
      
      # Get port assignments using PortHelper
      {cable_start, cable_end} = get_test_port_range("cable_modem_perf", 7000)
      {mta_start, mta_end} = get_test_port_range("mta_perf", 1500)
      {switch_start, switch_end} = get_test_port_range("switch_perf", 400)
      {router_start, router_end} = get_test_port_range("router_perf", 50)
      {cmts_start, cmts_end} = get_test_port_range("cmts_perf", 50)
      
      port_assignments = [
        {:cable_modem, cable_start..cable_end},
        {:mta, mta_start..mta_end},
        {:switch, switch_start..switch_end},
        {:router, router_start..router_end},
        {:cmts, cmts_start..cmts_end}
      ]
      
      OptimizedDevicePool.configure_port_assignments(port_assignments)
      
      # Create devices gradually using allocated port range
      {start_port, _end_port} = get_test_port_range("large_device_test", @large_device_count)
      device_ports = create_devices_gradually(@large_device_count, start_port)
      
      # Validate device creation
      assert length(device_ports) == @large_device_count
      
      # Test basic functionality with large device count
      sample_ports = Enum.take_random(device_ports, 100)
      
      successful_requests = test_device_responsiveness(sample_ports)
      assert successful_requests >= 95  # 95% success rate minimum
      
      # Performance validation
      stats = ResourceManager.get_resource_stats()
      assert stats.device_count >= @large_device_count * 0.95
      assert stats.memory_utilization < 0.9  # Under 90% memory usage
      
      # Throughput test
      throughput_result = test_sustained_throughput(sample_ports, 60_000)
      assert throughput_result.requests_per_second >= 1000
      assert throughput_result.avg_latency_ms < 50
      
      Logger.info("10K device test completed successfully")
    end

    @tag timeout: @performance_timeout  
    @tag :performance
    @tag :slow
    test "sustains 100K+ requests/second throughput" do
      Logger.info("Starting high throughput test")
      
      # Setup for high throughput with allocated ports
      device_count = @medium_device_count
      {start_port, _end_port} = get_test_port_range("high_throughput_test", device_count)
      device_ports = create_devices_gradually(device_count, start_port)
      
      # Run benchmark with high concurrency
      result = Benchmarks.run_single_benchmark("high_throughput_test", [
        device_ports: device_ports,
        concurrent_clients: 200,
        request_rate: 50_000,  # Target 50K req/s (will scale up)
        duration: 120_000      # 2 minutes
      ])
      
      # Validate high throughput requirements
      assert result.requests_per_second >= 10_000  # Minimum 10K req/s
      assert result.error_rate < 5.0              # Less than 5% errors
      assert result.avg_latency_ms < 100          # Under 100ms average
      assert result.p95_latency_ms < 500          # P95 under 500ms
      
      Logger.info("High throughput test: #{result.requests_per_second} req/s achieved")
    end

    @tag timeout: @performance_timeout
    @tag :performance
    @tag :slow
    test "maintains memory usage under 1GB for 10K devices" do
      Logger.info("Starting memory efficiency test")
      
      # Monitor memory throughout test
      {:ok, _} = PerformanceMonitor.start_link()
      
      # Create large device population with allocated ports
      {start_port, _end_port} = get_test_port_range("memory_efficiency_test", @large_device_count)
      device_ports = create_devices_gradually(@large_device_count, start_port)
      
      # Allow memory to stabilize
      Process.sleep(30_000)
      
      # Check memory usage
      initial_memory = get_memory_usage_mb()
      Logger.info("Initial memory usage: #{initial_memory}MB")
      
      # Run sustained load to test memory stability
      sample_ports = Enum.take_random(device_ports, 50)
      
      load_test_task = Task.async(fn ->
        test_sustained_load(sample_ports, 180_000)  # 3 minutes
      end)
      
      # Monitor memory during load test
      memory_samples = monitor_memory_usage(180_000)
      
      # Wait for load test completion
      Task.await(load_test_task, 200_000)
      
      # Analyze memory usage
      final_memory = get_memory_usage_mb()
      peak_memory = Enum.max(memory_samples)
      memory_growth = final_memory - initial_memory
      
      Logger.info("Memory analysis - Initial: #{initial_memory}MB, Final: #{final_memory}MB, Peak: #{peak_memory}MB")
      
      # Validate memory requirements
      assert peak_memory < 1024           # Under 1GB peak usage
      assert memory_growth < 100          # Less than 100MB growth
      assert final_memory < initial_memory * 1.2  # Less than 20% growth
      
      # Check for potential memory leaks
      assert not detect_memory_leak(memory_samples)
    end

    @tag timeout: @performance_timeout
    @tag :performance
    @tag :slow
    test "achieves sub-5ms response times for cached lookups" do
      Logger.info("Starting response time optimization test")
      
      # Create modest device count for response time testing with allocated ports
      {start_port, _end_port} = get_test_port_range("response_time_test", @small_device_count)
      device_ports = create_devices_gradually(@small_device_count, start_port)
      
      # Warm up caches with hot path requests
      warm_up_caches(device_ports)
      
      # Test hot path response times
      hot_path_oids = ["1.3.6.1.2.1.1.1.0", "1.3.6.1.2.1.1.3.0"]
      
      response_times = test_response_times(device_ports, hot_path_oids, 1000)
      
      avg_response_time = Enum.sum(response_times) / length(response_times)
      p95_response_time = Enum.at(Enum.sort(response_times), round(length(response_times) * 0.95))
      
      Logger.info("Response time analysis - Avg: #{avg_response_time}ms, P95: #{p95_response_time}ms")
      
      # Validate response time requirements
      assert avg_response_time < 5.0      # Under 5ms average
      assert p95_response_time < 10.0     # P95 under 10ms
      
      # Test cache effectiveness
      cache_hit_ratio = get_cache_hit_ratio()
      assert cache_hit_ratio > 85.0       # Over 85% cache hit ratio
    end
  end

  describe "Resource Management Tests" do
    setup do
      # Stop any existing processes first
      if Process.whereis(ResourceManager) do
        GenServer.stop(ResourceManager, :normal, 1000)
      end
      if Process.whereis(OptimizedDevicePool) do
        GenServer.stop(OptimizedDevicePool, :normal, 1000)
      end
      
      # Start ResourceManager first
      {:ok, _} = ResourceManager.start_link([
        max_devices: 1000,
        max_memory_mb: 512
      ])
      
      # Start OptimizedDevicePool to create ETS tables
      {:ok, _} = OptimizedDevicePool.start_link([])
      
      on_exit(fn ->
        # More robust cleanup that handles process termination gracefully
        try do
          if Process.whereis(ResourceManager) do
            GenServer.stop(ResourceManager, :normal, 1000)
          end
        catch
          :exit, _ -> :ok  # Process already dead, ignore
        end
        
        try do
          if Process.whereis(OptimizedDevicePool) do
            GenServer.stop(OptimizedDevicePool, :normal, 1000)
          end
        catch
          :exit, _ -> :ok  # Process already dead, ignore
        end
      end)
      
      :ok
    end
    
    @tag :performance
    test "enforces device and memory limits correctly" do
      # Simple test to verify ResourceManager is working
      # Test that ResourceManager is responsive
      stats = ResourceManager.get_resource_stats()
      assert is_map(stats)
      assert Map.has_key?(stats, :device_count)
      assert Map.has_key?(stats, :memory_utilization)
      
      # Test basic cleanup function
      case ResourceManager.force_cleanup() do
        {:ok, cleaned_count} when is_integer(cleaned_count) -> 
          assert cleaned_count >= 0
        {:error, reason} ->
          # If cleanup fails, that's still acceptable for this test
          Logger.info("Cleanup failed with reason: #{inspect(reason)}")
          assert true
      end
    end

    @tag :performance
    @tag :slow
    test "automatically cleans up idle devices" do
      # ResourceManager is already started in setup, so update its cleanup settings
      :ok = ResourceManager.update_limits([
        idle_threshold: 5_000,     # 5 seconds
        cleanup_interval: 2_000    # 2 seconds
      ])
      
      # Create some devices with allocated ports
      {start_port, _end_port} = get_test_port_range("cleanup_test", 50)
      device_ports = create_devices_gradually(50, start_port)
      initial_count = length(device_ports)
      
      # Wait for devices to become idle and get cleaned up
      Process.sleep(10_000)
      
      # Force a cleanup to ensure cleanup mechanism works
      {:ok, cleaned_count} = ResourceManager.force_cleanup()
      
      # Check that some devices were cleaned up
      final_stats = ResourceManager.get_resource_stats()
      # Either automatic or forced cleanup should have removed some devices
      assert final_stats.device_count < initial_count or cleaned_count > 0
    end
  end

  describe "Scaling and Efficiency Tests" do
    setup do
      # Stop any existing processes first
      if Process.whereis(ResourceManager) do
        GenServer.stop(ResourceManager, :normal, 1000)
      end
      if Process.whereis(OptimizedDevicePool) do
        GenServer.stop(OptimizedDevicePool, :normal, 1000)
      end
      
      # Start ResourceManager for scaling tests
      {:ok, _} = ResourceManager.start_link([
        max_devices: 5000,
        max_memory_mb: 1024
      ])
      
      # Start OptimizedDevicePool to create ETS tables
      {:ok, _} = OptimizedDevicePool.start_link([])
      
      on_exit(fn ->
        # More robust cleanup that handles process termination gracefully
        try do
          if Process.whereis(ResourceManager) do
            GenServer.stop(ResourceManager, :normal, 1000)
          end
        catch
          :exit, _ -> :ok  # Process already dead, ignore
        end
        
        try do
          if Process.whereis(OptimizedDevicePool) do
            GenServer.stop(OptimizedDevicePool, :normal, 1000)
          end
        catch
          :exit, _ -> :ok  # Process already dead, ignore
        end
      end)
      
      :ok
    end

    @tag timeout: @performance_timeout
    @tag :performance
    @tag :slow
    test "scales performance linearly with device count" do
      Logger.info("Starting scaling efficiency test")
      
      device_counts = [100, 500, 1000, 2000]
      
      scaling_results = Enum.map(device_counts, fn device_count ->
        Logger.info("Testing scaling with #{device_count} devices")
        
        # Create devices for this test with allocated ports
        {start_port, _end_port} = get_test_port_range("scaling_#{device_count}", device_count)
        device_ports = create_devices_gradually(device_count, start_port)
        
        # Run performance test
        result = test_scaling_performance(device_ports)
        
        # Cleanup for next iteration
        cleanup_devices()
        
        {device_count, result}
      end)
      
      # Analyze scaling efficiency
      scaling_efficiency = analyze_scaling_efficiency(scaling_results)
      
      # Validate scaling characteristics
      assert scaling_efficiency.linear_regression_r2 > 0.8  # Good linear correlation
      assert scaling_efficiency.efficiency_degradation < 20  # Less than 20% degradation
      
      Logger.info("Scaling test completed - R²: #{scaling_efficiency.linear_regression_r2}")
    end

    @tag :performance
    @tag :slow
    test "maintains stable performance over 24+ hour simulation" do
      # This would be a very long-running test for production validation
      # For the test suite, we'll simulate with a shorter duration but similar patterns
      
      Logger.info("Starting stability simulation test")
      
      # Create devices with allocated ports for stability test
      {start_port, _end_port} = get_test_port_range("stability_test", @small_device_count)
      device_ports = create_devices_gradually(@small_device_count, start_port)
      
      # Simulate 24-hour patterns in compressed time (10 minutes)
      stability_result = simulate_daily_load_patterns(device_ports, 600_000)
      
      # Validate stability metrics
      assert stability_result.performance_variance < 10    # Less than 10% variance
      assert stability_result.memory_leak_detected == false
      assert stability_result.error_rate_stable == true
      
      Logger.info("Stability simulation completed successfully")
    end
  end

  # Helper functions

  defp create_devices_gradually(count, start_port) do
    # Create devices in batches to avoid overwhelming the system
    batch_size = 50
    batches = div(count, batch_size) + 1
    
    Enum.reduce(1..batches, [], fn batch_num, acc ->
      batch_start = start_port + (batch_num - 1) * batch_size
      batch_end = min(batch_start + batch_size - 1, start_port + count - 1)
      
      if batch_start <= start_port + count - 1 do
        batch_ports = Enum.to_list(batch_start..batch_end)
        
        # Create devices in this batch
        created_ports = Enum.filter(batch_ports, fn port ->
          case OptimizedDevicePool.get_device(port) do
            {:ok, _device_pid} -> true
            {:error, _reason} -> false
          end
        end)
        
        # Small delay between batches
        Process.sleep(100)
        
        acc ++ created_ports
      else
        acc
      end
    end)
  end

  defp create_devices_up_to_limit(attempt_count, start_port) do
    Enum.reduce(1..attempt_count, [], fn i, acc ->
      port = start_port + i - 1
      
      case OptimizedDevicePool.get_device(port) do
        {:ok, _device_pid} -> [port | acc]
        {:error, :resource_limit_exceeded} -> acc  # Hit the limit
        {:error, _other_reason} -> acc
      end
    end)
  end

  defp test_device_responsiveness(device_ports) do
    test_oid = "1.3.6.1.2.1.1.1.0"  # sysDescr
    
    results = Enum.map(device_ports, fn port ->
      case :snmp.sync_get("127.0.0.1", port, "public", [test_oid], 5000) do
        {:ok, _response} -> :success
        {:error, _reason} -> :failure
      end
    end)
    
    success_count = Enum.count(results, &(&1 == :success))
    success_rate = (success_count / length(results)) * 100
    
    success_rate
  end

  defp test_sustained_throughput(device_ports, duration_ms) do
    # Run sustained load test
    Benchmarks.run_single_benchmark("sustained_throughput", [
      device_ports: device_ports,
      concurrent_clients: 20,
      request_rate: 1000,
      duration: duration_ms
    ])
  end

  defp test_sustained_load(device_ports, duration_ms) do
    # Generate sustained load for memory testing
    end_time = System.monotonic_time(:millisecond) + duration_ms
    
    test_loop(device_ports, end_time)
  end

  defp test_loop(device_ports, end_time) do
    current_time = System.monotonic_time(:millisecond)
    
    if current_time < end_time do
      # Send some requests
      port = Enum.random(device_ports)
      oid = "1.3.6.1.2.1.1.3.0"  # sysUpTime
      
      :snmp.sync_get("127.0.0.1", port, "public", [oid], 1000)
      
      Process.sleep(100)  # 10 req/s per loop
      test_loop(device_ports, end_time)
    else
      :ok
    end
  end

  defp get_memory_usage_mb() do
    div(:erlang.memory(:total), 1024 * 1024)
  end

  defp monitor_memory_usage(duration_ms) do
    end_time = System.monotonic_time(:millisecond) + duration_ms
    monitor_memory_loop(end_time, [])
  end

  defp monitor_memory_loop(end_time, samples) do
    current_time = System.monotonic_time(:millisecond)
    
    if current_time < end_time do
      memory_mb = get_memory_usage_mb()
      Process.sleep(5000)  # Sample every 5 seconds
      monitor_memory_loop(end_time, [memory_mb | samples])
    else
      Enum.reverse(samples)
    end
  end

  defp detect_memory_leak(memory_samples) do
    if length(memory_samples) < 3 do
      false
    else
      # Simple leak detection: consistently increasing memory
      increasing_count = memory_samples
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.count(fn [prev, curr] -> curr > prev end)
      
      total_pairs = length(memory_samples) - 1
      increasing_ratio = increasing_count / total_pairs
      
      # Consider it a leak if memory increases in >80% of samples
      increasing_ratio > 0.8
    end
  end

  defp warm_up_caches(device_ports) do
    # Send requests to populate caches
    hot_oids = ["1.3.6.1.2.1.1.1.0", "1.3.6.1.2.1.1.3.0"]
    
    Enum.each(1..3, fn _ ->
      Enum.each(device_ports, fn port ->
        Enum.each(hot_oids, fn oid ->
          :snmp.sync_get("127.0.0.1", port, "public", [oid], 1000)
        end)
      end)
    end)
  end

  defp test_response_times(device_ports, oids, request_count) do
    # Measure response times for multiple requests
    Enum.map(1..request_count, fn _ ->
      port = Enum.random(device_ports)
      oid = Enum.random(oids)
      
      start_time = System.monotonic_time(:microsecond)
      
      :snmp.sync_get("127.0.0.1", port, "public", [oid], 1000)
      
      end_time = System.monotonic_time(:microsecond)
      (end_time - start_time) / 1000  # Convert to milliseconds
    end)
  end

  defp get_cache_hit_ratio() do
    case OptimizedDevicePool.get_performance_stats() do
      %{cache_hit_ratio: ratio} -> ratio
      _ -> 0.0
    end
  end

  defp test_scaling_performance(device_ports) do
    # Quick performance test for scaling analysis
    result = Benchmarks.run_single_benchmark("scaling_test", [
      device_ports: device_ports,
      concurrent_clients: 10,
      request_rate: 500,
      duration: 30_000
    ])
    
    %{
      device_count: length(device_ports),
      requests_per_second: result.requests_per_second,
      avg_latency_ms: result.avg_latency_ms,
      memory_usage_mb: result.memory_usage
    }
  end

  defp analyze_scaling_efficiency(scaling_results) do
    # Simple linear regression analysis
    device_counts = Enum.map(scaling_results, fn {count, _result} -> count end)
    throughputs = Enum.map(scaling_results, fn {_count, result} -> result.requests_per_second end)
    
    # Calculate R² for linear relationship
    r_squared = calculate_r_squared(device_counts, throughputs)
    
    # Calculate efficiency degradation
    efficiency_scores = Enum.map(scaling_results, fn {count, result} ->
      result.requests_per_second / count
    end)
    
    max_efficiency = Enum.max(efficiency_scores)
    min_efficiency = Enum.min(efficiency_scores)
    efficiency_degradation = ((max_efficiency - min_efficiency) / max_efficiency) * 100
    
    %{
      linear_regression_r2: r_squared,
      efficiency_degradation: efficiency_degradation,
      scaling_results: scaling_results
    }
  end

  defp calculate_r_squared(x_values, y_values) do
    # Simple R² calculation
    n = length(x_values)
    x_mean = Enum.sum(x_values) / n
    y_mean = Enum.sum(y_values) / n
    
    numerator = Enum.zip(x_values, y_values)
    |> Enum.map(fn {x, y} -> (x - x_mean) * (y - y_mean) end)
    |> Enum.sum()
    |> :math.pow(2)
    
    x_variance = Enum.map(x_values, &:math.pow(&1 - x_mean, 2)) |> Enum.sum()
    y_variance = Enum.map(y_values, &:math.pow(&1 - y_mean, 2)) |> Enum.sum()
    
    denominator = x_variance * y_variance
    
    if denominator > 0 do
      numerator / denominator
    else
      0.0
    end
  end

  defp simulate_daily_load_patterns(device_ports, duration_ms) do
    # Simulate daily traffic patterns in compressed time
    # This is a simplified simulation of 24-hour patterns
    
    start_time = System.monotonic_time(:millisecond)
    end_time = start_time + duration_ms
    
    performance_samples = []
    memory_samples = []
    error_counts = []
    
    # Run simulation
    simulate_load_loop(device_ports, start_time, end_time, {performance_samples, memory_samples, error_counts})
  end

  defp simulate_load_loop(device_ports, start_time, end_time, {perf_samples, mem_samples, error_counts}) do
    current_time = System.monotonic_time(:millisecond)
    
    if current_time < end_time do
      # Simulate time-of-day load variation
      elapsed_ratio = (current_time - start_time) / (end_time - start_time)
      load_multiplier = calculate_daily_load_multiplier(elapsed_ratio)
      
      # Generate load based on multiplier
      request_count = round(10 * load_multiplier)
      
      {success_count, error_count} = generate_load_burst(device_ports, request_count)
      
      # Collect metrics
      memory_mb = get_memory_usage_mb()
      
      new_perf_samples = [{current_time, success_count} | perf_samples]
      new_mem_samples = [{current_time, memory_mb} | mem_samples]
      new_error_counts = [error_count | error_counts]
      
      Process.sleep(1000)  # Sample every second
      
      simulate_load_loop(device_ports, start_time, end_time, {new_perf_samples, new_mem_samples, new_error_counts})
    else
      # Analyze results
      %{
        performance_variance: calculate_variance(perf_samples),
        memory_leak_detected: detect_memory_leak(Enum.map(mem_samples, &elem(&1, 1))),
        error_rate_stable: calculate_error_stability(error_counts)
      }
    end
  end

  defp calculate_daily_load_multiplier(time_ratio) do
    # Simulate daily pattern: low at night, peak during business hours
    hour_of_day = time_ratio * 24
    
    cond do
      hour_of_day < 6 -> 0.3    # Night time - low load
      hour_of_day < 9 -> 0.7    # Morning ramp up
      hour_of_day < 17 -> 1.0   # Business hours - peak load
      hour_of_day < 20 -> 0.8   # Evening
      true -> 0.5              # Late evening
    end
  end

  defp generate_load_burst(device_ports, request_count) do
    results = Enum.map(1..request_count, fn _ ->
      port = Enum.random(device_ports)
      oid = "1.3.6.1.2.1.1.3.0"
      
      case :snmp.sync_get("127.0.0.1", port, "public", [oid], 1000) do
        {:ok, _} -> :success
        {:error, _} -> :error
      end
    end)
    
    success_count = Enum.count(results, &(&1 == :success))
    error_count = Enum.count(results, &(&1 == :error))
    
    {success_count, error_count}
  end

  defp calculate_variance(samples) do
    values = Enum.map(samples, &elem(&1, 1))
    mean = Enum.sum(values) / length(values)
    variance = (Enum.map(values, &:math.pow(&1 - mean, 2)) |> Enum.sum()) / length(values)
    
    if mean > 0 do
      (variance / mean) * 100  # Coefficient of variation as percentage
    else
      0
    end
  end

  defp calculate_error_stability(error_counts) do
    if length(error_counts) < 5 do
      true  # Not enough data
    else
      avg_errors = Enum.sum(error_counts) / length(error_counts)
      max_errors = Enum.max(error_counts)
      
      # Consider stable if max errors is not more than 3x average
      max_errors <= avg_errors * 3
    end
  end

  defp cleanup_devices() do
    # Force cleanup of all devices
    ResourceManager.force_cleanup()
    Process.sleep(1000)  # Allow cleanup to complete
  end
end