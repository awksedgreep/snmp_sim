# Test script to run from within the project context

defmodule LocalSNMPTest do
  def test_device(port \\ 30000) do
    IO.puts("Testing SNMP device on port #{port}...")
    
    # Create a simple GET request for sysDescr
    oid = [1, 3, 6, 1, 2, 1, 1, 1, 0]
    request_id = :rand.uniform(1000)
    
    # Build the request using the local snmp_lib
    case SnmpLib.PDU.build_get_request(oid, request_id) do
      {:ok, pdu} ->
        IO.puts("Built PDU: #{inspect(pdu)}")
        
        case SnmpLib.PDU.build_message(pdu, "public", :v1) do
          {:ok, message} ->
            IO.puts("Built message: #{inspect(message)}")
            
            case SnmpLib.PDU.encode_message(message) do
              {:ok, packet} ->
                IO.puts("Encoded packet: #{byte_size(packet)} bytes")
                send_packet(packet, port)
              {:error, reason} ->
                IO.puts("Failed to encode: #{inspect(reason)}")
            end
          {:error, reason} ->
            IO.puts("Failed to build message: #{inspect(reason)}")
        end
      {:error, reason} ->
        IO.puts("Failed to build PDU: #{inspect(reason)}")
    end
  end
  
  defp send_packet(packet, port) do
    case :gen_udp.open(0, [:binary, {:active, false}]) do
      {:ok, socket} ->
        IO.puts("Sending packet to 127.0.0.1:#{port}...")
        
        case :gen_udp.send(socket, {127, 0, 0, 1}, port, packet) do
          :ok ->
            IO.puts("Packet sent successfully")
            
            case :gen_udp.recv(socket, 0, 5000) do
              {:ok, {_ip, _port, response}} ->
                IO.puts("Received response: #{byte_size(response)} bytes")
                
                case SnmpLib.PDU.decode_message(response) do
                  {:ok, decoded} ->
                    IO.puts("Decoded response: #{inspect(decoded)}")
                  {:error, reason} ->
                    IO.puts("Failed to decode response: #{inspect(reason)}")
                end
                
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
  
  def check_server_sockets() do
    IO.puts("Checking server processes...")
    
    # Find all server processes
    servers = Process.list()
    |> Enum.filter(fn pid ->
      case Process.info(pid, :dictionary) do
        {:dictionary, dict} ->
          Keyword.get(dict, :"$initial_call") == {SnmpSim.Core.Server, :init, 1}
        _ -> false
      end
    end)
    
    IO.puts("Found #{length(servers)} server processes")
    
    Enum.each(servers, fn pid ->
      case GenServer.call(pid, :get_stats) do
        stats ->
          IO.puts("Server #{inspect(pid)}: port #{stats.port}, requests: #{stats.requests_received}")
        _ ->
          IO.puts("Server #{inspect(pid)}: could not get stats")
      end
    end)
  end
end

# Run the tests
LocalSNMPTest.check_server_sockets()
LocalSNMPTest.test_device(30000)
