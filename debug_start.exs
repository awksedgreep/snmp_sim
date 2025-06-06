#!/usr/bin/env elixir

IO.puts "🔧 Debugging application startup..."

# Start step by step
IO.puts "1. Starting logger..."
Application.ensure_started(:logger)

IO.puts "2. Starting snmp_sim application..."
case Application.ensure_all_started(:snmp_sim) do
  {:ok, apps} ->
    IO.puts "✅ Started applications: #{inspect(apps)}"
  {:error, reason} ->
    IO.puts "❌ Failed to start application: #{inspect(reason)}"
    System.halt(1)
end

Process.sleep(1000)

IO.puts "3. Checking if supervisor is running..."
case Process.whereis(SnmpSim.Supervisor) do
  nil ->
    IO.puts "❌ Main supervisor not found"
  pid ->
    IO.puts "✅ Main supervisor running: #{inspect(pid)}"
end

IO.puts "4. Checking if device supervisor is running..."
case Process.whereis(SnmpSim.DeviceSupervisor) do
  nil ->
    IO.puts "❌ Device supervisor not found"
  pid ->
    IO.puts "✅ Device supervisor running: #{inspect(pid)}"
    
    IO.puts "5. Checking children..."
    children = DynamicSupervisor.which_children(SnmpSim.DeviceSupervisor)
    IO.puts "📊 Device supervisor has #{length(children)} children"
end

IO.puts "6. Checking all registered processes..."
registered = Process.registered()
snmp_processes = Enum.filter(registered, fn name ->
  name_str = Atom.to_string(name)
  String.contains?(name_str, "Snmp") or String.contains?(name_str, "snmp")
end)
IO.puts "🔍 SNMP-related processes: #{inspect(snmp_processes)}"

IO.puts "\n✅ Debug complete"
