#!/usr/bin/env elixir

# Quick test for OBJECT IDENTIFIER type fidelity
Application.ensure_all_started(:snmp_sim)
Process.sleep(1000)

IO.puts("🔍 Testing OBJECT IDENTIFIER Type")
IO.puts("=================================")

# Load the walk profile
device_type = :walk_cable_modem_oids
walk_path = Path.join([File.cwd!(), "priv", "walks", "cable_modem_oids.walk"])

# Load walk profile
case SnmpSim.MIB.SharedProfiles.load_walk_profile(device_type, walk_path) do
  :ok -> IO.puts("✅ Walk profile loaded")
  {:error, reason} -> 
    IO.puts("❌ Failed to load walk profile: #{inspect(reason)}")
    System.halt(1)
end

# Create device
{:ok, device_pid} = SnmpSim.Device.start_link(%{
  device_id: "oid_test",
  device_type: device_type,
  port: 9005
})

IO.puts("✅ Device created")

# Test the specific OID that should be OBJECT IDENTIFIER
test_oid = "1.3.6.1.2.1.1.2.0"
IO.puts("\nTesting OID: #{test_oid}")

case SnmpSim.Device.get(device_pid, test_oid) do
  {:ok, {type, value}} ->
    IO.puts("✅ Type: #{type}")
    IO.puts("✅ Value: #{inspect(value)}")
    
    # Check if it's the expected OBJECT IDENTIFIER
    if type == :object_identifier or type == "OBJECT IDENTIFIER" or type == "OID" do
      IO.puts("🎉 SUCCESS: OBJECT IDENTIFIER type preserved!")
    else
      IO.puts("⚠️  Type is not OBJECT IDENTIFIER, got: #{type}")
    end
    
  {:error, reason} ->
    IO.puts("❌ Failed to get OID: #{inspect(reason)}")
end

IO.puts("\n✅ Test complete")
