#!/usr/bin/env elixir

# Start the SNMP simulator application
{:ok, _} = Application.ensure_all_started(:snmp_sim)

# Load the cable modem profile
IO.puts("Loading cable modem profile...")
result = SnmpSim.MIB.SharedProfiles.load_walk_profile(:cable_modem, "priv/walks/cable_modem.walk")
IO.puts("Load result: #{inspect(result)}")

# Wait a bit for ETS table to be populated
Process.sleep(100)

# Check some specific OIDs
test_oids = [
  "1.3.6.1.2.1.1.1.0",  # sysDescr
  "1.3.6.1.2.1.1.2.0",  # sysObjectID
  "1.3.6.1.2.1.1.3.0",  # sysUpTime
  "1.3.6.1.2.1.1"       # system subtree
]

IO.puts("\nChecking OID values:")
Enum.each(test_oids, fn oid ->
  case SnmpSim.MIB.SharedProfiles.get_oid_value(:cable_modem, oid, %{}) do
    {:ok, {type, value}} ->
      IO.puts("  #{oid} -> type: #{inspect(type)}, value: #{inspect(value)}")
    {:error, reason} ->
      IO.puts("  #{oid} -> ERROR: #{inspect(reason)}")
  end
end)

IO.puts("\nChecking GETNEXT operations:")
Enum.each(test_oids, fn oid ->
  case SnmpSim.MIB.SharedProfiles.get_next_oid(:cable_modem, oid) do
    {:ok, next_oid} ->
      IO.puts("  GETNEXT(#{oid}) -> #{next_oid}")
    {:error, reason} ->
      IO.puts("  GETNEXT(#{oid}) -> ERROR: #{inspect(reason)}")
  end
end)

# Check the ETS table directly
IO.puts("\nChecking ETS table contents:")
table_name = :cable_modem_profile
if :ets.info(table_name) != :undefined do
  count = :ets.info(table_name, :size)
  IO.puts("  Table #{table_name} has #{count} entries")
  
  # Get first 10 OIDs
  IO.puts("  First 10 OIDs:")
  :ets.tab2list(table_name)
  |> Enum.take(10)
  |> Enum.each(fn {oid, data} ->
    IO.puts("    #{oid} -> #{inspect(data)}")
  end)
else
  IO.puts("  ETS table #{table_name} not found!")
end
