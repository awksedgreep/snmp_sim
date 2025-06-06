# Test SNMP functionality directly
alias SnmpLib.PDU

# Create a simple SNMP GET request
oid = [1, 3, 6, 1, 2, 1, 1, 1, 0]
request_id = 12345

# Build the request using the new API
pdu = PDU.build_get_request(oid, request_id)
message = PDU.build_message(pdu, "public", :v1)

case PDU.encode_message(message) do
  {:ok, packet} ->
    IO.puts("✅ Successfully built SNMP packet (#{byte_size(packet)} bytes)")
    
    # Send to port 30000
    {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])
    
    case :gen_udp.send(socket, {127, 0, 0, 1}, 30000, packet) do
      :ok ->
        IO.puts("✅ Packet sent to port 30000")
        
        # Wait for response
        case :gen_udp.recv(socket, 0, 5000) do
          {:ok, {_ip, _port, response_packet}} ->
            IO.puts("✅ Got response (#{byte_size(response_packet)} bytes)")
            
            case PDU.decode_message(response_packet) do
              {:ok, response_message} ->
                IO.puts("✅ Successfully decoded response:")
                IO.inspect(response_message, pretty: true)
                
                # Show the actual value
                case response_message.pdu.varbinds do
                  [{oid, type, value}] ->
                    IO.puts("📊 Response details:")
                    IO.puts("   OID: #{inspect(oid)}")
                    IO.puts("   Type: #{inspect(type)}")
                    IO.puts("   Value: #{inspect(value)}")
                  other ->
                    IO.puts("❓ Unexpected varbinds format: #{inspect(other)}")
                end
                
              {:error, reason} ->
                IO.puts("❌ Failed to decode response: #{inspect(reason)}")
            end
            
          {:error, :timeout} ->
            IO.puts("❌ Timeout waiting for response")
          {:error, reason} ->
            IO.puts("❌ Error receiving response: #{inspect(reason)}")
        end
        
      error ->
        IO.puts("❌ Failed to send packet: #{inspect(error)}")
    end
    
    :gen_udp.close(socket)
    
  {:error, reason} ->
    IO.puts("❌ Failed to encode packet: #{inspect(reason)}")
end
