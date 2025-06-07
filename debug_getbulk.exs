#!/usr/bin/env elixir

# Debug script to test GETBULK functionality
Mix.install([
  {:snmp_lib, git: "https://github.com/mcotner/snmp_lib.git", tag: "v1.0.1"}
])

Code.require_file("lib/snmp_sim.ex")
Code.require_file("lib/snmp_sim/device.ex")
Code.require_file("lib/snmp_sim/mib/shared_profiles.ex")

alias SnmpSim.Device
alias SnmpSim.MIB.SharedProfiles

# Test the GETBULK functionality directly
defmodule GetBulkDebug do
  def test_getbulk do
    IO.puts("=== Testing GETBULK functionality ===")
    
    # Create a test device state
    state = %{
      device_type: :mock_device,
      port: 30000,
      community: "public",
      version: :v2c
    }
    
    # Test OID for system group
    test_oid = [1, 3, 6, 1, 2, 1, 1]
    
    IO.puts("Testing with OID: #{inspect(test_oid)}")
    
    # Test get_bulk_oid_values directly
    case Device.get_bulk_oid_values(test_oid, 5, state) do
      {:ok, varbinds} ->
        IO.puts("✅ get_bulk_oid_values returned #{length(varbinds)} varbinds:")
        Enum.each(varbinds, fn varbind ->
          IO.puts("  - #{inspect(varbind)}")
        end)
      {:error, reason} ->
        IO.puts("❌ get_bulk_oid_values failed: #{inspect(reason)}")
    end
    
    # Test SharedProfiles directly
    IO.puts("\n=== Testing SharedProfiles directly ===")
    
    # Initialize SharedProfiles
    {:ok, _pid} = SharedProfiles.start_link([])
    
    case SharedProfiles.get_bulk_oids(:mock_device, test_oid, 5) do
      {:ok, varbinds} ->
        IO.puts("✅ SharedProfiles.get_bulk_oids returned #{length(varbinds)} varbinds:")
        Enum.each(varbinds, fn varbind ->
          IO.puts("  - #{inspect(varbind)}")
        end)
      {:error, reason} ->
        IO.puts("❌ SharedProfiles.get_bulk_oids failed: #{inspect(reason)}")
    end
  end
end

GetBulkDebug.test_getbulk()
