#!/usr/bin/env elixir

defmodule UDPTest do
  def test_port(port) do
    IO.puts("Testing UDP port #{port}...")
    
    case :gen_udp.open(0, [:binary, {:active, false}]) do
      {:ok, socket} ->
        test_data = "hello"
        
        case :gen_udp.send(socket, {127, 0, 0, 1}, port, test_data) do
          :ok ->
            IO.puts("✅ Packet sent successfully to port #{port}")
            
            case :gen_udp.recv(socket, 0, 2000) do
              {:ok, {_ip, _port, response}} ->
                IO.puts("✅ Received response: #{inspect(response)}")
              {:error, :timeout} ->
                IO.puts("❌ TIMEOUT - No response received")
              {:error, reason} ->
                IO.puts("❌ Receive error: #{inspect(reason)}")
            end
            
          {:error, reason} ->
            IO.puts("❌ Send error: #{inspect(reason)}")
        end
        
        :gen_udp.close(socket)
      {:error, reason} ->
        IO.puts("❌ Failed to open socket: #{inspect(reason)}")
    end
  end
  
  def test_bind(port) do
    IO.puts("Testing if we can bind to port #{port}...")
    
    case :gen_udp.open(port, [:binary, {:active, false}, {:reuseaddr, true}]) do
      {:ok, socket} ->
        IO.puts("✅ Successfully bound to port #{port}")
        :gen_udp.close(socket)
      {:error, :eaddrinuse} ->
        IO.puts("✅ Port #{port} is already in use (good - server is running)")
      {:error, reason} ->
        IO.puts("❌ Failed to bind to port #{port}: #{inspect(reason)}")
    end
  end
end

# Test ports
Enum.each([30000, 30001, 30002, 31000, 32000], fn port ->
  UDPTest.test_bind(port)
  UDPTest.test_port(port)
  IO.puts("")
end)
