#!/usr/bin/env elixir

# Simple debug script to test GETBULK functionality
Mix.install([{:snmp_sim, path: "."}])

alias SnmpSim.Device
alias SnmpSim.MIB.SharedProfiles

IO.puts("🔍 Debug GETBULK Simple Test")

# Start SharedProfiles
case SharedProfiles.start_link([]) do
  {:ok, _pid} -> IO.puts("✅ SharedProfiles started")
  {:error, {:already_started, _pid}} -> IO.puts("✅ SharedProfiles already running")
end

# Create test device state
state = %{
  device_id: "debug_device",
  device_type: :cable_modem,
  port: 30200,
  community: "public",
  version: :v2c,
  counters: %{
    "1.3.6.1.2.1.2.2.1.10.1" => 1234567,
    "1.3.6.1.2.1.2.2.1.16.1" => 2345678
  },
  gauges: %{
    "1.3.6.1.2.1.2.2.1.5.1" => 100000000
  },
  uptime_start: System.monotonic_time(:millisecond)
}

IO.puts("🚀 Starting device...")
{:ok, device_pid} = Device.start_link(state)

IO.puts("📊 Testing GETBULK...")

# Test GETBULK
test_oid = [1, 3, 6, 1, 2, 1, 1]
result = Device.get_bulk(device_pid, test_oid, 5)

IO.puts("📋 GETBULK Result:")
IO.inspect(result, pretty: true)

case result do
  {:ok, varbinds} ->
    IO.puts("✅ GETBULK succeeded")
    IO.puts("📊 Number of varbinds: #{length(varbinds)}")
    
    if length(varbinds) > 0 do
      IO.puts("🔍 First few varbinds:")
      varbinds
      |> Enum.take(3)
      |> Enum.with_index()
      |> Enum.each(fn {varbind, index} ->
        IO.puts("  [#{index}] #{inspect(varbind)}")
      end)
    else
      IO.puts("❌ No varbinds returned - this is the problem!")
    end
    
  {:error, reason} ->
    IO.puts("❌ GETBULK failed: #{inspect(reason)}")
end

# Test a simple get_next for comparison
IO.puts("\n🔄 Testing get_next for comparison...")
next_result = Device.get_next(device_pid, test_oid)
IO.puts("📋 GETNEXT Result:")
IO.inspect(next_result, pretty: true)

# Clean up
Device.stop(device_pid)
IO.puts("🧹 Cleanup complete")
