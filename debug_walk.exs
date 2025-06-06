#!/usr/bin/env elixir

# Debug interface table walk issue
IO.puts "🔍 Debugging Interface Table Walk Issue"

# Start the application
Application.ensure_all_started(:snmp_sim)
Process.sleep(1000)

# Get a device to test with
devices = DynamicSupervisor.which_children(SnmpSim.DeviceSupervisor)
{_, device_pid, _, _} = List.first(devices)

IO.puts "📡 Testing device: #{inspect(device_pid)}"

# Get device info
device_info = GenServer.call(device_pid, :get_info)
IO.puts "   Device ID: #{device_info.device_id}"
IO.puts "   Port: #{device_info.port}"
IO.puts "   Device Type: #{device_info.device_type}"

# Test 1: Check what OIDs are available in the interface table range
IO.puts "\n🧪 Test 1: Check available interface table OIDs"

interface_table_base = "1.3.6.1.2.1.2.2.1"
test_oids = [
  "1.3.6.1.2.1.2.1.0",      # ifNumber
  "1.3.6.1.2.1.2.2.1.1.1",  # ifIndex.1
  "1.3.6.1.2.1.2.2.1.2.1",  # ifDescr.1
  "1.3.6.1.2.1.2.2.1.10.1", # ifInOctets.1
  "1.3.6.1.2.1.2.2.1.16.1"  # ifOutOctets.1
]

Enum.each(test_oids, fn oid ->
  result = GenServer.call(device_pid, {:get_oid, oid})
  IO.puts "   #{oid}: #{inspect(result)}"
end)

# Test 2: Try GETNEXT from interface table base
IO.puts "\n🧪 Test 2: GETNEXT from interface table base"
getnext_result = GenServer.call(device_pid, {:get_next_oid, interface_table_base})
IO.puts "   GETNEXT(#{interface_table_base}): #{inspect(getnext_result)}"

# Test 3: Try walking a smaller subtree first
IO.puts "\n🧪 Test 3: Walk system group (should work)"
system_walk = GenServer.call(device_pid, {:walk_oid, "1.3.6.1.2.1.1"})
IO.puts "   System walk result: #{inspect(system_walk)}"

# Test 4: Check if SharedProfiles has interface data
IO.puts "\n🧪 Test 4: Check SharedProfiles for interface OIDs"
try do
  profiles_result = SnmpSim.MIB.SharedProfiles.get_next_oid(device_info.device_type, interface_table_base)
  IO.puts "   SharedProfiles GETNEXT: #{inspect(profiles_result)}"
rescue
  error ->
    IO.puts "   SharedProfiles error: #{inspect(error)}"
end

# Test 5: Manual SNMP walk test
IO.puts "\n🧪 Test 5: Manual SNMP walk test"
IO.puts "   Run this command to test:"
IO.puts "   snmpwalk -v1 -c public 127.0.0.1:#{device_info.port} 1.3.6.1.2.1.2.2.1.1"

IO.puts "\n✅ Debug complete. Check the results above."
