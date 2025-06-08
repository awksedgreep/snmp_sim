#!/usr/bin/env elixir

# Test the full GETBULK chain to identify where NULL values are coming from

File.cd!("/Users/mcotner/Documents/elixir/snmp_sim")
Code.append_path("_build/dev/lib/snmp_sim/ebin")

# Load required modules
Application.ensure_all_started(:snmp_sim)

# Wait for SharedProfiles to start
Process.sleep(1000)

# Test specific OIDs that should return Counter32: 0
test_oids = [
  "1.3.6.1.2.1.2.2.1.13.1",  # Counter32: 0
  "1.3.6.1.2.1.2.2.1.15.1",  # Counter32: 0  
  "1.3.6.1.2.1.2.2.1.19.1"   # Counter32: 0
]

IO.puts("=== Testing GETBULK Chain ===")

# First, load a profile to test with
case SnmpSim.MIB.SharedProfiles.load_walk_profile(:cable_modem, "priv/walks/cable_modem_oids.walk") do
  :ok -> 
    IO.puts("✅ Profile loaded successfully")
  {:error, reason} -> 
    IO.puts("❌ Failed to load profile: #{inspect(reason)}")
    System.halt(1)
end

# Test individual OID lookups
IO.puts("\n=== Individual OID Tests ===")
device_state = %{device_id: "test", uptime: 3600}

for oid <- test_oids do
  case SnmpSim.MIB.SharedProfiles.get_oid_value(:cable_modem, oid, device_state) do
    {:ok, {type, value}} ->
      IO.puts("✅ #{oid} -> {#{inspect(type)}, #{inspect(value)}}")
    {:error, reason} ->
      IO.puts("❌ #{oid} -> Error: #{inspect(reason)}")
  end
end

# Test GETBULK operation
IO.puts("\n=== GETBULK Test ===")
case SnmpSim.MIB.SharedProfiles.get_bulk_oids(:cable_modem, "1.3.6.1.2.1.2.2.1.13", 5) do
  {:ok, bulk_oids} ->
    IO.puts("✅ GETBULK returned #{length(bulk_oids)} OIDs:")
    for {oid, type, value} <- bulk_oids do
      IO.puts("  #{oid} -> {#{inspect(type)}, #{inspect(value)}}")
    end
  {:error, reason} ->
    IO.puts("❌ GETBULK failed: #{inspect(reason)}")
end

# Test what's actually in the ETS tables
IO.puts("\n=== ETS Table Contents ===")
case GenServer.call(SnmpSim.MIB.SharedProfiles, :get_state) do
  state when is_map(state) ->
    prof_table = Map.get(state.profile_tables, :cable_modem)
    if prof_table do
      IO.puts("Profile table exists: #{inspect(prof_table)}")
      # Check a few specific entries
      for oid <- test_oids do
        case :ets.lookup(prof_table, oid) do
          [{^oid, profile_data}] ->
            IO.puts("  #{oid} in ETS: #{inspect(profile_data)}")
          [] ->
            IO.puts("  #{oid} NOT FOUND in ETS")
        end
      end
    else
      IO.puts("❌ No profile table found for :cable_modem")
    end
  error ->
    IO.puts("❌ Failed to get SharedProfiles state: #{inspect(error)}")
end
