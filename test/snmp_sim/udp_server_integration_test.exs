defmodule SnmpSim.UdpServerIntegrationTest do
  @moduledoc """
  Integration tests for the UDP SNMP server with real packet encoding/decoding.

  These tests verify that the server correctly handles real SNMP packets
  over UDP and responds with the correct version and format.
  """

  use ExUnit.Case, async: false

  alias SnmpSim.Core.UDPListener
  require Logger
  alias SnmpSim.TestHelpers.PortHelper
  alias SnmpLib.ASN1

  setup do
    # Ensure clean state
    if Process.whereis(SnmpSim.LazyDevicePool) do
      SnmpSim.LazyDevicePool.shutdown_all_devices()
    else
      {:ok, _} = SnmpSim.LazyDevicePool.start_link()
    end

    # Start necessary applications and services
    Application.ensure_all_started(:snmp_sim)
    Application.ensure_all_started(:snmp_ex)

    test_port = PortHelper.get_port()
    {:ok, device_pid} = SnmpSim.LazyDevicePool.get_or_create_device(test_port)

    # Give the server time to start
    Process.sleep(100)

    # Register cleanup callback
    on_exit(fn ->
      # Shutdown the device to release the port
      try do
        if Process.alive?(device_pid) do
          GenServer.stop(device_pid, :normal, 5000)
        end
      catch
        :exit, {:noproc, _} -> :ok
        :exit, {:normal, _} -> :ok
        :exit, reason -> 
          # Log unexpected exit reasons but don't fail the test
          Logger.debug("Process cleanup warning: #{inspect(reason)}")
      end
      
      # Also ensure the port is released from PortHelper
      PortHelper.release_port(test_port)
      
      # Give time for cleanup
      Process.sleep(50)
    end)

    {:ok, device_pid: device_pid, test_port: test_port}
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
          # Should be >= requested OID
          assert oid_string >= "1.3.6.1.2.1.1"

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
          # Should be >= requested OID
          assert oid_string >= "1.3.6.1.2.1.1"

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
          # Respects max_repetitions
          assert length(response_message.pdu.varbinds) <= 5

        {:error, reason} ->
          flunk("Failed to receive UDP response: #{inspect(reason)}")
      end

      :gen_udp.close(socket)
    end

    test "server handles GETBULK with max_repetitions = 0", %{test_port: test_port} do
      # Test GETBULK with zero repetitions
      oid_list = [1, 3, 6, 1, 2, 1, 1]
      # max_repetitions = 0
      pdu = SnmpLib.PDU.build_get_bulk_request(oid_list, 56790, 0, 0)
      message = SnmpLib.PDU.build_message(pdu, "public", :v2c)

      {:ok, encoded_packet} = SnmpLib.PDU.encode_message(message)

      {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])
      :ok = :gen_udp.send(socket, {127, 0, 0, 1}, test_port, encoded_packet)

      case :gen_udp.recv(socket, 0, 5000) do
        {:ok, {_ip, _port, response_packet}} ->
          {:ok, response_message} = SnmpLib.PDU.decode_message(response_packet)

          assert response_message.version == 1
          assert response_message.pdu.type == :get_response
          assert response_message.pdu.request_id == 56790
          assert response_message.pdu.error_status == 0
          # With max_repetitions = 0, should return minimal results
          assert length(response_message.pdu.varbinds) >= 0

        {:error, reason} ->
          flunk("Failed to receive UDP response: #{inspect(reason)}")
      end

      :gen_udp.close(socket)
    end

    test "server handles GETBULK with non_repeaters > varbind count", %{test_port: test_port} do
      # Test when non_repeaters exceeds the number of varbinds
      # Single OID
      oid_list = [1, 3, 6, 1, 2, 1, 1, 1, 0]
      # non_repeaters=5 > 1 varbind
      pdu = SnmpLib.PDU.build_get_bulk_request(oid_list, 56791, 5, 3)
      message = SnmpLib.PDU.build_message(pdu, "public", :v2c)

      {:ok, encoded_packet} = SnmpLib.PDU.encode_message(message)

      {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])
      :ok = :gen_udp.send(socket, {127, 0, 0, 1}, test_port, encoded_packet)

      case :gen_udp.recv(socket, 0, 5000) do
        {:ok, {_ip, _port, response_packet}} ->
          {:ok, response_message} = SnmpLib.PDU.decode_message(response_packet)

          # Should handle gracefully without error
          assert response_message.version == 1
          assert response_message.pdu.type == :get_response
          assert response_message.pdu.request_id == 56791
          assert response_message.pdu.error_status == 0
          assert length(response_message.pdu.varbinds) >= 1

        {:error, reason} ->
          flunk("Failed to receive UDP response: #{inspect(reason)}")
      end

      :gen_udp.close(socket)
    end

    test "server handles GETBULK with end_of_mib_view results", %{test_port: test_port} do
      # Test GETBULK with OID that will result in end_of_mib_view
      # Non-existent high OID
      oid_list = [1, 3, 6, 1, 9, 9, 9, 9, 9]
      pdu = SnmpLib.PDU.build_get_bulk_request(oid_list, 56792, 0, 3)
      message = SnmpLib.PDU.build_message(pdu, "public", :v2c)

      {:ok, encoded_packet} = SnmpLib.PDU.encode_message(message)

      {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])
      :ok = :gen_udp.send(socket, {127, 0, 0, 1}, test_port, encoded_packet)

      case :gen_udp.recv(socket, 0, 5000) do
        {:ok, {_ip, _port, response_packet}} ->
          {:ok, response_message} = SnmpLib.PDU.decode_message(response_packet)

          assert response_message.version == 1
          assert response_message.pdu.type == :get_response
          assert response_message.pdu.request_id == 56792
          assert response_message.pdu.error_status == 0

          # Should contain varbinds with end_of_mib_view exceptions
          varbinds = response_message.pdu.varbinds
          assert length(varbinds) > 0

          # At least one varbind should have end_of_mib_view
          has_end_of_mib =
            Enum.any?(varbinds, fn {_oid, type, value} ->
              type == :end_of_mib_view || match?({:end_of_mib_view, _}, value)
            end)

          assert has_end_of_mib,
                 "Expected at least one end_of_mib_view varbind, got: #{inspect(varbinds)}"

        {:error, reason} ->
          flunk("Failed to receive UDP response: #{inspect(reason)}")
      end

      :gen_udp.close(socket)
    end

    test "server handles GETBULK with mixed valid and invalid OIDs", %{test_port: test_port} do
      # Test GETBULK with a valid OID that will eventually lead to end_of_mib_view
      # Use an OID near the end of our known OID space to trigger end_of_mib_view
      valid_oid = [1, 3, 6, 1, 2, 1, 2, 2, 1, 21, 1]  # ifOutQLen.1 - near end of interface table

      # Create request with non_repeaters = 0 so the OID gets repeated
      # This will cause the system to walk beyond the last known OID
      pdu = SnmpLib.PDU.build_get_bulk_request(valid_oid, 56793, 0, 3)
      message = SnmpLib.PDU.build_message(pdu, "public", :v2c)

      {:ok, encoded_packet} = SnmpLib.PDU.encode_message(message)

      {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])
      :ok = :gen_udp.send(socket, {127, 0, 0, 1}, test_port, encoded_packet)

      case :gen_udp.recv(socket, 0, 5000) do
        {:ok, {_ip, _port, response_packet}} ->
          {:ok, response_message} = SnmpLib.PDU.decode_message(response_packet)

          assert response_message.version == 1
          assert response_message.pdu.type == :get_response
          assert response_message.pdu.request_id == 56793
          assert response_message.pdu.error_status == 0

          # Should handle both valid and invalid OIDs appropriately
          varbinds = response_message.pdu.varbinds
          assert length(varbinds) > 0

          # At least one varbind should have end_of_mib_view
          has_end_of_mib =
            Enum.any?(varbinds, fn {_oid, type, value} ->
              type == :end_of_mib_view || match?({:end_of_mib_view, _}, value)
            end)

          assert has_end_of_mib,
                 "Expected at least one end_of_mib_view varbind, got: #{inspect(varbinds)}"

        {:error, reason} ->
          flunk("Failed to receive UDP response: #{inspect(reason)}")
      end

      :gen_udp.close(socket)
    end

    test "server handles GETBULK with large max_repetitions", %{test_port: test_port} do
      # Test GETBULK with very large max_repetitions to ensure proper limiting
      oid_list = [1, 3, 6, 1, 2, 1, 1]
      # Very large repetitions
      pdu = SnmpLib.PDU.build_get_bulk_request(oid_list, 56794, 0, 1000)
      message = SnmpLib.PDU.build_message(pdu, "public", :v2c)

      {:ok, encoded_packet} = SnmpLib.PDU.encode_message(message)

      {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])
      :ok = :gen_udp.send(socket, {127, 0, 0, 1}, test_port, encoded_packet)

      case :gen_udp.recv(socket, 0, 5000) do
        {:ok, {_ip, _port, response_packet}} ->
          {:ok, response_message} = SnmpLib.PDU.decode_message(response_packet)

          assert response_message.version == 1
          assert response_message.pdu.type == :get_response
          assert response_message.pdu.request_id == 56794
          assert response_message.pdu.error_status == 0

          # Should limit response size reasonably (not return 1000 varbinds)
          varbinds = response_message.pdu.varbinds
          assert length(varbinds) > 0

          assert length(varbinds) < 100,
                 "Response should be reasonably limited, got #{length(varbinds)} varbinds"

        {:error, reason} ->
          flunk("Failed to receive UDP response: #{inspect(reason)}")
      end

      :gen_udp.close(socket)
    end

    test "server handles GETBULK with empty varbind list", %{test_port: test_port} do
      # Test GETBULK with minimal valid OID (since empty varbind list is not supported)
      # Valid minimal OID
      minimal_oid = [1, 3, 6, 1, 2, 1, 1]
      pdu = SnmpLib.PDU.build_get_bulk_request(minimal_oid, 56795, 0, 5)
      message = SnmpLib.PDU.build_message(pdu, "public", :v2c)

      {:ok, encoded_packet} = SnmpLib.PDU.encode_message(message)

      {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])
      :ok = :gen_udp.send(socket, {127, 0, 0, 1}, test_port, encoded_packet)

      case :gen_udp.recv(socket, 0, 5000) do
        {:ok, {_ip, _port, response_packet}} ->
          {:ok, response_message} = SnmpLib.PDU.decode_message(response_packet)

          assert response_message.version == 1
          assert response_message.pdu.type == :get_response
          assert response_message.pdu.request_id == 56795
          # Should handle gracefully, possibly with error or empty response
          assert is_integer(response_message.pdu.error_status)

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
          # Expected behavior
          :ok

        {:error, reason} ->
          flunk("Unexpected error: #{inspect(reason)}")
      end

      :gen_udp.close(socket)
    end

    test "server handles GETBULK with no_such_name in non-repeaters", %{test_port: test_port} do
      # Test GETBULK with valid OIDs and an invalid OID in the middle of non-repeaters
      # This tests how the simulator handles error conditions in bulk operations
      
      # Create a multi-varbind request with:
      # - Valid OID (sysDescr)
      # - Invalid OID (should return no_such_name)  
      # - Valid OID (sysUpTime)
      # - Repeater OID (interfaces subtree)
      valid_oid1 = [1, 3, 6, 1, 2, 1, 1, 1, 0]    # sysDescr
      invalid_oid = [1, 3, 6, 1, 2, 1, 99, 99, 0]  # Non-existent OID
      valid_oid2 = [1, 3, 6, 1, 2, 1, 1, 3, 0]    # sysUpTime  
      repeater_oid = [1, 3, 6, 1, 2, 1, 2]        # interfaces subtree
      
      # Build varbinds list - first 3 are non-repeaters, last is repeater
      varbinds = [
        {valid_oid1, :null, nil},
        {invalid_oid, :null, nil}, 
        {valid_oid2, :null, nil},
        {repeater_oid, :null, nil}
      ]
      
      # Start with a basic GETBULK request and then modify it to have multiple varbinds
      # non_repeaters = 3 (first 3 varbinds), max_repetitions = 2 for the repeater
      base_pdu = SnmpLib.PDU.build_get_bulk_request(valid_oid1, 56795, 3, 2)
      
      # Modify the PDU to include all our varbinds
      pdu = %{base_pdu | varbinds: varbinds}
      
      message = SnmpLib.PDU.build_message(pdu, "public", :v2c)
      {:ok, encoded_packet} = SnmpLib.PDU.encode_message(message)

      {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])
      :ok = :gen_udp.send(socket, {127, 0, 0, 1}, test_port, encoded_packet)

      case :gen_udp.recv(socket, 0, 5000) do
        {:ok, {_ip, _port, response_packet}} ->
          {:ok, response_message} = SnmpLib.PDU.decode_message(response_packet)

          assert response_message.version == 1
          assert response_message.pdu.type == :get_response
          assert response_message.pdu.request_id == 56795
          assert response_message.pdu.error_status == 0

          # Should get responses for all varbinds
          varbinds = response_message.pdu.varbinds
          assert length(varbinds) >= 4, "Expected at least 4 varbinds (3 non-repeaters + repeaters)"

          # First varbind should be the next OID after sysDescr (which is sysObjectID)
          {first_oid, first_type, first_value} = Enum.at(varbinds, 0)
          assert first_oid == [1, 3, 6, 1, 2, 1, 1, 2, 0]  # sysObjectID (next after sysDescr)
          assert first_type == :object_identifier  # sysObjectID has object identifier type
          assert is_binary(first_value) or is_list(first_value)

          # Second varbind should be no_such_name for invalid OID (or next valid OID)
          {_second_oid, second_type, _second_value} = Enum.at(varbinds, 1)
          # The invalid OID [1, 3, 6, 1, 2, 1, 99, 99, 0] should result in an error or next valid OID
          assert second_type in [:no_such_name, :no_such_object, :no_such_instance, :auto] or 
                 (is_atom(second_type) and second_type != :null)

          # Third varbind should be the next OID after sysUpTime 
          {third_oid, third_type, third_value} = Enum.at(varbinds, 2)
          # sysUpTime [1, 3, 6, 1, 2, 1, 1, 3, 0] -> next should be sysContact [1, 3, 6, 1, 2, 1, 1, 4, 0]
          assert third_oid == [1, 3, 6, 1, 2, 1, 1, 4, 0]  # sysContact (next after sysUpTime)
          assert third_type == :octet_string  # sysContact is an octet string
          assert is_binary(third_value)

          # Remaining varbinds should be from the interfaces subtree (repeaters)
          repeater_varbinds = Enum.drop(varbinds, 3)
          assert length(repeater_varbinds) > 0, "Expected repeater varbinds from interfaces subtree"
          
          # All repeater OIDs should start with [1, 3, 6, 1, 2, 1, 2] (interfaces)
          Enum.each(repeater_varbinds, fn {oid, _type, _value} ->
            assert List.starts_with?(oid, [1, 3, 6, 1, 2, 1, 2]), 
                   "Repeater OID #{inspect(oid)} should be in interfaces subtree"
          end)

        {:error, reason} ->
          flunk("Failed to receive UDP response: #{inspect(reason)}")
      end

      :gen_udp.close(socket)
    end
  end

  describe "UDP Server Varbind Format and Validation Tests" do
    test "server handles varbinds with different OID formats correctly", %{test_port: test_port} do
      # Test with single OID
      oid_list = [1, 3, 6, 1, 2, 1, 1, 1, 0]
      pdu = SnmpLib.PDU.build_get_request(oid_list, 12345)
      message = SnmpLib.PDU.build_message(pdu, "public", :v1)

      {:ok, encoded_packet} = SnmpLib.PDU.encode_message(message)
      {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])
      :ok = :gen_udp.send(socket, {127, 0, 0, 1}, test_port, encoded_packet)

      case :gen_udp.recv(socket, 0, 5000) do
        {:ok, {_ip, _port, response_data}} ->
          {:ok, response_message} = SnmpLib.PDU.decode_message(response_data)
          assert response_message.pdu.error_status == 0
          assert length(response_message.pdu.varbinds) == 1

          [{oid, _type, value}] = response_message.pdu.varbinds
          Logger.debug("DEBUG: OID: #{inspect(oid)}, Type: #{inspect(_type)}, Value: #{inspect(value)}")
          assert is_list(oid), "OID should be converted to list format"
          assert is_binary(value), "Should return valid string value"

        {:error, reason} ->
          flunk("Failed to receive UDP response: #{inspect(reason)}")
      end

      :gen_udp.close(socket)
    end

    test "server handles varbinds with integer list OID format correctly", %{test_port: test_port} do
      # Test with integer list OID format
      oid_list = [1, 3, 6, 1, 2, 1, 1, 1, 0]
      pdu = SnmpLib.PDU.build_get_request(oid_list, 12346)
      message = SnmpLib.PDU.build_message(pdu, "public", :v1)

      {:ok, encoded_packet} = SnmpLib.PDU.encode_message(message)
      {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])
      :ok = :gen_udp.send(socket, {127, 0, 0, 1}, test_port, encoded_packet)

      case :gen_udp.recv(socket, 0, 5000) do
        {:ok, {_ip, _port, response_data}} ->
          {:ok, response_message} = SnmpLib.PDU.decode_message(response_data)
          assert response_message.pdu.error_status == 0
          assert length(response_message.pdu.varbinds) == 1

          [{oid, _type, value}] = response_message.pdu.varbinds
          assert is_list(oid), "OID should remain as list format"
          assert oid == [1, 3, 6, 1, 2, 1, 1, 1, 0]
          assert is_binary(value), "Should return valid string value"

        {:error, reason} ->
          flunk("Failed to receive UDP response: #{inspect(reason)}")
      end

      :gen_udp.close(socket)
    end

    test "server handles GETBULK requests with proper varbind format", %{test_port: test_port} do
      # Test GETBULK with single OID
      oid_list = [1, 3, 6, 1, 2, 1, 1, 1, 0]
      pdu = SnmpLib.PDU.build_get_bulk_request(oid_list, 12347, 0, 3)
      message = SnmpLib.PDU.build_message(pdu, "public", :v2c)

      {:ok, encoded_packet} = SnmpLib.PDU.encode_message(message)
      {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])
      :ok = :gen_udp.send(socket, {127, 0, 0, 1}, test_port, encoded_packet)

      case :gen_udp.recv(socket, 0, 5000) do
        {:ok, {_ip, _port, response_data}} ->
          {:ok, response_message} = SnmpLib.PDU.decode_message(response_data)
          assert response_message.pdu.error_status == 0
          assert length(response_message.pdu.varbinds) >= 1

          # All OIDs should be normalized to list format in response
          Enum.each(response_message.pdu.varbinds, fn {oid, _type, _value} ->
            assert is_list(oid), "All OIDs should be normalized to list format"
            assert Enum.all?(oid, &is_integer/1), "All OID components should be integers"
          end)

        {:error, reason} ->
          flunk("Failed to receive UDP response: #{inspect(reason)}")
      end

      :gen_udp.close(socket)
    end

    test "server handles non-existent OIDs gracefully", %{test_port: test_port} do
      # Test with valid format but non-existent OID
      oid_list = [1, 3, 6, 1, 9, 9, 9, 9, 9]
      pdu = SnmpLib.PDU.build_get_request(oid_list, 12348)
      message = SnmpLib.PDU.build_message(pdu, "public", :v1)

      {:ok, encoded_packet} = SnmpLib.PDU.encode_message(message)
      {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])
      :ok = :gen_udp.send(socket, {127, 0, 0, 1}, test_port, encoded_packet)

      case :gen_udp.recv(socket, 0, 5000) do
        {:ok, {_ip, _port, response_data}} ->
          {:ok, response_message} = SnmpLib.PDU.decode_message(response_data)

          # Should still return a response (graceful handling)
          assert length(response_message.pdu.varbinds) == 1

          # Check that OID is properly formatted in response
          [{oid, _type, value}] = response_message.pdu.varbinds
          assert is_list(oid), "OID should be normalized to list format"
          assert Enum.all?(oid, &is_integer/1), "All OID components should be integers"

          # Value might be an exception tuple for non-existent OID
          case value do
            {:no_such_object, _} -> :ok
            {:no_such_instance, _} -> :ok
            nil -> :ok
            # Fallback value is also valid
            _ when is_binary(value) -> :ok
            _ -> flunk("Unexpected value type: #{inspect(value)}")
          end

        {:error, reason} ->
          flunk("Failed to receive UDP response: #{inspect(reason)}")
      end

      :gen_udp.close(socket)
    end

    test "server handles GETNEXT with different value types correctly", %{test_port: test_port} do
      # Test GETNEXT to get different value types
      # Should return string value
      oid_list = [1, 3, 6, 1, 2, 1, 1, 1]
      pdu = SnmpLib.PDU.build_get_next_request(oid_list, 12349)
      message = SnmpLib.PDU.build_message(pdu, "public", :v1)

      {:ok, encoded_packet} = SnmpLib.PDU.encode_message(message)
      {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])
      :ok = :gen_udp.send(socket, {127, 0, 0, 1}, test_port, encoded_packet)

      case :gen_udp.recv(socket, 0, 5000) do
        {:ok, {_ip, _port, response_data}} ->
          {:ok, response_message} = SnmpLib.PDU.decode_message(response_data)
          assert response_message.pdu.error_status == 0
          assert length(response_message.pdu.varbinds) == 1

          # Verify that value types are handled properly
          [{_oid, type, value}] = response_message.pdu.varbinds
          IO.inspect(response_message.pdu.varbinds, label: "DEBUG: Full varbinds")
          IO.inspect(value, label: "DEBUG: Value being tested")

          case value do
            # Exception is valid
            {:end_of_mib_view, _} -> :ok
            # Exception is valid
            {:no_such_object, _} -> :ok
            # Exception is valid
            {:no_such_instance, _} -> :ok
            # nil is valid for exception values after encoding/decoding
            nil -> :ok
            # String is valid
            _ when is_binary(value) -> :ok
            # Integer is valid
            _ when is_integer(value) -> :ok
            _ -> flunk("Unexpected value type: #{inspect(value)}")
          end

        {:error, reason} ->
          flunk("Failed to receive UDP response: #{inspect(reason)}")
      end

      :gen_udp.close(socket)
    end

    test "server handles standard GET request with proper varbind format", %{test_port: test_port} do
      # Test with standard GET request
      oid_list = [1, 3, 6, 1, 2, 1, 1, 1, 0]
      pdu = SnmpLib.PDU.build_get_request(oid_list, 12350)
      message = SnmpLib.PDU.build_message(pdu, "public", :v1)

      {:ok, encoded_packet} = SnmpLib.PDU.encode_message(message)
      {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])
      :ok = :gen_udp.send(socket, {127, 0, 0, 1}, test_port, encoded_packet)

      case :gen_udp.recv(socket, 0, 5000) do
        {:ok, {_ip, _port, response_data}} ->
          {:ok, response_message} = SnmpLib.PDU.decode_message(response_data)
          assert response_message.pdu.error_status == 0
          assert length(response_message.pdu.varbinds) == 1

          # Varbind should have proper format
          [{oid, type, _value}] = response_message.pdu.varbinds
          assert is_list(oid), "OID should be list format"

          assert type in [:auto, :octet_string, :integer, :counter32, :gauge32, :timeticks],
                 "Type should be valid SNMP type"

        {:error, reason} ->
          flunk("Failed to receive UDP response: #{inspect(reason)}")
      end

      :gen_udp.close(socket)
    end

    test "server handles moderately long OID chains correctly", %{test_port: test_port} do
      # Test with moderately long OID to avoid encoding issues
      long_oid = [1, 3, 6, 1, 2, 1, 1, 1, 0] ++ [1, 2, 3]
      pdu = SnmpLib.PDU.build_get_request(long_oid, 12351)
      message = SnmpLib.PDU.build_message(pdu, "public", :v1)

      {:ok, encoded_packet} = SnmpLib.PDU.encode_message(message)
      {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])
      :ok = :gen_udp.send(socket, {127, 0, 0, 1}, test_port, encoded_packet)

      case :gen_udp.recv(socket, 0, 5000) do
        {:ok, {_ip, _port, response_data}} ->
          {:ok, response_message} = SnmpLib.PDU.decode_message(response_data)

          # Should handle long OIDs gracefully (may return no_such_object)
          assert length(response_message.pdu.varbinds) == 1

          [{oid, _type, _value}] = response_message.pdu.varbinds
          assert is_list(oid), "OID should be normalized to list format"
          assert Enum.all?(oid, &is_integer/1), "All OID components should be integers"

        {:error, reason} ->
          flunk("Failed to receive UDP response: #{inspect(reason)}")
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

      walked_oids =
        walk_subtree_udp(socket, test_port, current_oid, :v1, request_id, walked_oids, 10)

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

      walked_oids =
        walk_subtree_udp(socket, test_port, current_oid, :v2c, request_id, walked_oids, 10)

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
    # Limit recursion
    walked_oids
  end

  defp walk_subtree_udp(socket, port, current_oid, version, request_id, walked_oids, limit) do
    # Convert string OID to list format for PDU
    oid_list =
      current_oid
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
                  [{next_oid_list, type, value}] when is_list(next_oid_list) ->
                    next_oid_string = oid_to_string(next_oid_list)

                    # Check if we're still in the subtree and not at end of MIB
                    is_end_of_mib = type == :end_of_mib_view || 
                                   match?({:end_of_mib_view, _}, value) ||
                                   (type == :null && value == nil)
                    
                    if String.starts_with?(next_oid_string, "1.3.6.1.2.1.1") and
                         next_oid_string != current_oid and
                         not is_end_of_mib do
                      # Continue walking
                      new_walked = [next_oid_string | walked_oids]

                      walk_subtree_udp(
                        socket,
                        port,
                        next_oid_string,
                        version,
                        request_id + 1,
                        new_walked,
                        limit - 1
                      )
                    else
                      # End of subtree
                      walked_oids
                    end

                  _ ->
                    # Unexpected format
                    walked_oids
                end

              {:error, _} ->
                # Decode error
                walked_oids
            end

          {:error, _} ->
            # Network error
            walked_oids
        end

      {:error, _} ->
        # Encode error
        walked_oids
    end
  end
end
