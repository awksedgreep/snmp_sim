#!/usr/bin/env elixir

# Debug script to trace exactly where system OIDs are coming from

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
IO.puts("First 10 OIDs in profile:")
Enum.take(all_oids, 10) |> Enum.each(&IO.puts("  #{&1}"))

# Test the specific problem case
test_oid = "1.3.6.1"
IO.puts("\n=== Testing SharedProfiles.get_next_oid directly ===")
case SnmpSim.MIB.SharedProfiles.get_next_oid(device_type, test_oid) do
  {:ok, next_oid} -> 
    IO.puts("SharedProfiles.get_next_oid(#{test_oid}) = #{next_oid}")
    
    # Check if this OID exists in the profile
    if next_oid in all_oids do
      IO.puts("✅ #{next_oid} EXISTS in walk file")
    else
      IO.puts("❌ #{next_oid} DOES NOT EXIST in walk file")
      IO.puts("This should not happen!")
    end
    
  :end_of_mib -> 
    IO.puts("SharedProfiles.get_next_oid(#{test_oid}) = END_OF_MIB")
  {:error, reason} -> 
    IO.puts("SharedProfiles.get_next_oid(#{test_oid}) = ERROR: #{reason}")
end

# Test what the device-level handler returns
IO.puts("\n=== Testing Device OidHandler ===")

# Create a mock device state
device_state = %{
  device_type: device_type,
  port: 30000,
  counters: %{},
  gauges: %{},
  device_id: "test_device"
}

case SnmpSim.Device.OidHandler.get_next_oid_value(test_oid, device_state) do
  {:ok, {next_oid, type, value}} ->
    IO.puts("OidHandler.get_next_oid_value(#{test_oid}) = {#{next_oid}, #{type}, #{inspect(value)}}")
    
    # Check if this OID exists in the profile
    if next_oid in all_oids do
      IO.puts("✅ #{next_oid} EXISTS in walk file")
    else
      IO.puts("❌ #{next_oid} DOES NOT EXIST in walk file")
      IO.puts("This is where the problem is!")
    end
    
  {:error, reason} ->
    IO.puts("OidHandler.get_next_oid_value(#{test_oid}) = ERROR: #{reason}")
end
