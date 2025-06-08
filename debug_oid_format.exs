#!/usr/bin/env elixir

# Debug script to check OID format in ETS tables
Mix.install([])

# Load the application
Code.require_file("lib/snmp_sim/walk_parser.ex")
Code.require_file("lib/snmp_sim/mib/shared_profiles.ex")

# Start the SharedProfiles GenServer
{:ok, _pid} = SnmpSim.MIB.SharedProfiles.start_link([])

# Load the walk file
walk_file = "priv/walks/cable_modem_oids.walk"
{:ok, result} = SnmpSim.MIB.SharedProfiles.load_walk_profile(:cable_modem, walk_file)

IO.puts("Walk file loaded: #{inspect(result)}")

# Check what's in the ETS table
profiles = SnmpSim.MIB.SharedProfiles.list_profiles()
IO.puts("Available profiles: #{inspect(profiles)}")

# Try to get a specific OID value
test_oid = "1.3.6.1.2.1.2.2.1.5.1"
result = SnmpSim.MIB.SharedProfiles.get_oid_value(:cable_modem, test_oid, %{})
IO.puts("get_oid_value(#{test_oid}): #{inspect(result)}")

# Try GETBULK
bulk_result = SnmpSim.MIB.SharedProfiles.get_bulk_oids(:cable_modem, "1.3.6.1.2.1.2.2.1.5", 5)
IO.puts("get_bulk_oids: #{inspect(bulk_result)}")
