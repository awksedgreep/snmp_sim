#!/usr/bin/env elixir

# Comprehensive test to understand the varbind encoding issue in SnmpLib
alias SnmpLib.PDU

IO.puts("\n=== SNMP Varbind Encoding Issue Investigation ===\n")

# Test 1: Basic GET Request encoding/decoding
IO.puts("Test 1: GET Request (should have null values)")
request_pdu = PDU.build_get_request([1, 3, 6, 1, 2, 1, 1, 1, 0], 12345)
request_message = PDU.build_message(request_pdu, "public", :v1)
IO.puts("Request PDU: #{inspect(request_pdu, pretty: true)}")
IO.puts("Request Message: #{inspect(request_message, pretty: true)}")

{:ok, encoded_request} = PDU.encode_message(request_message)
{:ok, decoded_request} = PDU.decode_message(encoded_request)
IO.puts("Decoded request varbinds: #{inspect(decoded_request.pdu.varbinds)}")

# Test 2: GET Response with actual values
IO.puts("\n\nTest 2: GET Response (should have actual values)")
response_pdu = %{
  type: :get_response,
  request_id: 12345,
  varbinds: [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :octet_string, "Test String"}],
  error_status: 0,
  error_index: 0
}
response_message_v1 = PDU.build_message(response_pdu, "public", :v1)
IO.puts("Response PDU: #{inspect(response_pdu, pretty: true)}")
IO.puts("Response Message v1: #{inspect(response_message_v1, pretty: true)}")

{:ok, encoded_response_v1} = PDU.encode_message(response_message_v1)
{:ok, decoded_response_v1} = PDU.decode_message(encoded_response_v1)
IO.puts("Decoded v1 response varbinds: #{inspect(decoded_response_v1.pdu.varbinds)}")

# Test 3: Same response with v2c
IO.puts("\n\nTest 3: Same GET Response with v2c")
response_message_v2c = PDU.build_message(response_pdu, "public", :v2c)
IO.puts("Response Message v2c: #{inspect(response_message_v2c, pretty: true)}")

{:ok, encoded_response_v2c} = PDU.encode_message(response_message_v2c)
{:ok, decoded_response_v2c} = PDU.decode_message(encoded_response_v2c)
IO.puts("Decoded v2c response varbinds: #{inspect(decoded_response_v2c.pdu.varbinds)}")

# Test 4: Different varbind types
IO.puts("\n\nTest 4: Testing different varbind types")
test_varbinds = [
  {[1, 3, 6, 1, 2, 1, 1, 1, 0], :octet_string, "String value"},
  {[1, 3, 6, 1, 2, 1, 1, 3, 0], :timeticks, 123456},
  {[1, 3, 6, 1, 2, 1, 1, 4, 0], :integer, 42},
  {[1, 3, 6, 1, 2, 1, 1, 5, 0], :counter32, 999},
  {[1, 3, 6, 1, 2, 1, 1, 6, 0], :object_identifier, [1, 3, 6, 1, 2, 1]},
  {[1, 3, 6, 1, 2, 1, 1, 7, 0], :gauge32, 500}
]

multi_response_pdu = %{
  type: :get_response,
  request_id: 12346,
  varbinds: test_varbinds,
  error_status: 0,
  error_index: 0
}

IO.puts("Testing v1 with multiple varbind types:")
multi_message_v1 = PDU.build_message(multi_response_pdu, "public", :v1)
{:ok, encoded_multi_v1} = PDU.encode_message(multi_message_v1)
{:ok, decoded_multi_v1} = PDU.decode_message(encoded_multi_v1)

Enum.zip(test_varbinds, decoded_multi_v1.pdu.varbinds)
|> Enum.each(fn {{orig_oid, orig_type, orig_value}, {dec_oid, dec_type, dec_value}} ->
  IO.puts("  Original: #{inspect({orig_oid, orig_type, orig_value})}")
  IO.puts("  Decoded:  #{inspect({dec_oid, dec_type, dec_value})}")
  IO.puts("")
end)

IO.puts("\nTesting v2c with multiple varbind types:")
multi_message_v2c = PDU.build_message(multi_response_pdu, "public", :v2c)
{:ok, encoded_multi_v2c} = PDU.encode_message(multi_message_v2c)
{:ok, decoded_multi_v2c} = PDU.decode_message(encoded_multi_v2c)

Enum.zip(test_varbinds, decoded_multi_v2c.pdu.varbinds)
|> Enum.each(fn {{orig_oid, orig_type, orig_value}, {dec_oid, dec_type, dec_value}} ->
  IO.puts("  Original: #{inspect({orig_oid, orig_type, orig_value})}")
  IO.puts("  Decoded:  #{inspect({dec_oid, dec_type, dec_value})}")
  IO.puts("")
end)

# Test 5: Check raw encoded bytes
IO.puts("\n\nTest 5: Examining raw encoded bytes")
simple_response = %{
  type: :get_response,
  request_id: 99999,
  varbinds: [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :octet_string, "Hello"}],
  error_status: 0,
  error_index: 0
}

v1_msg = PDU.build_message(simple_response, "public", :v1)
{:ok, v1_bytes} = PDU.encode_message(v1_msg)
IO.puts("v1 encoded bytes (first 50): #{inspect(binary_part(v1_bytes, 0, min(50, byte_size(v1_bytes))), base: :hex)}")
IO.puts("v1 total byte size: #{byte_size(v1_bytes)}")

v2c_msg = PDU.build_message(simple_response, "public", :v2c)
{:ok, v2c_bytes} = PDU.encode_message(v2c_msg)
IO.puts("v2c encoded bytes (first 50): #{inspect(binary_part(v2c_bytes, 0, min(50, byte_size(v2c_bytes))), base: :hex)}")
IO.puts("v2c total byte size: #{byte_size(v2c_bytes)}")

# Test 6: Try manually building a response structure
IO.puts("\n\nTest 6: Manually structured response")
manual_response = %{
  version: 0,
  community: "public",
  pdu: %{
    type: :get_response,
    request_id: 88888,
    error_status: 0,
    error_index: 0,
    varbinds: [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :octet_string, "Manual test"}]
  }
}

IO.puts("Manual response structure: #{inspect(manual_response, pretty: true)}")
{:ok, manual_encoded} = PDU.encode_message(manual_response)
{:ok, manual_decoded} = PDU.decode_message(manual_encoded)
IO.puts("Decoded manual response varbinds: #{inspect(manual_decoded.pdu.varbinds)}")
