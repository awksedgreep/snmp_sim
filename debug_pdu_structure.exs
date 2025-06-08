#!/usr/bin/env elixir

# Check if the issue is related to PDU structure
alias SnmpLib.PDU

IO.puts("\n=== Investigating PDU Structure Requirements ===\n")

# Test different ways of structuring the response
test_cases = [
  # Case 1: Basic structure
  %{
    type: :get_response,
    request_id: 12345,
    varbinds: [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :octet_string, "Test1"}],
    error_status: 0,
    error_index: 0
  },
  
  # Case 2: With version in PDU
  %{
    type: :get_response,
    version: 0,
    request_id: 12345,
    varbinds: [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :octet_string, "Test2"}],
    error_status: 0,
    error_index: 0
  },
  
  # Case 3: With community in PDU
  %{
    type: :get_response,
    community: "public",
    request_id: 12345,
    varbinds: [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :octet_string, "Test3"}],
    error_status: 0,
    error_index: 0
  },
  
  # Case 4: Different varbind structure - just OID and value
  %{
    type: :get_response,
    request_id: 12345,
    varbinds: [{[1, 3, 6, 1, 2, 1, 1, 1, 0], "Test4"}],
    error_status: 0,
    error_index: 0
  }
]

Enum.with_index(test_cases, 1)
|> Enum.each(fn {pdu, idx} ->
  IO.puts("Test Case #{idx}: #{inspect(Map.keys(pdu))}")
  
  try do
    message = PDU.build_message(pdu, "public", :v1)
    case PDU.encode_message(message) do
      {:ok, encoded} ->
        case PDU.decode_message(encoded) do
          {:ok, decoded} ->
            [{_oid, _type, value}] = decoded.pdu.varbinds
            IO.puts("  Result: value = #{inspect(value)}")
          {:error, reason} ->
            IO.puts("  Decode error: #{inspect(reason)}")
        end
      {:error, reason} ->
        IO.puts("  Encode error: #{inspect(reason)}")
    end
  rescue
    e ->
      IO.puts("  Exception: #{inspect(e)}")
  end
  IO.puts("")
end)

# Let's also check what a GET request looks like after decoding
IO.puts("\nChecking GET request structure:")
get_pdu = PDU.build_get_request([1, 3, 6, 1, 2, 1, 1, 1, 0], 99999)
get_msg = PDU.build_message(get_pdu, "public", :v1)
{:ok, get_encoded} = PDU.encode_message(get_msg)
{:ok, get_decoded} = PDU.decode_message(get_encoded)
IO.puts("GET request decoded varbinds: #{inspect(get_decoded.pdu.varbinds)}")

# Check if we can access the encoder/decoder directly
IO.puts("\nChecking for direct ASN.1 encoding functions...")
if function_exported?(SnmpLib.ASN1, :encode, 1) do
  IO.puts("ASN1.encode/1 exists")
end
if function_exported?(SnmpLib.ASN1, :decode, 1) do
  IO.puts("ASN1.decode/1 exists")
end

# Try to understand the varbind encoding
IO.puts("\nAnalyzing varbind structure in encoded data...")
simple_pdu = %{
  type: :get_response,
  request_id: 12345,
  varbinds: [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :octet_string, "ABC"}],
  error_status: 0,
  error_index: 0
}
simple_msg = PDU.build_message(simple_pdu, "public", :v1)
{:ok, simple_encoded} = PDU.encode_message(simple_msg)

# Show the hex dump
IO.puts("Encoded message with 'ABC' string:")
for <<byte <- simple_encoded>>, do: :io.format("~2.16.0B ", [byte])
IO.puts("\n")

# Try with an empty string
empty_pdu = %{
  type: :get_response,
  request_id: 12345,
  varbinds: [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :octet_string, ""}],
  error_status: 0,
  error_index: 0
}
empty_msg = PDU.build_message(empty_pdu, "public", :v1)
{:ok, empty_encoded} = PDU.encode_message(empty_msg)

IO.puts("Encoded message with empty string:")
for <<byte <- empty_encoded>>, do: :io.format("~2.16.0B ", [byte])
IO.puts("\n")
