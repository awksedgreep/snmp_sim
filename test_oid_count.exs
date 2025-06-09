#!/usr/bin/env elixir

# Simple script to test OID count from get_known_oids
Mix.install([])

# Add the lib path
Code.prepend_path("lib")

# Start the application
Application.ensure_all_started(:snmp_sim)

# Load the profile
alias SnmpSim.ProfileLoader
{:ok, _profile} = ProfileLoader.load_profile(
  :cable_modem,
  {:walk_file, "priv/walks/cable_modem.walk"}
)

# Test get_known_oids
alias SnmpSim.Device.OidHandler

# Use reflection to call the private function
oids = :erlang.apply(OidHandler, :get_known_oids, [:cable_modem])

IO.puts("Number of OIDs returned by get_known_oids: #{length(oids)}")
IO.puts("First 10 OIDs:")
oids |> Enum.take(10) |> Enum.each(fn oid ->
  oid_string = Enum.join(oid, ".")
  IO.puts("  #{oid_string}")
end)

IO.puts("Last 10 OIDs:")
oids |> Enum.take(-10) |> Enum.each(fn oid ->
  oid_string = Enum.join(oid, ".")
  IO.puts("  #{oid_string}")
end)
