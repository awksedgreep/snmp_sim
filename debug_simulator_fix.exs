#!/usr/bin/env elixir

# Change to the proper directory and load mix environment
System.cmd("pwd", [])
Mix.install([])

# Load the current application
Code.prepend_path("_build/dev/lib/snmp_sim/ebin")
Code.prepend_path("_build/dev/lib/snmp_lib/ebin")

# Start the application
Application.load(:snmp_sim)
Application.ensure_all_started(:snmp_sim)

defmodule SimulatorTest do
  def test_device() do
    # Start a single device for testing
    device_config = %{
      port: 9001,
      device_type: :cable_modem,
      device_id: "test_device",
      community: "public"
    }
    
    {:ok, device_pid} = SnmpSim.Device.start_link(device_config)
    IO.puts("Device started on port 9001")
    
    # Give it a moment to start
    Process.sleep(500)
    
    # Test direct device function calls first
    IO.puts("\n=== Testing direct device API ===")
    result = SnmpSim.Device.get(device_pid, "1.3.6.1.2.1.1.1.0")
    IO.puts("Direct device.get(1.3.6.1.2.1.1.1.0): #{inspect(result)}")
    
    # Test with SNMP request using test helper
    IO.puts("\n=== Testing SNMP request via test helper ===")
    
    result = SnmpSim.TestHelpers.SNMPTestHelpers.send_snmp_get(9001, "1.3.6.1.2.1.1.1.0", "public")
    IO.puts("SNMP GET result: #{inspect(result)}")
    
    # Test a few more OIDs
    test_oids = [
      "1.3.6.1.2.1.1.2.0",  # sysObjectID
      "1.3.6.1.2.1.1.3.0",  # sysUpTime
      "1.3.6.1.2.1.1.5.0"   # sysName
    ]
    
    for oid <- test_oids do
      result = SnmpSim.TestHelpers.SNMPTestHelpers.send_snmp_get(9001, oid, "public")
      IO.puts("SNMP GET #{oid}: #{inspect(result)}")
    end
    
    # Test invalid community
    IO.puts("\n=== Testing invalid community ===")
    result = SnmpSim.TestHelpers.SNMPTestHelpers.send_snmp_get(9001, "1.3.6.1.2.1.1.1.0", "invalid")
    IO.puts("SNMP GET with invalid community: #{inspect(result)}")
    
    # Stop device
    SnmpSim.Device.stop(device_pid)
    IO.puts("\nDevice stopped")
    
    :ok
  end
end

SimulatorTest.test_device()