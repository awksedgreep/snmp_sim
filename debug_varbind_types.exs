#!/usr/bin/env elixir

# Debug script to test varbind type encoding/decoding
Mix.install([{:snmp_lib, "~> 1.0"}])

# Test varbind with object_identifier type
test_varbind = {[1, 3, 6, 1, 2, 1, 1, 2, 0], :object_identifier, "SNMPv2-SMI::enterprises.4491.2.4.1"}

# Create a simple PDU with this varbind
pdu = %{
  type: :get_response,
  version: 2,
  request_id: 12345,
  varbinds: [test_varbind],
  community: "public",
  error_status: 0,
  error_index: 0
}

IO.puts("Original PDU:")
IO.inspect(pdu, pretty: true)

# Build message
message = SnmpLib.PDU.build_message(pdu, "public", :v2c)
IO.puts("\nBuilt message:")
IO.inspect(message, pretty: true)

# Encode and decode
case SnmpLib.PDU.encode_message(message) do
  {:ok, encoded} ->
    IO.puts("\nEncoded successfully, size: #{byte_size(encoded)} bytes")
    
    case SnmpLib.PDU.decode_message(encoded) do
      {:ok, decoded} ->
        IO.puts("\nDecoded message:")
        IO.inspect(decoded, pretty: true)
        
        IO.puts("\nDecoded varbinds:")
        Enum.each(decoded.pdu.varbinds, fn {oid, type, value} ->
          IO.puts("  OID: #{inspect(oid)}, Type: #{inspect(type)}, Value: #{inspect(value)}")
        end)
        
      {:error, reason} ->
        IO.puts("\nDecode failed: #{inspect(reason)}")
    end
    
  {:error, reason} ->
    IO.puts("\nEncode failed: #{inspect(reason)}")
end
