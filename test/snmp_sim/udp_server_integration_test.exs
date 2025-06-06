defmodule SnmpSim.UdpServerIntegrationTest do
  @moduledoc """
  Integration tests for the UDP SNMP server with real packet encoding/decoding.
  
  These tests verify that the server correctly handles real SNMP packets
  over UDP and responds with the correct version and format.
  """
  
  use ExUnit.Case, async: false
  
  alias SnmpSim.{LazyDevicePool, Core.Server}
  alias SnmpSim.TestHelpers.PortHelper
  alias SnmpLib.PDU
  
  @test_timeout 10_000
  
  setup do
    # Ensure clean state
    if Process.whereis(LazyDevicePool) do
      LazyDevicePool.shutdown_all_devices()
    else
      {:ok, _} = LazyDevicePool.start_link()
    end
    
    test_port = PortHelper.get_port()
    {:ok, device_pid} = LazyDevicePool.get_or_create_device(test_port)
    
    # Give the server time to start
    Process.sleep(100)
    
    {:ok, test_port: test_port, device_pid: device_pid}
  end
  
  describe "UDP Server SNMP Version Handling" do
    test "server responds to SNMPv1 UDP packets with v1 format", %{test_port: test_port} do
      # Create SNMPv1 GET request
      oid_list = [1, 3, 6, 1, 2, 1, 1, 1, 0]
      pdu = SnmpLib.PDU.build_get_request(oid_list, 12345)
      message = SnmpLib.PDU.build_message(pdu, "public", :v1)
      
      {:ok, encoded_packet} = SnmpLib.PDU.encode_message(message)
      
      # Send UDP packet
      {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])
      :ok = :gen_udp.send(socket, {127, 0, 0, 1}, test_port, encoded_packet)
      
      # Receive response
      case :gen_udp.recv(socket, 0, 5000) do
        {:ok, {_ip, _port, response_packet}} ->
          {:ok, response_message} = SnmpLib.PDU.decode_message(response_packet)
          
          # Verify response is SNMPv1
          assert response_message.version == 0
          assert response_message.community == "public"
          assert response_message.pdu.type == :get_response
          assert response_message.pdu.request_id == 12345
          assert length(response_message.pdu.varbinds) == 1
          
        {:error, reason} ->
          flunk("Failed to receive UDP response: #{inspect(reason)}")
      end
      
      :gen_udp.close(socket)
    end
    
    test "server responds to SNMPv2c UDP packets with v2c format", %{test_port: test_port} do
      # Create SNMPv2c GET request
      oid_list = [1, 3, 6, 1, 2, 1, 1, 1, 0]
      pdu = SnmpLib.PDU.build_get_request(oid_list, 23456)
      message = SnmpLib.PDU.build_message(pdu, "public", :v2c)
      
      {:ok, encoded_packet} = SnmpLib.PDU.encode_message(message)
      
      # Send UDP packet
      {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])
      :ok = :gen_udp.send(socket, {127, 0, 0, 1}, test_port, encoded_packet)
      
      # Receive response
      case :gen_udp.recv(socket, 0, 5000) do
        {:ok, {_ip, _port, response_packet}} ->
          {:ok, response_message} = SnmpLib.PDU.decode_message(response_packet)
          
          # Verify response is SNMPv2c
          assert response_message.version == 1
          assert response_message.community == "public"
          assert response_message.pdu.type == :get_response
          assert response_message.pdu.request_id == 23456
          assert length(response_message.pdu.varbinds) == 1
          
        {:error, reason} ->
          flunk("Failed to receive UDP response: #{inspect(reason)}")
      end
      
      :gen_udp.close(socket)
    end
    
    test "server handles SNMPv1 GETNEXT requests correctly", %{test_port: test_port} do
      # Create SNMPv1 GETNEXT request
      oid_list = [1, 3, 6, 1, 2, 1, 1]
      pdu = SnmpLib.PDU.build_get_next_request(oid_list, 34567)
      message = SnmpLib.PDU.build_message(pdu, "public", :v1)
      
      {:ok, encoded_packet} = SnmpLib.PDU.encode_message(message)
      
      # Send UDP packet
      {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])
      :ok = :gen_udp.send(socket, {127, 0, 0, 1}, test_port, encoded_packet)
      
      # Receive response
      case :gen_udp.recv(socket, 0, 5000) do
        {:ok, {_ip, _port, response_packet}} ->
          {:ok, response_message} = SnmpLib.PDU.decode_message(response_packet)
          
          # Verify response
          assert response_message.version == 0
          assert response_message.pdu.type == :get_response
          assert response_message.pdu.request_id == 34567
          assert length(response_message.pdu.varbinds) == 1
          
          [{oid, _type, _value}] = response_message.pdu.varbinds
          oid_string = oid_to_string(oid)
          assert oid_string >= "1.3.6.1.2.1.1"  # Should be >= requested OID
          
        {:error, reason} ->
          flunk("Failed to receive UDP response: #{inspect(reason)}")
      end
      
      :gen_udp.close(socket)
    end
    
    test "server handles SNMPv2c GETNEXT requests correctly", %{test_port: test_port} do
      # Create SNMPv2c GETNEXT request
      oid_list = [1, 3, 6, 1, 2, 1, 1]
      pdu = SnmpLib.PDU.build_get_next_request(oid_list, 45678)
      message = SnmpLib.PDU.build_message(pdu, "public", :v2c)
      
      {:ok, encoded_packet} = SnmpLib.PDU.encode_message(message)
      
      # Send UDP packet
      {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])
      :ok = :gen_udp.send(socket, {127, 0, 0, 1}, test_port, encoded_packet)
      
      # Receive response
      case :gen_udp.recv(socket, 0, 5000) do
        {:ok, {_ip, _port, response_packet}} ->
          {:ok, response_message} = SnmpLib.PDU.decode_message(response_packet)
          
          # Verify response
          assert response_message.version == 1
          assert response_message.pdu.type == :get_response
          assert response_message.pdu.request_id == 45678
          assert length(response_message.pdu.varbinds) == 1
          
          [{oid, _type, _value}] = response_message.pdu.varbinds
          oid_string = oid_to_string(oid)
          assert oid_string >= "1.3.6.1.2.1.1"  # Should be >= requested OID
          
        {:error, reason} ->
          flunk("Failed to receive UDP response: #{inspect(reason)}")
      end
      
      :gen_udp.close(socket)
    end
    
    test "server handles SNMPv2c GETBULK requests correctly", %{test_port: test_port} do
      # Create SNMPv2c GETBULK request
      oid_list = [1, 3, 6, 1, 2, 1, 1]
      pdu = SnmpLib.PDU.build_get_bulk_request(oid_list, 56789, 0, 5)
      message = SnmpLib.PDU.build_message(pdu, "public", :v2c)
      
      {:ok, encoded_packet} = SnmpLib.PDU.encode_message(message)
      
      # Send UDP packet
      {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])
      :ok = :gen_udp.send(socket, {127, 0, 0, 1}, test_port, encoded_packet)
      
      # Receive response
      case :gen_udp.recv(socket, 0, 5000) do
        {:ok, {_ip, _port, response_packet}} ->
          {:ok, response_message} = SnmpLib.PDU.decode_message(response_packet)
          
          # Verify response
          assert response_message.version == 1
          assert response_message.pdu.type == :get_response
          assert response_message.pdu.request_id == 56789
          assert length(response_message.pdu.varbinds) <= 5  # Respects max_repetitions
          
        {:error, reason} ->
          flunk("Failed to receive UDP response: #{inspect(reason)}")
      end
      
      :gen_udp.close(socket)
    end
    
    test "server rejects wrong community string", %{test_port: test_port} do
      # Create request with wrong community
      oid_list = [1, 3, 6, 1, 2, 1, 1, 1, 0]
      pdu = SnmpLib.PDU.build_get_request(oid_list, 67890)
      message = SnmpLib.PDU.build_message(pdu, "wrong_community", :v1)
      
      {:ok, encoded_packet} = SnmpLib.PDU.encode_message(message)
      
      # Send UDP packet
      {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])
      :ok = :gen_udp.send(socket, {127, 0, 0, 1}, test_port, encoded_packet)
      
      # Should timeout (no response for auth failure)
      case :gen_udp.recv(socket, 0, 2000) do
        {:ok, _} ->
          flunk("Should not receive response for wrong community")
        {:error, :timeout} ->
          :ok  # Expected behavior
        {:error, reason} ->
          flunk("Unexpected error: #{inspect(reason)}")
      end
      
      :gen_udp.close(socket)
    end
  end
  
  describe "UDP Server Walk Simulation" do
    test "simulate SNMP walk using GETNEXT sequence - SNMPv1", %{test_port: test_port} do
      {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])
      
      # Start walk
      current_oid = "1.3.6.1.2.1.1"
      walked_oids = []
      request_id = 10000
      
      walked_oids = walk_subtree_udp(socket, test_port, current_oid, :v1, request_id, walked_oids, 10)
      
      # Should have walked some OIDs
      assert length(walked_oids) > 0
      
      # All OIDs should be in the subtree or beyond
      for oid <- walked_oids do
        assert oid >= "1.3.6.1.2.1.1"
      end
      
      :gen_udp.close(socket)
    end
    
    test "simulate SNMP walk using GETNEXT sequence - SNMPv2c", %{test_port: test_port} do
      {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])
      
      # Start walk
      current_oid = "1.3.6.1.2.1.1"
      walked_oids = []
      request_id = 20000
      
      walked_oids = walk_subtree_udp(socket, test_port, current_oid, :v2c, request_id, walked_oids, 10)
      
      # Should have walked some OIDs
      assert length(walked_oids) > 0
      
      # All OIDs should be in the subtree or beyond
      for oid <- walked_oids do
        assert oid >= "1.3.6.1.2.1.1"
      end
      
      :gen_udp.close(socket)
    end
  end
  
  # Helper function to convert OID list to string
  defp oid_to_string(oid_list) when is_list(oid_list) do
    oid_list |> Enum.join(".")
  end
  defp oid_to_string(oid_string) when is_binary(oid_string), do: oid_string

  # Helper function to simulate SNMP walk over UDP
  defp walk_subtree_udp(_socket, _port, _current_oid, _version, _request_id, walked_oids, 0) do
    walked_oids  # Limit recursion
  end
  
  defp walk_subtree_udp(socket, port, current_oid, version, request_id, walked_oids, limit) do
    # Convert string OID to list format for PDU
    oid_list = current_oid
    |> String.split(".")
    |> Enum.map(&String.to_integer/1)
    
    # Create GETNEXT request
    pdu = SnmpLib.PDU.build_get_next_request(oid_list, request_id)
    message = SnmpLib.PDU.build_message(pdu, "public", version)
    
    case SnmpLib.PDU.encode_message(message) do
      {:ok, encoded_packet} ->
        :ok = :gen_udp.send(socket, {127, 0, 0, 1}, port, encoded_packet)
        
        case :gen_udp.recv(socket, 0, 2000) do
          {:ok, {_ip, _port, response_packet}} ->
            case SnmpLib.PDU.decode_message(response_packet) do
              {:ok, response_message} ->
                case response_message.pdu.varbinds do
                  [{next_oid_list, _type, value}] when is_list(next_oid_list) ->
                    next_oid_string = oid_to_string(next_oid_list)
                    
                    # Check if we're still in the subtree
                    if String.starts_with?(next_oid_string, "1.3.6.1.2.1.1") and 
                       next_oid_string != current_oid and
                       value != :end_of_mib_view do
                      # Continue walking
                      new_walked = [next_oid_string | walked_oids]
                      walk_subtree_udp(socket, port, next_oid_string, version, request_id + 1, new_walked, limit - 1)
                    else
                      walked_oids  # End of subtree
                    end
                  
                  _ ->
                    walked_oids  # Unexpected format
                end
              
              {:error, _} ->
                walked_oids  # Decode error
            end
          
          {:error, _} ->
            walked_oids  # Network error
        end
      
      {:error, _} ->
        walked_oids  # Encode error
    end
  end
end
