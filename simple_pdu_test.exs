#!/usr/bin/env elixir

Mix.install([
  {:snmp_lib, path: "../snmp_lib"}
])

IO.puts("=== Simple PDU Test ===")

IO.puts("Testing SnmpLib.PDU module...")
IO.inspect(SnmpLib.PDU.__info__(:functions))

# Test building a GET request
oid_list = [1, 3, 6, 1, 2, 1, 1, 1, 0]
pdu = SnmpLib.PDU.build_get_request(oid_list, 12345)
IO.puts("Built PDU: #{inspect(pdu)}")

# Test building a message
message = SnmpLib.PDU.build_message(pdu, "public", :v2c)
IO.puts("Built message: #{inspect(message)}")

# Test encoding
case SnmpLib.PDU.encode_message(message) do
  {:ok, encoded} ->
    IO.puts("✓ Encoding successful, size: #{byte_size(encoded)}")
    
    # Test decoding
    case SnmpLib.PDU.decode_message(encoded) do
      {:ok, decoded} ->
        IO.puts("✓ Decoding successful")
        IO.puts("Decoded message: #{inspect(decoded)}")
      {:error, reason} ->
        IO.puts("✗ Decoding failed: #{inspect(reason)}")
    end
  {:error, reason} ->
    IO.puts("✗ Encoding failed: #{inspect(reason)}")
end