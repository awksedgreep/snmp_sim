#!/usr/bin/env elixir

# This script checks the status of SNMP server processes
# Run this in the IEx session with: Code.eval_file("debug_servers.exs")

defmodule ServerDebug do
  def check_servers() do
    IO.puts("=== SNMP Server Process Debug ===")
    
    # Find all SnmpSim.Core.Server processes
    servers = Process.list()
    |> Enum.filter(fn pid ->
      try do
        case Process.info(pid, :dictionary) do
          {:dictionary, dict} ->
            case Keyword.get(dict, :"$initial_call") do
              {SnmpSim.Core.Server, :init, 1} -> true
              _ -> false
            end
          _ -> false
        end
      rescue
        _ -> false
      end
    end)
    
    IO.puts("Found #{length(servers)} server processes:")
    
    Enum.each(servers, fn pid ->
      try do
        # Get process info
        info = Process.info(pid)
        initial_call = Keyword.get(info[:dictionary] || [], :"$initial_call")
        
        IO.puts("\nServer PID: #{inspect(pid)}")
        IO.puts("  Status: #{info[:status]}")
        IO.puts("  Message queue: #{info[:message_queue_len]} messages")
        IO.puts("  Initial call: #{inspect(initial_call)}")
        
        # Try to get server state
        case GenServer.call(pid, :get_stats, 1000) do
          stats ->
            IO.puts("  Port: #{stats.port || "unknown"}")
            IO.puts("  Requests received: #{stats.requests_received}")
            IO.puts("  Responses sent: #{stats.responses_sent}")
          _ ->
            IO.puts("  Could not get stats")
        end
        
      rescue
        e ->
          IO.puts("  Error getting info: #{inspect(e)}")
      end
    end)
    
    if length(servers) == 0 do
      IO.puts("❌ No server processes found!")
      IO.puts("Let's check all processes with 'Server' in the name:")
      
      Process.list()
      |> Enum.each(fn pid ->
        try do
          case Process.info(pid, :dictionary) do
            {:dictionary, dict} ->
              initial_call = Keyword.get(dict, :"$initial_call")
              if initial_call && to_string(elem(initial_call, 0)) =~ "Server" do
                IO.puts("  #{inspect(pid)}: #{inspect(initial_call)}")
              end
            _ -> :ok
          end
        rescue
          _ -> :ok
        end
      end)
    end
  end
  
  def check_ports() do
    IO.puts("\n=== Port Binding Test ===")
    
    ports = [30000, 30001, 30002, 31000, 32000]
    
    Enum.each(ports, fn port ->
      case :gen_udp.open(port, [:binary, {:active, false}, {:reuseaddr, true}]) do
        {:ok, socket} ->
          IO.puts("❌ Port #{port}: Successfully bound (should be in use!)")
          :gen_udp.close(socket)
        {:error, :eaddrinuse} ->
          IO.puts("✅ Port #{port}: In use (correct)")
        {:error, reason} ->
          IO.puts("❓ Port #{port}: Error #{inspect(reason)}")
      end
    end)
  end
end

ServerDebug.check_servers()
ServerDebug.check_ports()
