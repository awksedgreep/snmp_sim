#!/usr/bin/env elixir

# Test varbind encoding/decoding
alias SnmpLib.PDU

# Create a response PDU with actual values
response_pdu = %{
  type: :get_response,
  version: 0,
  request_id: 12345,
  varbinds: [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :octet_string, "Test String"}],
  error_status: 0,
  error_index: 0
}

# Build and encode message
message = PDU.build_message(response_pdu, "public", :v1)
IO.puts("Message before encoding: #{inspect(message)}")

case PDU.encode_message(message) do
  {:ok, encoded} ->
    IO.puts("Successfully encoded")
    
    # Now decode it back
    case PDU.decode_message(encoded) do
      {:ok, decoded} ->
        IO.puts("Decoded message: #{inspect(decoded)}")
        IO.puts("Decoded varbinds: #{inspect(decoded.pdu.varbinds)}")
      {:error, reason} ->
        IO.puts("Decode error: #{inspect(reason)}")
    end
    
  {:error, reason} ->
    IO.puts("Encode error: #{inspect(reason)}")
end
