defmodule SnmpSim.GetbulkFunctionalityTest do
  use ExUnit.Case, async: true
  alias SnmpSim.Device

  # Test the GETBULK processing logic directly without starting UDP servers
  defp create_test_state() do
    %{
      device_type: :cable_modem,
      device_id: "test_device",
      port: 20001,
      last_access: System.monotonic_time(:millisecond),
      counters: %{},
      gauges: %{},
      status_vars: %{},
      community: "public",
      error_conditions: %{}
    }
  end

  # Access the private process_snmp_pdu function for testing
  defp call_process_snmp_pdu(pdu, _state) do
    # Use :sys.get_state to call private functions (test hack)
    # Since we can't call private functions directly, we'll test via the public interface
    # by creating a minimal device process
    {:ok, device_pid} =
      GenServer.start_link(Device, %{
        device_type: :cable_modem,
        device_id: "test_#{:rand.uniform(10000)}",
        port: 20000 + :rand.uniform(1000)
      })

    # Call the device with our test PDU
    result = GenServer.call(device_pid, {:handle_snmp, pdu, %{}})
    GenServer.stop(device_pid)
    result
  end

  describe "GETBULK functionality" do
    test "handles basic GETBULK request starting from internet root" do
      # This is the exact request that snmpbulkwalk sends
      pdu = %{
        type: :get_bulk_request,
        # SNMPv2c
        version: 1,
        community: "public",
        request_id: 12345,
        non_repeaters: 0,
        max_repetitions: 10,
        varbinds: [{"1.3.6.1", nil}]
      }

      # Process the GETBULK request
      {:ok, response_pdu} = call_process_snmp_pdu(pdu, create_test_state())

      # Verify response structure
      assert response_pdu.type == :get_response
      assert response_pdu.error_status == 0
      assert response_pdu.error_index == 0
      assert is_list(response_pdu.varbinds)
      assert length(response_pdu.varbinds) > 0

      # Verify OID progression - each OID should be greater than the previous
      oids =
        Enum.map(response_pdu.varbinds, fn {oid, _type, _value} ->
          if is_list(oid), do: Enum.join(oid, "."), else: oid
        end)

      # Check that OIDs are progressing (not returning the same OID)
      first_oid = hd(oids)
      refute first_oid == "1.3.6.1", "GETBULK should not return the same OID it was queried for"

      # First OID should be greater than the query OID
      assert String.starts_with?(first_oid, "1.3.6.1."),
             "First OID should be under the queried subtree"
    end

    test "GETBULK OID progression validation - the critical test" do
      # Test the specific case that's failing with snmpbulkwalk
      pdu = %{
        type: :get_bulk_request,
        version: 1,
        community: "public",
        request_id: 12350,
        non_repeaters: 0,
        max_repetitions: 1,
        varbinds: [{"1.3.6.1", nil}]
      }

      {:ok, response_pdu} = call_process_snmp_pdu(pdu, create_test_state())

      assert length(response_pdu.varbinds) >= 1
      {first_oid, _type, _value} = hd(response_pdu.varbinds)

      first_oid_str = if is_list(first_oid), do: Enum.join(first_oid, "."), else: first_oid

      # The critical test: returned OID must be greater than query OID
      query_oid = "1.3.6.1"

      assert first_oid_str > query_oid,
             "Returned OID '#{first_oid_str}' must be greater than query OID '#{query_oid}' to avoid 'OID not increasing' error"

      # More specifically, it should start with the query OID but be longer
      assert String.starts_with?(first_oid_str, query_oid <> "."),
             "Returned OID should be under the queried subtree: '#{first_oid_str}' should start with '#{query_oid}.'"
    end

    test "GETBULK returns consistent varbind format" do
      pdu = %{
        type: :get_bulk_request,
        version: 1,
        community: "public",
        request_id: 12349,
        non_repeaters: 0,
        max_repetitions: 3,
        varbinds: [{"1.3.6.1.2.1.1", nil}]
      }

      {:ok, response_pdu} = call_process_snmp_pdu(pdu, create_test_state())

      # All varbinds should be 3-tuples {oid, type, value}
      Enum.each(response_pdu.varbinds, fn varbind ->
        assert tuple_size(varbind) == 3, "Varbind should be 3-tuple: #{inspect(varbind)}"
        {oid, type, _value} = varbind
        assert is_binary(oid) or is_list(oid), "OID should be string or list: #{inspect(oid)}"
        assert is_atom(type), "Type should be atom: #{inspect(type)}"
        # Value can be anything
      end)
    end

    test "GETBULK error status should be 0 not 5" do
      # Isolate the error status issue
      pdu = %{
        type: :get_bulk_request,
        version: 1,
        community: "public",
        request_id: 99999,
        non_repeaters: 0,
        max_repetitions: 1,
        varbinds: [{"1.3.6.1", nil}]
      }

      {:ok, response_pdu} = call_process_snmp_pdu(pdu, create_test_state())

      # This should pass after fix - currently fails with error_status: 5
      assert response_pdu.error_status == 0,
             "GETBULK should return error_status 0, got #{response_pdu.error_status}"

      assert response_pdu.error_index == 0
    end

    test "GETBULK should not return same OID as query" do
      # Isolate the OID progression issue
      pdu = %{
        type: :get_bulk_request,
        version: 1,
        community: "public",
        request_id: 88888,
        non_repeaters: 0,
        max_repetitions: 1,
        varbinds: [{"1.3.6.1", nil}]
      }

      {:ok, response_pdu} = call_process_snmp_pdu(pdu, create_test_state())

      # Extract first varbind - handle both 2-tuple and 3-tuple formats for now
      first_varbind = hd(response_pdu.varbinds)

      first_oid =
        case first_varbind do
          {oid, _type, _value} -> oid
          {oid, _value} -> oid
          _ -> nil
        end

      first_oid_str = if is_list(first_oid), do: Enum.join(first_oid, "."), else: first_oid

      # The core issue: should NOT return the same OID
      refute first_oid_str == "1.3.6.1",
             "GETBULK returned same OID '#{first_oid_str}' as query '1.3.6.1' - this causes 'OID not increasing' error"
    end

    test "GETBULK fallback function format consistency" do
      # Test that fallback functions return expected format
      # This test will help us understand what the fallback is actually returning
      pdu = %{
        type: :get_bulk_request,
        version: 1,
        community: "public",
        request_id: 77777,
        non_repeaters: 0,
        max_repetitions: 1,
        varbinds: [{"1.3.6.1", nil}]
      }

      {:ok, response_pdu} = call_process_snmp_pdu(pdu, create_test_state())

      # Debug: print what we actually get
      IO.inspect(response_pdu.varbinds, label: "GETBULK varbinds")
      IO.inspect(response_pdu.error_status, label: "GETBULK error_status")

      # This test is for debugging - we expect it to fail initially
      assert length(response_pdu.varbinds) > 0, "Should have at least one varbind"
    end
  end
end
