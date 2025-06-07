#!/usr/bin/env elixir

# Manual SNMP Test Script
# This script starts a virtual SNMP device and runs external SNMP commands to test the simulator

defmodule ManualSnmpTest do
  alias SnmpSim.LazyDevicePool

  def run do
    IO.puts("=== Manual SNMP Test ===")
    IO.puts("Starting virtual cable modem device on port 30001...")

    # Start the application
    Application.ensure_all_started(:snmp_sim)

    # Start a virtual device using LazyDevicePool
    case start_virtual_device() do
      {:ok, device_pid, port} ->
        IO.puts("✅ Virtual device started successfully on port #{port}")
        IO.puts("Device PID: #{inspect(device_pid)}")

        # Wait a moment for device to fully initialize
        Process.sleep(2000)

        IO.puts("\n=== Running SNMP Commands ===")
        run_snmp_tests(port)

        IO.puts("\n=== Stopping Device ===")
        stop_virtual_device()

      {:error, reason} ->
        IO.puts("❌ Failed to start virtual device: #{inspect(reason)}")
    end
  end

  defp start_virtual_device do
    # Use a port in the cable_modem range (30_000..37_999)
    port = 30001

    # Ensure clean state
    if Process.whereis(LazyDevicePool) do
      LazyDevicePool.shutdown_all_devices()
    else
      case LazyDevicePool.start_link() do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end
    end

    # Get or create device on the specified port
    case LazyDevicePool.get_or_create_device(port) do
      {:ok, device_pid} ->
        {:ok, device_pid, port}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp stop_virtual_device do
    if Process.whereis(LazyDevicePool) do
      LazyDevicePool.shutdown_all_devices()
    end
    IO.puts("✅ Virtual device stopped")
  end

  defp run_snmp_tests(port) do
    # Test 1: SNMP GET
    IO.puts("\n1. Testing SNMP GET:")
    IO.puts("Command: snmpget -v1 -c public localhost:#{port} 1.3.6.1.2.1.1.1.0")
    {output, exit_code} = System.cmd("snmpget", ["-v1", "-c", "public", "localhost:#{port}", "1.3.6.1.2.1.1.1.0"], stderr_to_stdout: true)
    IO.puts("Exit code: #{exit_code}")
    IO.puts("Output: #{String.trim(output)}")

    # Test 2: SNMP WALK v1
    IO.puts("\n2. Testing SNMP WALK v1:")
    IO.puts("Command: snmpwalk -v1 -c public localhost:#{port} 1.3.6.1.2.1.1")
    {output, exit_code} = System.cmd("snmpwalk", ["-v1", "-c", "public", "localhost:#{port}", "1.3.6.1.2.1.1"], stderr_to_stdout: true)
    IO.puts("Exit code: #{exit_code}")
    IO.puts("Output: #{String.trim(output)}")

    # Test 3: SNMP BULK WALK v2c
    IO.puts("\n3. Testing SNMP BULK WALK v2c:")
    IO.puts("Command: snmpbulkwalk -v2c -c public localhost:#{port} 1.3.6.1")
    {output, exit_code} = System.cmd("snmpbulkwalk", ["-v2c", "-c", "public", "localhost:#{port}", "1.3.6.1"], stderr_to_stdout: true)
    IO.puts("Exit code: #{exit_code}")
    IO.puts("Output: #{String.trim(output)}")

    # Test 4: SNMP WALK v1 with broader OID
    IO.puts("\n4. Testing SNMP WALK v1 (broader OID):")
    IO.puts("Command: snmpwalk -v1 -c public localhost:#{port} 1.3.6.1")
    {output, exit_code} = System.cmd("snmpwalk", ["-v1", "-c", "public", "localhost:#{port}", "1.3.6.1"], stderr_to_stdout: true)
    IO.puts("Exit code: #{exit_code}")
    IO.puts("Output: #{String.trim(output)}")

    # Test 5: Test our fixed GETBULK functionality
    IO.puts("\n5. Testing SNMP GETBULK v2c:")
    IO.puts("Command: snmpbulkget -v2c -c public -Cn0 -Cr5 localhost:#{port} 1.3.6.1.2.1.1")
    {output, exit_code} = System.cmd("snmpbulkget", ["-v2c", "-c", "public", "-Cn0", "-Cr5", "localhost:#{port}", "1.3.6.1.2.1.1"], stderr_to_stdout: true)
    IO.puts("Exit code: #{exit_code}")
    IO.puts("Output: #{String.trim(output)}")

    IO.puts("\n=== Test Complete ===")
  end
end

# Run the test
ManualSnmpTest.run()
