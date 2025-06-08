#!/usr/bin/env elixir

# Debug SNMP get-next to see why SharedProfiles is failing
Application.ensure_all_started(:snmp_sim)
Process.sleep(1000)

IO.puts("🔍 Debug SNMP Get-Next")
IO.puts("=======================")

# Load the walk profile
device_type = :walk_cable_modem_oids
walk_path = Path.join([File.cwd!(), "priv", "walks", "cable_modem_oids.walk"])

IO.puts("1. Loading walk profile...")
SnmpSim.MIB.SharedProfiles.load_walk_profile(device_type, walk_path)

# Test the specific OID that's failing
test_oid = "1.3.6.1.2.1.2.2.1.1.2"

IO.puts("\n2. Testing SharedProfiles.get_next_oid directly...")
case SnmpSim.MIB.SharedProfiles.get_next_oid(device_type, test_oid) do
  {:ok, next_oid} -> 
    IO.puts("✅ SharedProfiles.get_next_oid(#{device_type}, #{test_oid}) -> #{next_oid}")
  {:error, reason} -> 
    IO.puts("❌ SharedProfiles.get_next_oid failed: #{inspect(reason)}")
end

IO.puts("\n3. Creating device and testing device get_next...")
{:ok, device_pid} = SnmpSim.Device.start_link(%{
  device_id: "debug_device",
  device_type: device_type,
  port: 9998
})

case SnmpSim.Device.get_next(device_pid, test_oid) do
  {:ok, {oid, type, value}} -> 
    IO.puts("✅ Device.get_next(#{test_oid}) -> #{oid} (#{type}) = #{inspect(value)}")
  {:error, reason} -> 
    IO.puts("❌ Device.get_next failed: #{inspect(reason)}")
end

IO.puts("\n4. Getting device state to check device_type...")
case GenServer.call(device_pid, :get_state) do
  {:ok, state} ->
    IO.puts("✅ Device state: device_type=#{state.device_type}, device_id=#{state.device_id}")
  {:error, reason} ->
    IO.puts("❌ Could not get device state: #{inspect(reason)}")
end

IO.puts("\n✅ Debug complete")
