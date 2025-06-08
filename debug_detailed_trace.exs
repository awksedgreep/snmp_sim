#!/usr/bin/env elixir

# Detailed trace to find where system OIDs come from

# Start the application
Application.ensure_all_started(:snmp_sim)

# Load a profile
profile_path = "priv/walks/cable_modem_oids.walk"
{:ok, profile_data, behavior_data} = SnmpSim.ProfileLoader.load_profile(:cable_modem, {:walk_file, profile_path})

# Store the profile
device_type = "cable_modem"
:ok = SnmpSim.MIB.SharedProfiles.store_profile(device_type, profile_data, behavior_data)

IO.puts("Profile loaded with #{length(profile_data)} OIDs")

# Check what OIDs are actually in the profile
all_oids = Enum.map(profile_data, fn {oid, _data} -> oid end) |> Enum.sort()
IO.puts("First 5 OIDs in profile:")
Enum.take(all_oids, 5) |> Enum.each(&IO.puts("  #{&1}"))

# Test the specific problem case step by step
test_oid = "1.3.6.1"
IO.puts("\n=== Step 1: Test SharedProfiles.get_next_oid directly ===")

result1 = SnmpSim.MIB.SharedProfiles.get_next_oid(device_type, test_oid)
IO.puts("SharedProfiles.get_next_oid(\"#{test_oid}\") = #{inspect(result1)}")

case result1 do
  {:ok, next_oid} ->
    IO.puts("✅ Got next OID: #{next_oid}")
    
    # Check if this OID exists in the profile
    if next_oid in all_oids do
      IO.puts("✅ #{next_oid} EXISTS in walk file")
    else
      IO.puts("❌ #{next_oid} DOES NOT EXIST in walk file")
    end
    
    IO.puts("\n=== Step 2: Test SharedProfiles.get_oid_value for that OID ===")
    device_state = %{}
    result2 = SnmpSim.MIB.SharedProfiles.get_oid_value(device_type, next_oid, device_state)
    IO.puts("SharedProfiles.get_oid_value(\"#{next_oid}\") = #{inspect(result2)}")
    
  other ->
    IO.puts("SharedProfiles returned: #{inspect(other)}")
end

IO.puts("\n=== Step 3: Test Device OidHandler ===")

# Create a mock device state
device_state = %{
  device_type: device_type,
  port: 30000,
  counters: %{},
  gauges: %{},
  device_id: "test_device"
}

IO.puts("Testing OidHandler.get_next_oid_value(\"#{test_oid}\")...")
result3 = SnmpSim.Device.OidHandler.get_next_oid_value(test_oid, device_state)
IO.puts("OidHandler.get_next_oid_value(\"#{test_oid}\") = #{inspect(result3)}")

case result3 do
  {:ok, {next_oid, type, value}} ->
    IO.puts("✅ Got next OID: #{next_oid}")
    
    # Check if this OID exists in the profile
    if next_oid in all_oids do
      IO.puts("✅ #{next_oid} EXISTS in walk file")
    else
      IO.puts("❌ #{next_oid} DOES NOT EXIST in walk file - THIS IS THE PROBLEM!")
      
      # Let's see what fallback was used
      IO.puts("\n=== Step 4: Test fallback mechanism ===")
      fallback_result = SnmpSim.Device.OidHandler.get_fallback_next_oid(test_oid, device_state)
      IO.puts("get_fallback_next_oid(\"#{test_oid}\") = #{inspect(fallback_result)}")
    end
    
  {:error, reason} ->
    IO.puts("OidHandler returned error: #{reason}")
end

IO.puts("\n=== Step 5: Check if there are multiple device types or tables ===")
# Check what's actually stored in SharedProfiles
state = :sys.get_state(SnmpSim.MIB.SharedProfiles)
IO.puts("SharedProfiles state keys: #{inspect(Map.keys(state))}")
if Map.has_key?(state, :profile_tables) do
  IO.puts("Profile tables: #{inspect(Map.keys(state.profile_tables))}")
end
