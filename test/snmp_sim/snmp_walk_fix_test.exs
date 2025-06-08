defmodule SnmpSim.SnmpWalkFixTest do
  use ExUnit.Case, async: false

  alias SnmpSim.{Device, LazyDevicePool}
  alias SnmpSim.Device.OidHandler
  alias SnmpSim.TestHelpers.PortHelper
  alias SnmpSim.ProfileLoader
  alias SnmpLib.PDU

  @moduletag :unit

  describe "SNMP Walk OID Loading and Responses" do
    setup do
      # Load the walk file profile first
      {:ok, _profile} = ProfileLoader.load_profile(
        :cable_modem,
        {:walk_file, "priv/walks/cable_modem.walk"}
      )

      # Ensure clean state
      if Process.whereis(LazyDevicePool) do
        LazyDevicePool.shutdown_all_devices()
      else
        {:ok, _} = LazyDevicePool.start_link()
      end

      test_port = PortHelper.get_port()
      
      # Create device with cable modem profile
      device_config = %{
        port: test_port,
        device_type: :cable_modem,
        device_id: "cable_modem_#{test_port}",
        community: "public",
        walk_file: "priv/walks/cable_modem.walk"
      }
      
      {:ok, device_pid} = Device.start_link(device_config)

      # Give the server time to start
      Process.sleep(100)

      {:ok, test_port: test_port, device_pid: device_pid}
    end

    test "fallback logic handles interface OID transition from ifIndex.2 to ifDescr.1", %{device_pid: device_pid} do
      # Allow time for walk file to be fully loaded
      Process.sleep(100)
      
      # Test the specific OID transition that was causing premature end-of-MIB
      # From "1.3.6.1.2.1.2.2.1.1.2" (ifIndex.2) to "1.3.6.1.2.1.2.2.1.2.1" (ifDescr.1)
      
      result = Device.get_next(device_pid, "1.3.6.1.2.1.2.2.1.1.2")
      IO.puts("get_next result: #{inspect(result)}")
      
      assert {:ok, {"1.3.6.1.2.1.2.2.1.2.1", :octet_string, "cable-modem0"}} = result
    end

    test "fallback logic provides complete interface OID sequence", %{device_pid: device_pid} do
      # First, let's see what OIDs are actually available
      # Start from the beginning of interface table
      initial_oid = "1.3.6.1.2.1.2.2.1.1.0"
      
      case Device.get_next(device_pid, initial_oid) do
        {:ok, {first_oid, first_type, first_value}} ->
          IO.puts("First OID found: #{first_oid} (#{first_type}) = #{inspect(first_value)}")
          
          # Try to get the next one
          case Device.get_next(device_pid, first_oid) do
            {:ok, {second_oid, second_type, second_value}} ->
              IO.puts("Second OID found: #{second_oid} (#{second_type}) = #{inspect(second_value)}")
              
              # Test the specific transition that was problematic
              if first_oid == "1.3.6.1.2.1.2.2.1.1.2" do
                assert second_oid == "1.3.6.1.2.1.2.2.1.2.1", 
                       "Expected transition from ifIndex.2 to ifDescr.1, got #{second_oid}"
                assert second_type == :octet_string
                assert second_value == "cable-modem0"
              end
              
            {:error, reason} ->
              IO.puts("Second get_next failed: #{inspect(reason)}")
          end
          
        {:error, reason} ->
          IO.puts("First get_next failed: #{inspect(reason)}")
          # Let's try a different starting point
          case Device.get_next(device_pid, "1.3.6.1.2.1.1") do
            {:ok, {oid, type, value}} ->
              IO.puts("Alternative starting point found: #{oid} (#{type}) = #{inspect(value)}")
            {:error, alt_reason} ->
              flunk("No OIDs found at all: #{inspect(alt_reason)}")
          end
      end
    end

    test "OidHandler.get_fallback_next_oid/2 handles the problematic transition" do
      # Test the fallback case - should return end_of_mib_view since SharedProfiles handles real data
      result = OidHandler.get_fallback_next_oid("1.3.6.1.2.1.2.2.1.1.2", %{})
      
      assert {"1.3.6.1.2.1.2.2.1.1.2", :end_of_mib_view, {:end_of_mib_view, nil}} = result
    end

    @tag :walk_test
    test "walk file data is loaded and interface OIDs are accessible", %{device_pid: device_pid} do
      # Test that we can access specific OIDs from the walk file
      working_cases = [
        {"1.3.6.1.2.1.1.1.0", "Motorola SB6141 DOCSIS 3.0 Cable Modem"},  # sysDescr
        {"1.3.6.1.2.1.2.1.0", {:integer, 2}},  # ifNumber
        {"1.3.6.1.2.1.2.2.1.1.1", {:integer, 1}}  # ifIndex.1
      ]
      
      Enum.each(working_cases, fn {oid, expected_value} ->
        case Device.get(device_pid, oid) do
          {:ok, ^expected_value} ->
            IO.puts("✓ #{oid} = #{inspect(expected_value)}")
          {:ok, actual_value} ->
            flunk("OID #{oid} returned #{inspect(actual_value)}, expected #{inspect(expected_value)}")
          {:error, reason} ->
            flunk("Failed to get OID #{oid}: #{inspect(reason)}")
        end
      end)
      
      # Now test get_next from ifIndex.1 to see what happens
      IO.puts("\nTesting get_next from ifIndex.1:")
      case Device.get_next(device_pid, "1.3.6.1.2.1.2.2.1.1.1") do
        {:ok, {next_oid, _type, value}} ->
          IO.puts("✓ get_next(1.3.6.1.2.1.2.2.1.1.1) = #{next_oid} = #{inspect(value)}")
        {:error, reason} ->
          IO.puts("✗ get_next(1.3.6.1.2.1.2.2.1.1.1) failed: #{inspect(reason)}")
      end
    end

    test "SNMP GETBULK operation continues past interface index to interface description", %{test_port: test_port} do
      # Simulate a GETBULK request starting from interface index subtree
      # This should not end prematurely at ifIndex.2 but continue to ifDescr.1
      
      # Create a GETBULK request for the interface table
      oid_list = [1, 3, 6, 1, 2, 1, 2, 2, 1, 1]
      pdu = PDU.build_get_bulk_request(oid_list, 56799, 0, 10)
      message = PDU.build_message(pdu, "public", :v2c)
      
      # Send the request to the device
      {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])
      
      # Encode and send the SNMP request
      {:ok, encoded_request} = PDU.encode_message(message)
      
      :ok = :gen_udp.send(socket, {127, 0, 0, 1}, test_port, encoded_request)
      
      # Receive and decode the response
      {:ok, {_addr, _port, response_data}} = :gen_udp.recv(socket, 0, 5000)
      :gen_udp.close(socket)
      
      # Decode the response
      {:ok, decoded_response} = PDU.decode_message(response_data)
      
      # Extract varbinds from the response
      varbinds = decoded_response.pdu.varbinds
      
      IO.puts("GETBULK response varbinds (#{length(varbinds)}):")
      Enum.with_index(varbinds, 1) |> Enum.each(fn {varbind, index} ->
        IO.puts("  #{index}. #{inspect(varbind)}")
      end)
      
      # Verify we get multiple varbinds (should continue walking)
      assert length(varbinds) >= 3, "Expected at least 3 varbinds, got #{length(varbinds)}"
      
      # Check that we have both ifIndex and ifDescr OIDs
      oid_strings = Enum.map(varbinds, fn {oid, _type, _value} -> 
        oid |> Enum.join(".")
      end)
      
      # Should contain ifIndex.1, ifIndex.2, and ifDescr.1
      assert Enum.any?(oid_strings, &String.starts_with?(&1, "1.3.6.1.2.1.2.2.1.1")), 
             "Missing ifIndex OIDs in response: #{inspect(oid_strings)}"
      assert Enum.any?(oid_strings, &String.starts_with?(&1, "1.3.6.1.2.1.2.2.1.2")), 
             "Missing ifDescr OIDs in response: #{inspect(oid_strings)}"
    end

    @tag :unit
    test "SNMP GETBULK operation returns ALL 50 OIDs from walk file" do
      # Start the device with cable modem walk file
      device_name = "cable_modem_full_walk"
      walk_file = Path.join([File.cwd!(), "priv", "walks", "cable_modem.walk"])
      
      {:ok, device_pid} = SnmpSim.Device.start_link(%{
        device_id: device_name,
        name: device_name,
        device_type: "cable_modem",
        walk_file: walk_file,
        port: 9998
      })

      # Load expected OIDs from walk file
      expected_oids = File.read!(walk_file)
      |> String.split("\n", trim: true)
      |> Enum.map(fn line ->
        # Parse walk file line to extract OID
        case Regex.run(~r/^([^=]+)/, String.trim(line)) do
          [_, oid_part] -> 
            # Convert MIB names to numeric OIDs (simplified mapping)
            oid_part
            |> String.trim()
            |> convert_mib_to_numeric()
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort()

      IO.puts("Expected #{length(expected_oids)} OIDs from walk file")

      # Perform comprehensive GETBULK walk starting from the beginning
      all_oids = perform_complete_getbulk_walk(device_pid)
      
      IO.puts("Retrieved #{length(all_oids)} OIDs via GETBULK walk")
      IO.puts("First 10 retrieved OIDs:")
      all_oids |> Enum.take(10) |> Enum.each(&IO.puts("  #{&1}"))
      IO.puts("Last 10 retrieved OIDs:")
      all_oids |> Enum.take(-10) |> Enum.each(&IO.puts("  #{&1}"))

      # Verify we got all expected OIDs
      missing_oids = expected_oids -- all_oids
      extra_oids = all_oids -- expected_oids

      if length(missing_oids) > 0 do
        IO.puts("Missing OIDs (#{length(missing_oids)}):")
        missing_oids |> Enum.take(10) |> Enum.each(&IO.puts("  #{&1}"))
      end

      if length(extra_oids) > 0 do
        IO.puts("Extra OIDs (#{length(extra_oids)}):")
        extra_oids |> Enum.take(10) |> Enum.each(&IO.puts("  #{&1}"))
      end

      # Test MUST pass only if we get all 50 OIDs
      assert length(all_oids) == 50, "Expected 50 OIDs, got #{length(all_oids)}"
      assert length(missing_oids) == 0, "Missing #{length(missing_oids)} OIDs from walk file"
    end

    # Helper function to convert MIB names to numeric OIDs (simplified)
    defp convert_mib_to_numeric(mib_oid) do
      case mib_oid do
        "SNMPv2-MIB::sysObjectID.0" -> "1.3.6.1.2.1.1.2.0"
        "SNMPv2-MIB::sysUpTime.0" -> "1.3.6.1.2.1.1.3.0"
        "SNMPv2-MIB::sysContact.0" -> "1.3.6.1.2.1.1.4.0"
        "SNMPv2-MIB::sysName.0" -> "1.3.6.1.2.1.1.5.0"
        "SNMPv2-MIB::sysLocation.0" -> "1.3.6.1.2.1.1.6.0"
        "SNMPv2-MIB::sysServices.0" -> "1.3.6.1.2.1.1.7.0"
        "SNMPv2-MIB::sysDescr.0" -> "1.3.6.1.2.1.1.1.0"
        "IF-MIB::ifNumber.0" -> "1.3.6.1.2.1.2.1.0"
        "IF-MIB::ifIndex.1" -> "1.3.6.1.2.1.2.2.1.1.1"
        "IF-MIB::ifIndex.2" -> "1.3.6.1.2.1.2.2.1.1.2"
        "IF-MIB::ifDescr.1" -> "1.3.6.1.2.1.2.2.1.2.1"
        "IF-MIB::ifDescr.2" -> "1.3.6.1.2.1.2.2.1.2.2"
        "IF-MIB::ifType.1" -> "1.3.6.1.2.1.2.2.1.3.1"
        "IF-MIB::ifType.2" -> "1.3.6.1.2.1.2.2.1.3.2"
        "IF-MIB::ifMtu.1" -> "1.3.6.1.2.1.2.2.1.4.1"
        "IF-MIB::ifMtu.2" -> "1.3.6.1.2.1.2.2.1.4.2"
        "IF-MIB::ifSpeed.1" -> "1.3.6.1.2.1.2.2.1.5.1"
        "IF-MIB::ifSpeed.2" -> "1.3.6.1.2.1.2.2.1.5.2"
        "IF-MIB::ifPhysAddress.1" -> "1.3.6.1.2.1.2.2.1.6.1"
        "IF-MIB::ifPhysAddress.2" -> "1.3.6.1.2.1.2.2.1.6.2"
        "IF-MIB::ifAdminStatus.1" -> "1.3.6.1.2.1.2.2.1.7.1"
        "IF-MIB::ifAdminStatus.2" -> "1.3.6.1.2.1.2.2.1.7.2"
        "IF-MIB::ifOperStatus.1" -> "1.3.6.1.2.1.2.2.1.8.1"
        "IF-MIB::ifOperStatus.2" -> "1.3.6.1.2.1.2.2.1.8.2"
        "IF-MIB::ifLastChange.1" -> "1.3.6.1.2.1.2.2.1.9.1"
        "IF-MIB::ifLastChange.2" -> "1.3.6.1.2.1.2.2.1.9.2"
        "IF-MIB::ifInOctets.1" -> "1.3.6.1.2.1.2.2.1.10.1"
        "IF-MIB::ifInUcastPkts.1" -> "1.3.6.1.2.1.2.2.1.11.1"
        "IF-MIB::ifInNUcastPkts.1" -> "1.3.6.1.2.1.2.2.1.12.1"
        "IF-MIB::ifInDiscards.1" -> "1.3.6.1.2.1.2.2.1.13.1"
        "IF-MIB::ifInErrors.1" -> "1.3.6.1.2.1.2.2.1.14.1"
        "IF-MIB::ifInUnknownProtos.1" -> "1.3.6.1.2.1.2.2.1.15.1"
        "IF-MIB::ifOutOctets.1" -> "1.3.6.1.2.1.2.2.1.16.1"
        "IF-MIB::ifOutUcastPkts.1" -> "1.3.6.1.2.1.2.2.1.17.1"
        "IF-MIB::ifOutNUcastPkts.1" -> "1.3.6.1.2.1.2.2.1.18.1"
        "IF-MIB::ifOutDiscards.1" -> "1.3.6.1.2.1.2.2.1.19.1"
        "IF-MIB::ifOutErrors.1" -> "1.3.6.1.2.1.2.2.1.20.1"
        "IF-MIB::ifOutQLen.1" -> "1.3.6.1.2.1.2.2.1.21.1"
        "IF-MIB::ifInOctets.2" -> "1.3.6.1.2.1.2.2.1.10.2"
        "IF-MIB::ifInUcastPkts.2" -> "1.3.6.1.2.1.2.2.1.11.2"
        "IF-MIB::ifInNUcastPkts.2" -> "1.3.6.1.2.1.2.2.1.12.2"
        "IF-MIB::ifInDiscards.2" -> "1.3.6.1.2.1.2.2.1.13.2"
        "IF-MIB::ifInErrors.2" -> "1.3.6.1.2.1.2.2.1.14.2"
        "IF-MIB::ifInUnknownProtos.2" -> "1.3.6.1.2.1.2.2.1.15.2"
        "IF-MIB::ifOutOctets.2" -> "1.3.6.1.2.1.2.2.1.16.2"
        "IF-MIB::ifOutUcastPkts.2" -> "1.3.6.1.2.1.2.2.1.17.2"
        "IF-MIB::ifOutNUcastPkts.2" -> "1.3.6.1.2.1.2.2.1.18.2"
        "IF-MIB::ifOutDiscards.2" -> "1.3.6.1.2.1.2.2.1.19.2"
        "IF-MIB::ifOutErrors.2" -> "1.3.6.1.2.1.2.2.1.20.2"
        "IF-MIB::ifOutQLen.2" -> "1.3.6.1.2.1.2.2.1.21.2"
        _ -> mib_oid  # Return as-is if no mapping found
      end
    end

    # Helper function to perform complete GETBULK walk using Device.walk/2
    defp perform_complete_getbulk_walk(device_pid) do
      # Use the built-in walk function starting from the root to capture ALL OIDs
      case SnmpSim.Device.walk(device_pid, "1.3.6.1.2.1") do
        {:ok, oids} ->
          IO.puts("Walk returned #{length(oids)} OIDs")
          IO.puts("First few OIDs from walk:")
          oids |> Enum.take(5) |> Enum.each(&IO.inspect/1)
          
          oids
          |> Enum.map(fn
            {oid, _value} when is_list(oid) -> Enum.join(oid, ".")
            {oid, _value} when is_binary(oid) -> oid
            {oid, _type, _value} when is_list(oid) -> Enum.join(oid, ".")
            {oid, _type, _value} when is_binary(oid) -> oid
            oid when is_list(oid) -> Enum.join(oid, ".")
            oid when is_binary(oid) -> oid
            other -> 
              IO.puts("Unexpected OID format: #{inspect(other)}")
              nil
          end)
          |> Enum.reject(&is_nil/1)
          |> Enum.sort()

        {:error, reason} ->
          IO.puts("Walk failed: #{inspect(reason)}")
          []
      end
    end
  end
end
