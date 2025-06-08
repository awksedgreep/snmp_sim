defmodule SnmpSimProductionValidationTest do
  @moduledoc """
  Production validation tests for SnmpSim.

  These tests validate that the system meets production requirements and
  behaves correctly under production-like conditions. They test realistic
  scenarios, performance benchmarks, and operational requirements.

  Usage:
    # Run all production validation tests
    mix test test/snmp_sim_production_validation_test.exs
    
    # Run specific validation categories
    mix test test/snmp_sim_production_validation_test.exs --include validation:performance
    mix test test/snmp_sim_production_validation_test.exs --include validation:security
  """

  use ExUnit.Case, async: false
  alias SnmpSim.{Device, LazyDevicePool, Core.Server}
  alias SnmpSim.TestHelpers.{ProductionTestHelper, PerformanceHelper, PortHelper}

  @moduletag :production_validation
  # 5 minutes default timeout
  @moduletag timeout: 300_000

  # Production requirements
  @min_device_capacity 10_000
  @max_response_time_ms 100
  @min_throughput_rps 1000
  @max_memory_usage_mb 2048
  @max_error_rate_percent 1.0
  @uptime_requirement_percent 99.9

  setup_all do
    # Configure production-like settings
    Application.put_env(:snmp_sim, :max_devices, @min_device_capacity)
    Application.put_env(:snmp_sim, :enable_performance_monitoring, true)
    Application.put_env(:snmp_sim, :optimization_level, :aggressive)

    # Restart application with new configuration
    Application.stop(:snmp_sim)
    {:ok, _} = Application.ensure_all_started(:snmp_sim)

    # Wait for system initialization
    Process.sleep(5000)

    on_exit(fn ->
      ProductionTestHelper.cleanup_all()
      # Restart application to restore normal state for other tests
      Application.stop(:snmp_sim)
      Application.ensure_all_started(:snmp_sim)
    end)

    :ok
  end

  setup do
    ProductionTestHelper.reset_system_state()

    # PortHelper automatically handles port allocation

    :ok
  end

  @tag validation: :capacity
  @tag :slow
  test "meets minimum device capacity requirement (#{@min_device_capacity} devices)" do
    # Test device capacity in phases to avoid overwhelming system
    phases = [
      %{device_count: 1000, duration_ms: 30_000},
      %{device_count: 5000, duration_ms: 60_000},
      %{device_count: @min_device_capacity, duration_ms: 120_000}
    ]

    Enum.each(phases, fn phase ->
      IO.puts("Testing capacity: #{phase.device_count} devices for #{phase.duration_ms}ms")

      # Create devices
      start_time = System.monotonic_time(:millisecond)
      devices = ProductionTestHelper.create_devices_efficiently(phase.device_count)
      creation_time = System.monotonic_time(:millisecond) - start_time

      # Verify all devices are created successfully
      assert length(devices) == phase.device_count,
             "Failed to create #{phase.device_count} devices, got #{length(devices)}"

      # Verify devices are operational
      operational_count = count_operational_devices(devices)
      operational_percentage = operational_count / phase.device_count * 100

      assert operational_percentage >= 99.0,
             "Only #{operational_percentage}% of devices operational"

      # Test system performance with this device count
      performance_metrics = measure_system_performance(devices, phase.duration_ms)

      # Verify performance requirements
      assert performance_metrics.avg_response_time <= @max_response_time_ms,
             "Response time too high: #{performance_metrics.avg_response_time}ms"

      assert performance_metrics.memory_usage_mb <= @max_memory_usage_mb,
             "Memory usage too high: #{performance_metrics.memory_usage_mb}MB"

      assert performance_metrics.error_rate <= @max_error_rate_percent,
             "Error rate too high: #{performance_metrics.error_rate}%"

      IO.puts("""
        Phase Results:
        - Creation Time: #{creation_time}ms
        - Operational Devices: #{operational_count}/#{phase.device_count} (#{Float.round(operational_percentage, 1)}%)
        - Avg Response Time: #{Float.round(performance_metrics.avg_response_time, 2)}ms
        - Memory Usage: #{Float.round(performance_metrics.memory_usage_mb, 2)}MB
        - Error Rate: #{Float.round(performance_metrics.error_rate, 2)}%
      """)

      # Cleanup before next phase
      ProductionTestHelper.cleanup_devices(devices)
      # Allow system to stabilize
      Process.sleep(5000)
    end)
  end

  @tag validation: :performance
  @tag :slow
  test "meets performance requirements under sustained load" do
    device_count = 1000
    # 5 minutes
    test_duration_ms = 300_000

    # Create test devices
    devices = ProductionTestHelper.create_devices_efficiently(device_count)

    # Run sustained load test
    load_test_results =
      PerformanceHelper.run_sustained_load_test(
        devices,
        @min_throughput_rps,
        test_duration_ms,
        %{
          monitor_response_times: true,
          monitor_throughput: true,
          monitor_error_rates: true,
          monitor_resource_usage: true
        }
      )

    # Analyze results
    {avg_response_time, p95_response_time, p99_response_time} =
      PerformanceHelper.analyze_response_times(load_test_results.response_times)

    actual_throughput = load_test_results.actual_throughput_rps

    error_rate =
      PerformanceHelper.calculate_error_rate(
        load_test_results.errors,
        load_test_results.total_requests
      )

    max_memory_usage = Enum.max(load_test_results.memory_samples)

    IO.puts("""
    Performance Test Results:
    - Duration: #{test_duration_ms / 1000} seconds
    - Target Throughput: #{@min_throughput_rps} RPS
    - Actual Throughput: #{Float.round(actual_throughput, 2)} RPS
    - Avg Response Time: #{Float.round(avg_response_time, 2)}ms
    - P95 Response Time: #{Float.round(p95_response_time, 2)}ms
    - P99 Response Time: #{Float.round(p99_response_time, 2)}ms
    - Error Rate: #{Float.round(error_rate, 2)}%
    - Max Memory Usage: #{Float.round(max_memory_usage / 1_048_576, 2)}MB
    """)

    # Assertions against requirements
    assert actual_throughput >= @min_throughput_rps,
           "Throughput below requirement: #{actual_throughput} < #{@min_throughput_rps}"

    assert avg_response_time <= @max_response_time_ms,
           "Average response time above limit: #{avg_response_time}ms"

    assert p95_response_time <= @max_response_time_ms * 2,
           "P95 response time too high: #{p95_response_time}ms"

    assert error_rate <= @max_error_rate_percent,
           "Error rate above limit: #{error_rate}%"

    assert max_memory_usage / 1_048_576 <= @max_memory_usage_mb,
           "Memory usage above limit: #{max_memory_usage / 1_048_576}MB"

    ProductionTestHelper.cleanup_devices(devices)
  end

  @tag validation: :reliability
  @tag :slow
  test "maintains #{@uptime_requirement_percent}% uptime under realistic conditions" do
    # 10 minutes
    test_duration_ms = 600_000
    device_count = 500

    # Create devices
    devices = ProductionTestHelper.create_devices_efficiently(device_count)

    # Define realistic failure scenarios
    failure_scenarios = [
      %{type: :network_blip, probability: 0.001, duration_ms: 1000},
      %{type: :temporary_overload, probability: 0.0005, duration_ms: 5000},
      %{type: :device_restart, probability: 0.0001, duration_ms: 10_000},
      %{type: :memory_pressure, probability: 0.0002, duration_ms: 3000}
    ]

    # Run reliability test with failure injection
    reliability_results =
      ProductionTestHelper.run_reliability_test(
        devices,
        test_duration_ms,
        failure_scenarios,
        %{
          measure_uptime: true,
          measure_recovery_times: true,
          measure_data_consistency: true
        }
      )

    # Calculate uptime percentage
    total_downtime_ms = Enum.sum(reliability_results.downtime_periods)
    uptime_percentage = (test_duration_ms - total_downtime_ms) / test_duration_ms * 100

    # Analyze recovery times
    avg_recovery_time =
      Enum.sum(reliability_results.recovery_times) /
        length(reliability_results.recovery_times)

    max_recovery_time = Enum.max(reliability_results.recovery_times)

    IO.puts("""
    Reliability Test Results:
    - Test Duration: #{test_duration_ms / 1000} seconds
    - Total Downtime: #{total_downtime_ms}ms
    - Uptime: #{Float.round(uptime_percentage, 3)}%
    - Failure Events: #{length(reliability_results.failure_events)}
    - Recovery Events: #{length(reliability_results.recovery_times)}
    - Avg Recovery Time: #{Float.round(avg_recovery_time, 2)}ms
    - Max Recovery Time: #{max_recovery_time}ms
    - Data Consistency: #{reliability_results.data_consistency_maintained}
    """)

    # Assertions
    assert uptime_percentage >= @uptime_requirement_percent,
           "Uptime below requirement: #{uptime_percentage}% < #{@uptime_requirement_percent}%"

    assert avg_recovery_time <= 30_000,
           "Average recovery time too high: #{avg_recovery_time}ms"

    assert max_recovery_time <= 60_000,
           "Maximum recovery time too high: #{max_recovery_time}ms"

    assert reliability_results.data_consistency_maintained,
           "Data consistency not maintained during failures"

    ProductionTestHelper.cleanup_devices(devices)
  end

  @tag validation: :security
  @tag :slow
  test "meets security requirements and handles attack scenarios" do
    # Test various security scenarios with reduced duration for CI performance
    security_tests = [
      %{name: "Community String Bruteforce", test: :community_bruteforce},
      %{name: "Rate Limiting", test: :rate_limiting},
      %{name: "Resource Exhaustion Attack", test: :resource_exhaustion},
      %{name: "Malformed Packet Handling", test: :malformed_packets},
      %{name: "Concurrent Connection Flood", test: :connection_flood}
    ]

    Enum.each(security_tests, fn security_test ->
      IO.puts("Running security test: #{security_test.name}")

      result =
        ProductionTestHelper.run_security_test(security_test.test, %{
          # Reduced from 60s to 5s for faster CI execution
          duration_ms: 5_000,
          monitor_system_health: true,
          log_security_events: true
        })

      # Verify system remained stable
      assert result.system_remained_stable,
             "System became unstable during #{security_test.name}"

      assert result.no_unauthorized_access,
             "Unauthorized access detected during #{security_test.name}"

      assert result.resource_limits_enforced,
             "Resource limits not enforced during #{security_test.name}"

      # Verify proper logging
      assert length(result.security_events) > 0,
             "No security events logged for #{security_test.name}"

      IO.puts("  ✓ #{security_test.name} passed")
    end)
  end

  @tag validation: :monitoring
  @tag :slow
  test "monitoring and alerting systems function correctly" do
    # Test monitoring system responsiveness
    monitoring_tests = [
      %{metric: :memory_usage, threshold: @max_memory_usage_mb, inject: :memory_pressure},
      %{metric: :response_time, threshold: @max_response_time_ms, inject: :artificial_delay},
      %{metric: :error_rate, threshold: @max_error_rate_percent, inject: :random_failures},
      %{metric: :device_count, threshold: @min_device_capacity * 0.9, inject: :device_failures}
    ]

    Enum.each(monitoring_tests, fn test ->
      IO.puts("Testing monitoring for: #{test.metric}")

      # Inject condition that should trigger alert
      ProductionTestHelper.inject_monitoring_condition(test.inject, test.threshold)

      # Wait for monitoring system to detect and alert (reduced timeout for CI)
      alert_received = ProductionTestHelper.wait_for_alert(test.metric, 5_000)

      assert alert_received,
             "No alert received for #{test.metric} within timeout"

      # Verify alert contains correct information
      alert_details = ProductionTestHelper.get_latest_alert(test.metric)

      assert alert_details.severity in [:warning, :critical],
             "Alert severity not appropriate for #{test.metric}"

      assert alert_details.threshold == test.threshold,
             "Alert threshold incorrect for #{test.metric}"

      # Clear condition and verify recovery alert
      ProductionTestHelper.clear_monitoring_condition(test.inject)
      recovery_alert = ProductionTestHelper.wait_for_recovery_alert(test.metric, 5_000)

      assert recovery_alert,
             "No recovery alert received for #{test.metric}"

      IO.puts("  ✓ #{test.metric} monitoring verified")
    end)
  end

  @tag validation: :deployment
  @tag :slow
  test "deployment and operational procedures work correctly" do
    # Test deployment scenarios
    deployment_tests = [
      %{name: "Rolling Update", test: :rolling_update},
      %{name: "Blue-Green Deployment", test: :blue_green_deployment},
      %{name: "Graceful Shutdown", test: :graceful_shutdown},
      %{name: "Configuration Hot Reload", test: :config_hot_reload},
      %{name: "Health Check Endpoints", test: :health_checks}
    ]

    Enum.each(deployment_tests, fn test ->
      IO.puts("Testing deployment scenario: #{test.name}")

      result =
        ProductionTestHelper.run_deployment_test(test.test, %{
          maintain_service_availability: true,
          verify_data_integrity: true,
          measure_downtime: true
        })

      # Verify deployment succeeded
      assert result.deployment_successful,
             "Deployment failed: #{test.name}"

      # Verify minimal downtime
      assert result.downtime_ms <= 10_000,
             "Downtime too high for #{test.name}: #{result.downtime_ms}ms"

      # Verify service availability maintained
      assert result.service_availability_percent >= 99.0,
             "Service availability too low during #{test.name}: #{result.service_availability_percent}%"

      # Verify data integrity
      assert result.data_integrity_maintained,
             "Data integrity not maintained during #{test.name}"

      IO.puts("  ✓ #{test.name} completed successfully")
    end)
  end

  @tag validation: :integration
  @tag :slow
  test "integrates correctly with external systems" do
    # Test integration points
    integration_tests = [
      %{system: "SNMP Management Tools", test: :snmp_tool_compatibility},
      %{system: "Monitoring Systems", test: :monitoring_integration},
      %{system: "Log Aggregation", test: :log_integration},
      %{system: "Metrics Collection", test: :metrics_integration},
      %{system: "Container Orchestration", test: :k8s_integration}
    ]

    Enum.each(integration_tests, fn test ->
      if ProductionTestHelper.integration_available?(test.system) do
        IO.puts("Testing integration with: #{test.system}")

        result =
          ProductionTestHelper.run_integration_test(test.test, %{
            verify_data_flow: true,
            verify_protocols: true,
            verify_authentication: true
          })

        assert result.integration_successful,
               "Integration failed with #{test.system}"

        assert result.data_flow_correct,
               "Data flow incorrect with #{test.system}"

        assert result.protocols_compatible,
               "Protocol compatibility issue with #{test.system}"

        IO.puts("  ✓ #{test.system} integration verified")
      else
        IO.puts("  - #{test.system} not available for testing")
      end
    end)
  end

  # Helper functions

  defp count_operational_devices(devices) do
    Enum.count(devices, fn device ->
      try do
        case Device.get(device, "1.3.6.1.2.1.1.1.0") do
          {:ok, _value} -> true
          _error -> false
        end
      catch
        _type, _error -> false
      end
    end)
  end

  defp measure_system_performance(devices, duration_ms) do
    # Sample a subset of devices for performance measurement
    sample_devices = Enum.take_random(devices, min(100, length(devices)))

    # Measure performance over duration
    start_time = System.monotonic_time(:millisecond)
    end_time = start_time + duration_ms

    {response_times, errors, memory_samples} =
      collect_performance_data(sample_devices, start_time, end_time, [], [], [])

    avg_response_time = Enum.sum(response_times) / length(response_times)
    error_rate = length(errors) / length(response_times) * 100
    max_memory_usage = Enum.max(memory_samples)

    %{
      avg_response_time: avg_response_time,
      error_rate: error_rate,
      memory_usage_mb: max_memory_usage / 1_048_576
    }
  end

  defp collect_performance_data(
         devices,
         start_time,
         end_time,
         response_times,
         errors,
         memory_samples
       ) do
    current_time = System.monotonic_time(:millisecond)

    if current_time >= end_time do
      {response_times, errors, memory_samples}
    else
      # Perform SNMP operation and measure response time
      device = Enum.random(devices)

      {response_time, result} =
        measure_operation_time(fn ->
          Device.get(device, "1.3.6.1.2.1.1.1.0")
        end)

      new_response_times = [response_time | response_times]

      new_errors =
        case result do
          {:ok, _} -> errors
          _error -> [result | errors]
        end

      # Sample memory usage
      {:ok, memory_info} = :erlang.system_info(:memory)
      current_memory = memory_info[:total]
      new_memory_samples = [current_memory | memory_samples]

      # Small delay before next measurement
      Process.sleep(100)

      collect_performance_data(
        devices,
        start_time,
        end_time,
        new_response_times,
        new_errors,
        new_memory_samples
      )
    end
  end

  defp measure_operation_time(fun) do
    start_time = System.monotonic_time(:microsecond)
    result = fun.()
    end_time = System.monotonic_time(:microsecond)
    response_time_ms = (end_time - start_time) / 1000

    {response_time_ms, result}
  end
end
