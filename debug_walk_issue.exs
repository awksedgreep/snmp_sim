#!/usr/bin/env elixir

# Debug script to understand the walk issue

# Start a device and test get_next_oid_value
{:ok, device_pid} = SnmpSim.Device.start_link(%{
  device_type: :cable_modem,
  oid_map: %{},
  profile: {:walk_file, "priv/walks/cable_modem.walk"}
})

# Test get_next_oid_value
oid = [1, 3, 6, 1, 2, 1, 1, 1, 0]  # sysDescr.0
result = GenServer.call(device_pid, {:get_next_oid_value, oid})

IO.puts("get_next_oid_value result:")
IO.inspect(result, pretty: true)

case result do
  {:ok, {next_oid, type, value}} ->
    IO.puts("\nParsed result:")
    IO.puts("next_oid: #{inspect(next_oid)} (type: #{inspect(next_oid.__struct__ || :list)})")
    IO.puts("type: #{inspect(type)}")
    IO.puts("value: #{inspect(value)} (type: #{inspect(value.__struct__ || :primitive)})")
  other ->
    IO.puts("Unexpected result: #{inspect(other)}")
end

GenServer.stop(device_pid)
