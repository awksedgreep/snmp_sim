#!/usr/bin/env elixir

# Test script to reproduce the exact SNMP bulk walk problem
# This reproduces the exact command that's failing: snmpbulkwalk -v2c -c public localhost:10001 1.3.6.1

defmodule ExactProblemTest do
  alias SnmpSim.LazyDevicePool

  def run do
    IO.puts("=== Testing Exact Problem: SNMP bulk walk failures ===")
    
    # Start the application
    Application.ensure_all_started(:snmp_sim)
    Process.sleep(1000)
    
    # Test port 30001 (known working from our manual test)
    test_port(30001, "cable_modem range (should work)")
    
    # Test port 10001 (the failing port)
    test_port(10001, "port 10001 (the failing one)")
    
    # Test port 10002 
    test_port(10002, "port 10002 (another test)")
  end
  
  defp test_port(port, description) do
    IO.puts("\n=== Testing #{description} ===")
    
    case LazyDevicePool.get_or_create_device(port) do
      {:ok, device_pid} ->
        IO.puts("✅ Device started on port #{port}")
        IO.puts("Device PID: #{inspect(device_pid)}")
        
        # Wait for device to initialize
        Process.sleep(2000)
        
        # Test the exact failing command
        IO.puts("\n--- Running: snmpbulkwalk -v2c -c public localhost:#{port} 1.3.6.1 ---")
        
        {output, exit_code} = System.cmd("snmpbulkwalk", ["-v2c", "-c", "public", "localhost:#{port}", "1.3.6.1"], stderr_to_stdout: true)
        
        IO.puts("Exit code: #{exit_code}")
        IO.puts("Output:")
        IO.puts(String.trim(output))
        
        if String.contains?(output, "No more variables left in this MIB View") do
          IO.puts("\n❌ PROBLEM REPRODUCED! The bulk walk is failing on port #{port}!")
        elsif String.contains?(output, "Timeout") or String.contains?(output, "No response") do
          IO.puts("\n⚠️  Device not responding on port #{port}")
        else
          IO.puts("\n✅ Bulk walk is working correctly on port #{port}!")
        end
        
        # Stop the device
        LazyDevicePool.stop_device(port)
        
      {:error, reason} ->
        IO.puts("❌ Failed to start device on port #{port}: #{inspect(reason)}")
        
        if reason == :unknown_port_range do
          IO.puts("   Port #{port} is not in any recognized device type range")
          IO.puts("   Let's try the command anyway to see what happens...")
          
          {output, exit_code} = System.cmd("snmpbulkwalk", ["-v2c", "-c", "public", "localhost:#{port}", "1.3.6.1"], stderr_to_stdout: true)
          IO.puts("   Exit code: #{exit_code}")
          IO.puts("   Output: #{String.trim(output)}")
        end
    end
  end
end

# Run the test
ExactProblemTest.run()
