#!/usr/bin/env elixir

IO.puts "🧪 Testing SNMP communication..."

# Test multiple devices
test_ports = [30000, 30001, 31000, 32000]

Enum.each(test_ports, fn port ->
  IO.puts "\n📡 Testing device on port #{port}..."
  
  case System.cmd("snmpget", ["-v1", "-c", "public", "127.0.0.1:#{port}", "1.3.6.1.2.1.1.1.0"], stderr_to_stdout: true) do
    {output, 0} ->
      IO.puts "✅ SNMP GET successful: #{String.trim(output)}"
    {output, _} ->
      IO.puts "❌ SNMP GET failed: #{String.trim(output)}"
  end
end)

IO.puts "\n🔍 Checking if ports are bound..."
case System.cmd("lsof", ["-nP", "-i4UDP"], stderr_to_stdout: true) do
  {output, 0} ->
    snmp_lines = output
    |> String.split("\n")
    |> Enum.filter(fn line -> 
      Enum.any?(test_ports, fn port -> String.contains?(line, ":#{port}") end)
    end)
    
    if length(snmp_lines) > 0 do
      IO.puts "✅ Found bound ports:"
      Enum.each(snmp_lines, fn line -> IO.puts "  #{line}" end)
    else
      IO.puts "❌ No SNMP ports found in lsof output"
    end
  {output, _} ->
    IO.puts "❌ lsof failed: #{String.trim(output)}"
end
