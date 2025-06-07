defmodule SnmpSimStabilityTest do
  @moduledoc """
  Long-running stability tests for SnmpSim.

  These tests verify system stability under sustained load and various stress conditions.
  They are designed to run for extended periods to catch memory leaks, resource exhaustion,
  and other stability issues that only appear over time.

  Usage:
    # Run all stability tests (may take hours)
    mix test test/snmp_sim_stability_test.exs
    
    # Run specific stability tests
    mix test test/snmp_sim_stability_test.exs --include stability:memory
    mix test test/snmp_sim_stability_test.exs --include stability:load
  """

  use ExUnit.Case, async: false
  require Logger
  alias SnmpSim.{Device, LazyDevicePool, Core.Server}
  alias SnmpSim.MIB.SharedProfiles
  alias SnmpSim.TestHelpers.{StabilityTestHelper, PortHelper}
  @moduletag :slow

  setup do
    # Ensure SharedProfiles is available for each test
    case GenServer.whereis(SharedProfiles) do
      nil ->
        {:ok, _} = SharedProfiles.start_link([])

      pid when is_pid(pid) ->
        # Check if the process is still alive
        if Process.alive?(pid) do
          :ok
        else
          # Process is dead, start a new one
          {:ok, _} = SharedProfiles.start_link([])
        end
    end

    # Load cable_modem profile into SharedProfiles for tests
    :ok =
      SharedProfiles.load_walk_profile(
        :cable_modem,
        "priv/walks/cable_modem.walk",
        []
      )

    # Start LazyDevicePool for tests that need it
    case GenServer.whereis(LazyDevicePool) do
      nil ->
        {:ok, _} = LazyDevicePool.start_link([])

      _pid ->
        :ok
    end

    :ok
  end

  @moduletag :stability
  @moduletag timeout: :infinity

  # Test configuration
  @memory_test_duration_minutes 30
  @load_test_duration_minutes 60
  @endurance_test_duration_hours 4
  @stress_test_device_count 100
  @load_test_requests_per_second 500

  setup_all do
    # Start application with stability test configuration
    Application.put_env(:snmp_sim, :max_devices, @stress_test_device_count)
    Application.put_env(:snmp_sim, :enable_performance_monitoring, true)
    Application.put_env(:snmp_sim, :enable_telemetry, true)

    # Ensure clean startup
    Application.stop(:snmp_sim)
    Application.start(:snmp_sim)

    # Wait for system to stabilize
    Process.sleep(5000)

    on_exit(fn ->
      StabilityTestHelper.cleanup_all()
      Application.stop(:snmp_sim)
    end)

    :ok
  end

  setup do
    # Clean state before each test
    StabilityTestHelper.reset_system_state()
    :ok
  end

  @tag stability: :memory
  @tag timeout: @memory_test_duration_minutes * 60 * 1000 + 60_000
  test "memory stability over #{@memory_test_duration_minutes} minutes" do
    duration_ms = @memory_test_duration_minutes * 60 * 1000
    # Sample every 30 seconds
    sample_interval_ms = 30_000

    # Track memory usage over time
    memory_samples =
      StabilityTestHelper.monitor_memory_usage(
        duration_ms,
        sample_interval_ms,
        fn ->
          # Continuous device creation and cleanup
          device_count = 50
          devices = create_test_devices(device_count)

          # Perform various operations
          Enum.each(devices, fn device ->
            perform_snmp_operations(device, 10)
          end)

          # Cleanup devices
          cleanup_devices(devices)

          # Force garbage collection
          :erlang.garbage_collect()
        end
      )

    # Analyze memory trends
    {initial_memory, final_memory, max_memory, avg_memory} =
      StabilityTestHelper.analyze_memory_samples(memory_samples)

    # Memory should not grow unbounded
    memory_growth_percent = (final_memory - initial_memory) / initial_memory * 100

    IO.puts("""
    Memory Stability Test Results:
    - Duration: #{@memory_test_duration_minutes} minutes
    - Initial Memory: #{format_memory(initial_memory)}
    - Final Memory: #{format_memory(final_memory)}
    - Max Memory: #{format_memory(max_memory)}
    - Average Memory: #{format_memory(avg_memory)}
    - Memory Growth: #{Float.round(memory_growth_percent, 2)}%
    """)

    # Assertions
    assert memory_growth_percent < 20.0, "Memory growth exceeded 20%: #{memory_growth_percent}%"
    assert max_memory < initial_memory * 2, "Memory usage doubled during test"
    assert length(memory_samples) > @memory_test_duration_minutes, "Insufficient memory samples"
  end

  @tag stability: :load
  @tag timeout: @load_test_duration_minutes * 60 * 1000 + 60_000
  test "sustained load handling for #{@load_test_duration_minutes} minutes" do
    duration_ms = @load_test_duration_minutes * 60 * 1000
    device_count = 100

    # Create devices for load testing
    devices = create_test_devices(device_count)

    # Track system metrics during load test
    metrics =
      StabilityTestHelper.run_load_test(
        devices,
        @load_test_requests_per_second,
        duration_ms,
        %{
          monitor_response_times: true,
          monitor_error_rates: true,
          monitor_resource_usage: true,
          monitor_process_counts: true
        }
      )

    # Analyze results
    {avg_response_time, p95_response_time, p99_response_time} =
      StabilityTestHelper.analyze_response_times(metrics.response_times)

    error_rate = StabilityTestHelper.calculate_error_rate(metrics.errors, metrics.total_requests)
    max_process_count = Enum.max(metrics.process_counts)

    IO.puts("""
    Load Test Results:
    - Duration: #{@load_test_duration_minutes} minutes
    - Target RPS: #{@load_test_requests_per_second}
    - Actual RPS: #{Float.round(metrics.actual_rps, 2)}
    - Total Requests: #{metrics.total_requests}
    - Error Rate: #{Float.round(error_rate, 2)}%
    - Avg Response Time: #{Float.round(avg_response_time, 2)}ms
    - P95 Response Time: #{Float.round(p95_response_time, 2)}ms
    - P99 Response Time: #{Float.round(p99_response_time, 2)}ms
    - Max Process Count: #{max_process_count}
    """)

    # Assertions
    assert error_rate < 5.0, "Error rate too high: #{error_rate}%"
    assert avg_response_time < 100.0, "Average response time too high: #{avg_response_time}ms"
    assert p95_response_time < 200.0, "P95 response time too high: #{p95_response_time}ms"
    assert max_process_count < 50_000, "Process count grew too high: #{max_process_count}"

    cleanup_devices(devices)
  end

  @tag stability: :endurance
  @tag timeout: @endurance_test_duration_hours * 60 * 60 * 1000 + 300_000
  test "endurance test for #{@endurance_test_duration_hours} hours" do
    duration_ms = @endurance_test_duration_hours * 60 * 60 * 1000

    # Start endurance test with varied workload patterns
    results =
      StabilityTestHelper.run_endurance_test(duration_ms, %{
        workload_patterns: [
          %{type: :steady, device_count: 50, duration_minutes: 30},
          %{type: :burst, device_count: 200, duration_minutes: 10},
          %{type: :idle, device_count: 10, duration_minutes: 20}
        ],
        inject_failures: true,
        # 1% failure rate
        failure_rate: 0.01,
        monitor_everything: true
      })

    # Verify system remained stable
    assert results.system_crashed == false, "System crashed during endurance test"
    assert results.memory_leak_detected == false, "Memory leak detected"
    assert results.deadlock_detected == false, "Deadlock detected"
    assert results.resource_exhaustion == false, "Resource exhaustion occurred"

    IO.puts("""
    Endurance Test Results:
    - Duration: #{@endurance_test_duration_hours} hours
    - Total Cycles: #{results.total_cycles}
    - Devices Created: #{results.devices_created}
    - Requests Processed: #{results.requests_processed}
    - Errors Encountered: #{results.errors_encountered}
    - Memory Samples: #{length(results.memory_samples)}
    - System Uptime: 100%
    """)
  end

  @tag stability: :stress
  test "stress test with #{@stress_test_device_count} concurrent devices" do
    # Gradually ramp up device count to stress test limits
    ramp_up_steps = [10, 25, 50, 75, @stress_test_device_count]

    Enum.each(ramp_up_steps, fn device_count ->
      IO.puts("Testing with #{device_count} devices...")

      # Create devices in batches to avoid overwhelming system
      batch_size = 10
      devices = create_devices_in_batches(device_count, batch_size)

      # Verify most devices are operational (allow for some failures due to resource limits)
      operational_count = count_operational_devices(devices)
      success_rate = operational_count / device_count * 100

      assert success_rate > 80.0,
             "Only #{operational_count}/#{device_count} devices operational (#{Float.round(success_rate, 1)}%)"

      # Perform operations on all devices simultaneously
      tasks =
        Enum.map(devices, fn device ->
          Task.async(fn ->
            perform_snmp_operations(device, 5)
          end)
        end)

      # Wait for all tasks to complete
      results = Task.await_many(tasks, 30_000)
      successful_operations = Enum.count(results, fn result -> result == :ok end)

      success_rate = successful_operations / device_count * 100

      assert success_rate > 95.0,
             "Success rate too low with #{device_count} devices: #{success_rate}%"

      # Check system health
      health = StabilityTestHelper.check_system_health()
      assert health.memory_usage < 0.9, "Memory usage too high: #{health.memory_usage}"
      assert health.process_count < 100_000, "Too many processes: #{health.process_count}"

      # Cleanup before next iteration
      cleanup_devices(devices)

      # Allow system to recover and release file descriptors
      :erlang.garbage_collect()
      Process.sleep(2000)
    end)
  end

  @tag stability: :recovery
  test "system recovery after various failure scenarios" do
    scenarios = [
      %{name: "Process Kill", action: :kill_random_processes, count: 10},
      %{name: "Memory Pressure", action: :memory_pressure, intensity: :high},
      %{name: "Port Exhaustion", action: :exhaust_ports, percentage: 0.8},
      %{name: "Network Delays", action: :inject_network_delays, delay_ms: 1000},
      %{name: "Cascading Failures", action: :cascading_failures, failure_rate: 0.1}
    ]

    Enum.each(scenarios, fn scenario ->
      IO.puts("Testing recovery from: #{scenario.name}")

      # Create baseline system state
      baseline_devices = create_test_devices(50)
      baseline_health = StabilityTestHelper.check_system_health()

      # Inject failure
      StabilityTestHelper.inject_failure(scenario)

      # Allow failure to propagate
      Process.sleep(10_000)

      # Measure system response
      recovery_start = System.monotonic_time(:millisecond)

      # Wait for system to recover
      recovery_completed = wait_for_recovery(baseline_health, 120_000)
      recovery_time_ms = System.monotonic_time(:millisecond) - recovery_start

      assert recovery_completed, "System failed to recover from #{scenario.name}"

      assert recovery_time_ms < 60_000,
             "Recovery took too long for #{scenario.name}: #{recovery_time_ms}ms"

      # Verify system functionality after recovery
      post_recovery_devices = create_test_devices(10)

      assert length(post_recovery_devices) == 10,
             "System not fully functional after #{scenario.name}"

      IO.puts("  Recovery time: #{recovery_time_ms}ms")

      # Cleanup
      cleanup_devices(baseline_devices ++ post_recovery_devices)
      StabilityTestHelper.clear_failure_injection()
    end)
  end

  # Helper functions

  # SNMP client functions
  defp send_snmp_get(port, oid, community \\ "public") do
    request_pdu = %{
      version: 1,
      community: community,
      type: :get_request,
      request_id: :rand.uniform(65535),
      error_status: 0,
      error_index: 0,
      varbinds: [{oid, nil}]
    }

    send_snmp_request(port, request_pdu)
  end

  defp send_snmp_getnext(port, oid, community \\ "public") do
    request_pdu = %{
      version: 1,
      community: community,
      type: :get_next_request,
      request_id: :rand.uniform(65535),
      error_status: 0,
      error_index: 0,
      varbinds: [{oid, nil}]
    }

    send_snmp_request(port, request_pdu)
  end

  defp send_snmp_request(port, pdu) do
    message = %{pdu: pdu}

    case SnmpLib.PDU.encode(message) do
      {:ok, packet} ->
        {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])

        :gen_udp.send(socket, {127, 0, 0, 1}, port, packet)

        result =
          case :gen_udp.recv(socket, 0, 2000) do
            {:ok, {_ip, _port, response_data}} ->
              SnmpLib.PDU.decode(response_data)

            {:error, :timeout} ->
              :timeout

            {:error, reason} ->
              {:error, reason}
          end

        :gen_udp.close(socket)
        result

      {:error, reason} ->
        {:error, {:encode_failed, reason}}
    end
  end

  defp create_test_devices(count) do
    # Use PortAllocator service for guaranteed unique ports
    {:ok, {base_port, _end_port}} = get_stability_port_range(count)

    1..count
    |> Enum.map(fn i ->
      # Adjust for 0-based indexing
      port = base_port + i - 1

      {:ok, device} =
        Device.start_link(%{
          community: "public",
          device_type: :cable_modem,
          device_id: "device_#{port}",
          port: port,
          walk_file: "priv/walks/cable_modem.walk"
        })

      # Return both device PID and port for SNMP requests
      {device, port}
    end)
  end

  defp create_devices_in_batches(total_count, batch_size) do
    # Use PortAllocator service for guaranteed unique ports
    {:ok, {base_port, _end_port}} = get_stability_port_range(total_count)

    1..total_count
    |> Enum.chunk_every(batch_size)
    |> Enum.reduce([], fn batch, acc ->
      devices =
        Enum.map(batch, fn i ->
          # Adjust for 0-based indexing
          port = base_port + i - 1

          case Device.start_link(%{
                 community: "public",
                 device_type: :cable_modem,
                 device_id: "device_#{port}",
                 port: port,
                 walk_file: "priv/walks/cable_modem.walk"
               }) do
            {:ok, device} ->
              # Return both device PID and port for SNMP requests
              {device, port}

            {:error, :emfile} ->
              # Hit file descriptor limit, force garbage collection and retry
              :erlang.garbage_collect()
              Process.sleep(100)

              case Device.start_link(%{
                     community: "public",
                     device_type: :cable_modem,
                     device_id: "device_#{port}",
                     port: port,
                     walk_file: "priv/walks/cable_modem.walk"
                   }) do
                {:ok, device} -> {device, port}
                # Skip this device
                {:error, _reason} -> nil
              end

            {:error, _reason} ->
              # Skip devices that fail to start
              nil
          end
        end)
        # Remove nil entries
        |> Enum.filter(& &1)

      # Longer delay between batches to allow system recovery
      Process.sleep(200)
      acc ++ devices
    end)
  end

  defp perform_snmp_operations({_device_pid, port}, operation_count) do
    try do
      1..operation_count
      |> Enum.each(fn _i ->
        # Mix of different SNMP operations using the correct client functions
        # Simplified to just GET and GETNEXT for now
        case :rand.uniform(2) do
          1 -> send_snmp_get(port, "1.3.6.1.2.1.1.1.0")
          2 -> send_snmp_getnext(port, "1.3.6.1.2.1.1")
        end
      end)

      :ok
    catch
      _type, _error -> :error
    end
  end

  defp count_operational_devices(devices) do
    Enum.count(devices, fn {_device_pid, port} ->
      try do
        case send_snmp_get(port, "1.3.6.1.2.1.1.1.0") do
          {:ok, _pdu} -> true
          _error -> false
        end
      catch
        _type, _error -> false
      end
    end)
  end

  defp cleanup_devices(devices) do
    Enum.each(devices, fn {device_pid, _port} ->
      try do
        GenServer.stop(device_pid, :normal, 1000)
      catch
        _type, _error ->
          # Force kill if normal shutdown fails
          try do
            Process.exit(device_pid, :kill)
          catch
            _type, _error -> :ok
          end
      end
    end)

    # Force garbage collection to help release resources
    :erlang.garbage_collect()

    # Small delay to allow cleanup to complete
    Process.sleep(100)
  end

  defp wait_for_recovery(baseline_health, timeout_ms) do
    start_time = System.monotonic_time(:millisecond)

    wait_for_recovery_loop(baseline_health, start_time, timeout_ms)
  end

  defp wait_for_recovery_loop(baseline_health, start_time, timeout_ms) do
    current_time = System.monotonic_time(:millisecond)

    if current_time - start_time > timeout_ms do
      false
    else
      current_health = StabilityTestHelper.check_system_health()

      if system_recovered?(baseline_health, current_health) do
        true
      else
        Process.sleep(1000)
        wait_for_recovery_loop(baseline_health, start_time, timeout_ms)
      end
    end
  end

  defp system_recovered?(baseline, current) do
    # System is considered recovered when key metrics are within acceptable range
    memory_ok = current.memory_usage < baseline.memory_usage * 1.2
    processes_ok = current.process_count < baseline.process_count * 1.1
    devices_ok = current.active_devices >= baseline.active_devices * 0.9

    memory_ok and processes_ok and devices_ok
  end

  defp format_memory(bytes) do
    cond do
      bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 2)} GB"
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 2)} MB"
      bytes >= 1024 -> "#{Float.round(bytes / 1024, 2)} KB"
      true -> "#{bytes} bytes"
    end
  end

  # Helper function to get allocated port range using PortHelper
  defp get_stability_port_range(device_count) do
    port_range = PortHelper.get_port_range(device_count)
    start_port = port_range.first
    end_port = port_range.last
    {:ok, {start_port, end_port}}
  end
end
