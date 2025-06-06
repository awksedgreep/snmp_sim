#!/usr/bin/env elixir

# Debug script to reproduce the Test button issue
# This simulates exactly what the web UI Test button does

Mix.install([
  {:snmp_lib, "~> 1.0"}
])

defmodule TestButtonDebug do
  require Logger
  
  def run do
    Logger.configure(level: :debug)
    
    # Start a simple SNMP server to test against
    port = 10001
    
    # Create the exact SNMP v1 GetRequest that the Test button sends
    # OID: sysDescr (1.3.6.1.2.1.1.1.0)
    varbinds = [{"1.3.6.1.2.1.1.1.0", nil}]
    
    # Build SNMP v1 GetRequest message
    pdu = SnmpLib.PDU.build_get_request(12345, varbinds)
    message = SnmpLib.PDU.build_message(pdu, "public", :v1)
    
    IO.puts("=== Test Button SNMP Packet Debug ===")
    IO.puts("PDU: #{inspect(pdu)}")
    IO.puts("Message: #{inspect(message)}")
    
    case SnmpLib.PDU.encode_message(message) do
      {:ok, encoded_packet} ->
        packet_size = byte_size(encoded_packet)
        packet_hex = Base.encode16(encoded_packet)
        
        IO.puts("\n=== Encoded Packet ===")
        IO.puts("Size: #{packet_size} bytes")
        IO.puts("Hex: #{packet_hex}")
        
        # Test decoding the same packet
        IO.puts("\n=== Decode Test ===")
        case SnmpLib.PDU.decode_message(encoded_packet) do
          {:ok, decoded} ->
            IO.puts("✓ Decode successful!")
            IO.puts("Decoded: #{inspect(decoded)}")
            
            # Now test sending it to a real UDP socket
            test_udp_send(encoded_packet, port)
            
          {:error, reason} ->
            IO.puts("✗ Decode failed: #{inspect(reason)}")
        end
        
      {:error, reason} ->
        IO.puts("✗ Encode failed: #{inspect(reason)}")
    end
  end
  
  defp test_udp_send(packet, port) do
    IO.puts("\n=== UDP Send Test ===")
    
    {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])
    
    # Send to localhost
    result = :gen_udp.send(socket, {127, 0, 0, 1}, port, packet)
    IO.puts("Send result: #{inspect(result)}")
    
    # Try to receive response
    case :gen_udp.recv(socket, 0, 5000) do
      {:ok, {_ip, _port, response_data}} ->
        IO.puts("✓ Received response (#{byte_size(response_data)} bytes)")
        IO.puts("Response hex: #{Base.encode16(response_data)}")
        
        case SnmpLib.PDU.decode_message(response_data) do
          {:ok, response} ->
            IO.puts("✓ Response decoded successfully")
            IO.puts("Response: #{inspect(response)}")
          {:error, reason} ->
            IO.puts("✗ Response decode failed: #{inspect(reason)}")
        end
        
      {:error, :timeout} ->
        IO.puts("✗ No response received (timeout)")
        
      {:error, reason} ->
        IO.puts("✗ Receive error: #{inspect(reason)}")
    end
    
    :gen_udp.close(socket)
  end
end

TestButtonDebug.run()
