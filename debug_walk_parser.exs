#!/usr/bin/env elixir

# Debug script to test walk parser
Mix.install([])

# Load the application modules by compiling them first
Code.compile_file("lib/snmp_sim_ex/walk_parser.ex")

# Test the walk parser
line = "SNMPv2-MIB::sysDescr.0 = STRING: \"Motorola SB6141 DOCSIS 3.0 Cable Modem\""
result = SnmpSim.WalkParser.parse_walk_line(line)

IO.puts("Input line: #{line}")
IO.puts("Parsed result: #{inspect(result, pretty: true)}")

case result do
  {oid, data} ->
    IO.puts("\nOID: #{oid}")
    IO.puts("Data: #{inspect(data, pretty: true)}")
  other ->
    IO.puts("\nUnexpected result: #{inspect(other)}")
end

# Test a few more lines
test_lines = [
  "IF-MIB::ifInOctets.1 = Counter32: 1234567890",
  ".1.3.6.1.2.1.1.1.0 = STRING: \"Direct OID test\""
]

IO.puts("\n--- Testing additional lines ---")
for line <- test_lines do
  result = SnmpSim.WalkParser.parse_walk_line(line)
  IO.puts("Line: #{line}")
  IO.puts("Result: #{inspect(result, pretty: true)}")
  IO.puts("")
end