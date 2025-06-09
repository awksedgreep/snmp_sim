defmodule SnmpSim.SNMPOperationsTest do
  @moduledoc """
  Tests for SNMP operation types (GET, GETNEXT, GETBULK) to ensure
  they work correctly and return proper SNMP data types.

  This test suite specifically targets the SNMP walk functionality
  and device response handling that was causing "Wrong Type: NULL" issues.
  """

  use ExUnit.Case, async: false

  alias SnmpSim.Core.Server
  alias SnmpSim.Device
  alias SnmpSim.TestHelpers.PortHelper

  @test_community "public"

  describe "Device SNMP operations" do
    setup do
      test_port = PortHelper.get_port()

      device_config = %{
        port: test_port,
        device_type: :cable_modem,
        device_id: "snmp_test_device",
        community: @test_community
      }

      {:ok, device_pid} = Device.start_link(device_config)

      on_exit(fn ->
        if Process.alive?(device_pid) do
          Device.stop(device_pid)
        end
      end)

      # Wait for device initialization
      Process.sleep(100)

      %{device: device_pid}
    end

    test "GET operation returns proper SNMP data types", %{device: device} do
      test_cases = [
        {"1.3.6.1.2.1.1.1.0", &is_binary/1, "sysDescr should be string"},
        {"1.3.6.1.2.1.1.2.0", &is_list/1, "sysObjectID should be OID list"},
        {"1.3.6.1.2.1.1.3.0", &is_integer/1, "sysUpTime should be integer"}
      ]

      for {oid, validator, description} <- test_cases do
        {:ok, {^oid, type, value}} = Device.get(device, oid)
        # Handle the case where value might be a typed tuple
        actual_value = case value do
          {_type, actual_val} -> actual_val
          actual_val -> actual_val
        end
        assert validator.(actual_value), "#{description}, got: #{inspect({type, actual_value})}"
      end
    end

    test "GETNEXT operations return proper next OID and value", %{device: device} do
      getnext_tests = [
        {"1.3.6.1.2.1.1", "1.3.6.1.2.1.1.1.0"},
        {"1.3.6.1.2.1.1.1.0", "1.3.6.1.2.1.1.2.0"},
        {"1.3.6.1.2.1.1.2.0", "1.3.6.1.2.1.1.3.0"}
      ]

      for {current_oid, expected_next_oid} <- getnext_tests do
        {:ok, {next_oid, _type, value}} = Device.get_next(device, current_oid)
        assert next_oid == expected_next_oid, "GETNEXT for #{current_oid} should return #{expected_next_oid}, got: #{next_oid}"
        assert value != nil, "GETNEXT value for #{current_oid} should not be nil"
      end
    end

    test "interface table OIDs return proper SNMP types", %{device: device} do
      interface_oids = [
        {"1.3.6.1.2.1.2.2.1.1.1", :integer},
        {"1.3.6.1.2.1.2.2.1.2.1", :octet_string},
        {"1.3.6.1.2.1.2.2.1.3.1", :integer}
      ]

      for {oid, expected_type} <- interface_oids do
        {:ok, {^oid, type, value}} = Device.get(device, oid)
        assert type == expected_type, "#{oid} should return #{expected_type}, got: #{inspect(type)}"
        assert value != nil, "#{oid} should have a non-nil value"
      end
    end

    test "simulated SNMP walk returns sequential OIDs with proper types", %{device: device} do
      # Perform a walk from sysDescr (1.3.6.1.2.1.1.1.0)
      {:ok, walk_results} = Device.walk(device, [1, 3, 6, 1, 2, 1, 1, 1, 0])
      assert length(walk_results) > 0, "Walk should return at least one result"

      # Check if results are in numerical order
      oids = Enum.map(walk_results, fn {oid, _value} -> oid end)
      IO.inspect(oids, label: "Walk OIDs returned")
      # Sort OIDs numerically by converting to integer lists
      sorted_oids = Enum.sort_by(oids, fn oid_string ->
        oid_string
        |> String.split(".")
        |> Enum.map(&String.to_integer/1)
      end)
      IO.inspect(sorted_oids, label: "Walk OIDs sorted")
      assert oids == sorted_oids, "OIDs should be in numerical order"

      # Check values and types for specific OIDs
      for {oid, value} <- walk_results do
        case oid do
          "1.3.6.1.2.1.1.1.0" ->
            assert is_binary(value), "sysDescr should return a string"

          "1.3.6.1.2.1.1.2.0" ->
            assert is_list(value), "sysObjectID should return an OID"

          "1.3.6.1.2.1.1.7.0" ->
            assert is_integer(value), "sysServices should return an integer"

          _ ->
            # For other OIDs, just ensure we have a value
            assert value != nil, "OID #{oid} should have a value"
        end
      end
    end

    test "non-existent OIDs return proper SNMP error types", %{device: device} do
      non_existent_oids = [
        "1.3.6.1.99.99.99.0",
        "1.3.6.1.2.1.1.99.0",
        "9.9.9.9.9.0"
      ]

      for oid <- non_existent_oids do
        case Device.get(device, oid) do
          {:error, :no_such_name} ->
            # This is correct
            :ok

          {:ok, {:no_such_object, nil}} ->
            # This is also correct for SNMPv2
            :ok

          {:ok, value} ->
            flunk("Non-existent OID #{oid} should return error, got: #{inspect(value)}")

          {:error, other} ->
            # Other error types are acceptable
            :ok
        end
      end
    end
  end

  describe "End-to-end SNMP PDU processing" do
    setup do
      test_port = PortHelper.get_port()

      device_config = %{
        port: test_port,
        device_type: :router,
        device_id: "pdu_test_device",
        community: @test_community
      }

      {:ok, device_pid} = Device.start_link(device_config)

      on_exit(fn ->
        if Process.alive?(device_pid) do
          Device.stop(device_pid)
        end
      end)

      Process.sleep(100)

      %{device: device_pid}
    end

    test "GET request PDU processing returns proper response", %{device: device} do
      # Create a GET request PDU
      request_pdu = %{
        version: 1,
        community: @test_community,
        type: :get_request,
        request_id: 12345,
        error_status: 0,
        error_index: 0,
        varbinds: [
          # sysDescr
          {"1.3.6.1.2.1.1.1.0", nil, nil},
          # sysUpTime
          {"1.3.6.1.2.1.1.3.0", nil, nil}
        ]
      }

      # Process the PDU through the device
      case GenServer.call(device, {:handle_snmp, request_pdu, %{}}) do
        {:ok, {:ok, response_pdu}} ->
          # Verify response structure
          assert response_pdu.version == request_pdu.version
          assert response_pdu.community == request_pdu.community
          assert response_pdu.type == :get_response
          assert response_pdu.request_id == request_pdu.request_id
          assert response_pdu.error_status == 0
          assert response_pdu.error_index == 0

          # Verify we got responses for both OIDs
          assert length(response_pdu.varbinds) == 2

          # Check the actual values returned
          [{oid1, _type1, value1}, {oid2, _type2, value2}] = response_pdu.varbinds

          # Convert OID lists to strings for comparison
          oid1_string = if is_list(oid1), do: Enum.join(oid1, "."), else: oid1
          oid2_string = if is_list(oid2), do: Enum.join(oid2, "."), else: oid2

          assert oid1_string == "1.3.6.1.2.1.1.1.0"
          assert oid2_string == "1.3.6.1.2.1.1.3.0"

          # Verify data types - sysDescr should be string, sysUpTime should be integer
          assert is_binary(value1), "sysDescr should be string, got: #{inspect(value1)}"
          assert is_integer(value2), "sysUpTime should be integer, got: #{inspect(value2)}"

          # Verify the response can be encoded (this was the original problem)
          test_message = SnmpLib.PDU.build_message(response_pdu, "public", :v1)
          {:ok, encoded_response} = SnmpLib.PDU.encode_message(test_message)
          assert is_binary(encoded_response), "Response PDU should encode to binary"

          # Verify the encoded response can be decoded back
          {:ok, decoded_response} = SnmpLib.PDU.decode_message(encoded_response)
          # v1 is encoded as 0
          assert decoded_response.version == 0
          assert decoded_response.community == "public"

        {:error, error_response} ->
          flunk("Device returned error: #{inspect(error_response)}")
      end
    end

    test "GETNEXT request PDU processing works correctly", %{device: device} do
      # Create a GETNEXT request PDU
      request_pdu = %{
        version: 1,
        community: @test_community,
        type: :get_next_request,
        request_id: 12346,
        error_status: 0,
        error_index: 0,
        varbinds: [
          # Start of system group
          {"1.3.6.1.2.1.1", nil, nil}
        ]
      }

      # Process the PDU
      response = GenServer.call(device, {:handle_snmp, request_pdu, %{}})
      case response do
        {:ok, {:ok, response_pdu}} ->
          assert response_pdu.type == :get_response
          assert response_pdu.request_id == request_pdu.request_id
          assert response_pdu.error_status == 0

          [{next_oid, _type, next_value}] = response_pdu.varbinds

          # Convert OID list to string for comparison
          next_oid_string = if is_list(next_oid), do: Enum.join(next_oid, "."), else: next_oid

          # Should get the first OID in the system subtree
          assert String.starts_with?(next_oid_string, "1.3.6.1.2.1.1"),
                 "GETNEXT should return OID in system subtree, got: #{next_oid_string}"

          assert is_valid_snmp_type(next_value),
                 "GETNEXT value should be valid SNMP type, got: #{inspect(next_value)}"

        {:ok, {:error, reason}} ->
          flunk("GETNEXT PDU processing failed: #{inspect(reason)}")
        {:error, reason} ->
          flunk("GETNEXT PDU processing failed: #{inspect(reason)}")
        other ->
          flunk("Unexpected response format: #{inspect(other)}")
      end
    end
  end

  # Helper functions

  defp simulate_snmp_walk(device, start_oid) do
    simulate_walk_recursive(device, start_oid, [], 10)
  end

  defp simulate_walk_recursive(_device, _oid, results, 0) do
    # Prevent infinite loops
    results
  end

  defp simulate_walk_recursive(device, current_oid, results, iterations_left) do
    case simulate_getnext(device, current_oid) do
      {:ok, {next_oid, value}} ->
        if String.starts_with?(next_oid, "1.3.6.1.2.1.1") do
          # Still in system subtree, continue
          new_results = results ++ [{next_oid, value}]
          simulate_walk_recursive(device, next_oid, new_results, iterations_left - 1)
        else
          # Left system subtree, stop
          results
        end

      {:error, _} ->
        results
    end
  end

  defp simulate_getnext(device, oid) do
    # This simulates GETNEXT by using the device's fallback functions
    # In a real implementation, this would use the actual GETNEXT PDU processing

    # Try to get the current OID to see if it exists
    case Device.get(device, oid) do
      {:ok, _} ->
        # OID exists, get next
        get_next_system_oid(device, oid)

      {:error, _} ->
        # OID doesn't exist, get first valid OID after this one
        get_next_system_oid(device, oid)
    end
  end

  defp get_next_system_oid(device, oid) do
    # Simple mapping for common system OID transitions
    next_oid =
      case oid do
        "1.3.6.1.2.1.1" -> "1.3.6.1.2.1.1.1.0"
        "1.3.6.1.2.1.1.1.0" -> "1.3.6.1.2.1.1.2.0"
        "1.3.6.1.2.1.1.2.0" -> "1.3.6.1.2.1.1.3.0"
        "1.3.6.1.2.1.1.3.0" -> "1.3.6.1.2.1.1.4.0"
        "1.3.6.1.2.1.1.4.0" -> "1.3.6.1.2.1.1.5.0"
        "1.3.6.1.2.1.1.5.0" -> "1.3.6.1.2.1.1.6.0"
        "1.3.6.1.2.1.1.6.0" -> "1.3.6.1.2.1.1.7.0"
        "1.3.6.1.2.1.1.7.0" -> "1.3.6.1.2.1.2.1.0"
        _ -> nil
      end

    if next_oid do
      case Device.get(device, next_oid) do
        {:ok, value} -> {:ok, {next_oid, value}}
        error -> error
      end
    else
      {:error, :end_of_mib}
    end
  end

  defp is_valid_snmp_type(value) do
    case value do
      # Basic SNMP types
      s when is_binary(s) -> true
      i when is_integer(i) -> true
      # SNMP-specific types  
      {:counter32, v} when is_integer(v) -> true
      {:gauge32, v} when is_integer(v) -> true
      {:timeticks, v} when is_integer(v) -> true
      {:object_identifier, v} when is_binary(v) -> true
      {:counter64, v} when is_integer(v) -> true
      # Exception types
      {:no_such_object, nil} -> true
      {:no_such_instance, nil} -> true
      {:end_of_mib_view, nil} -> true
      # Invalid types that would cause "Wrong Type: NULL" errors
      nil -> false
      {:null, nil} -> false
      _ -> false
    end
  end
end
