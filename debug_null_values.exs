#!/usr/bin/env elixir

# Debug script to identify why we're getting NULL values instead of proper SNMP data

IO.puts("=== Debugging NULL Values in SNMP Simulator ===")

# Start dependencies
Application.ensure_all_started(:snmp_sim)

# Sleep to allow proper startup
Process.sleep(200)

IO.puts("\n1. Testing SharedProfiles...")

# Test SharedProfiles directly
IO.puts("Loading cable_modem walk profile...")
result = SnmpSim.MIB.SharedProfiles.load_walk_profile(:cable_modem, "priv/walks/cable_modem.walk")
IO.puts("Load result: #{inspect(result)}")

IO.puts("\nTesting OID retrieval from SharedProfiles...")
test_result = SnmpSim.MIB.SharedProfiles.get_oid_value(:cable_modem, "1.3.6.1.2.1.1.1.0", %{device_id: "test"})
IO.puts("SharedProfiles get_oid_value result: #{inspect(test_result)}")

IO.puts("\n2. Testing Device module...")

# Create a test device
device_config = %{
  port: 19999,
  device_type: :cable_modem,
  device_id: "debug_device",
  community: "public"
}

IO.puts("Starting test device...")
{:ok, device_pid} = SnmpSim.Device.start_link(device_config)
Process.sleep(100)

IO.puts("Testing device OID retrieval...")
device_result = SnmpSim.Device.get(device_pid, "1.3.6.1.2.1.1.1.0")
IO.puts("Device.get result: #{inspect(device_result)}")

IO.puts("\n3. Testing SNMP PDU processing...")

# Create a test PDU using the struct definition from the module
test_pdu = %SnmpLib.PDU{
  version: 1,
  community: "public",
  pdu_type: 0xA0,  # GET_REQUEST
  request_id: 12345,
  error_status: 0,
  error_index: 0,
  variable_bindings: [{"1.3.6.1.2.1.1.1.0", nil}]
}

IO.puts("Testing PDU processing...")
pdu_result = GenServer.call(device_pid, {:handle_snmp, test_pdu, %{}})
IO.puts("PDU processing result: #{inspect(pdu_result)}")

IO.puts("\n4. Testing PDU encoding/decoding...")

case pdu_result do
  {:ok, response_pdu} ->
    IO.puts("Encoding response PDU...")
    case SnmpLib.PDU.encode(response_pdu) do
      {:ok, encoded} ->
        IO.puts("Encoded successfully, size: #{byte_size(encoded)} bytes")
        case SnmpLib.PDU.decode(encoded) do
          {:ok, decoded} ->
            IO.puts("Decoded successfully: #{inspect(decoded)}")
          {:error, reason} ->
            IO.puts("Decode failed: #{inspect(reason)}")
        end
      {:error, reason} ->
        IO.puts("Encode failed: #{inspect(reason)}")
    end
  _ ->
    IO.puts("Cannot test encoding - PDU processing failed")
end

# Cleanup
SnmpSim.Device.stop(device_pid)

IO.puts("\n=== Debug Complete ===")