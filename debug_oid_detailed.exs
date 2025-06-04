#!/usr/bin/env elixir

Mix.install([
  {:snmp_lib, path: "../snmp_lib"}
])

IO.puts("=== Detailed Object Identifier Debug ===")

# Test various ways of representing object identifiers
test_oid_string = "1.3.6.1.2.1.1.1.0"
test_oid_list = [1, 3, 6, 1, 2, 1, 1, 1, 0]

# Test cases with different value formats
test_cases = [
  %{
    name: "GET request with null value",
    message_func: fn -> 
      pdu = SnmpLib.PDU.build_get_request(test_oid_list, 12345)
      SnmpLib.PDU.build_message(pdu, "public", :v2c)
    end
  },
  %{
    name: "Response with object identifier value",
    message_func: fn ->
      # Build a response PDU with an object identifier value
      varbinds = [{test_oid_list, :object_identifier, test_oid_list}]
      pdu = SnmpLib.PDU.build_response(12345, 0, 0, varbinds)
      SnmpLib.PDU.build_message(pdu, "public", :v2c)
    end
  },
  %{
    name: "Response with object identifier tuple",
    message_func: fn ->
      # Try with the tuple format
      oid_tuple = {:object_identifier, test_oid_string}
      varbinds = [{test_oid_list, :object_identifier, oid_tuple}]
      pdu = SnmpLib.PDU.build_response(12346, 0, 0, varbinds)
      SnmpLib.PDU.build_message(pdu, "public", :v2c)
    end
  },
  %{
    name: "Response with string value",
    message_func: fn ->
      # Try with a simple string value
      varbinds = [{test_oid_list, :string, "test-value"}]
      pdu = SnmpLib.PDU.build_response(12347, 0, 0, varbinds)
      SnmpLib.PDU.build_message(pdu, "public", :v2c)
    end
  },
  %{
    name: "Response with integer value",
    message_func: fn ->
      varbinds = [{test_oid_list, :integer, 42}]
      pdu = SnmpLib.PDU.build_response(12348, 0, 0, varbinds)
      SnmpLib.PDU.build_message(pdu, "public", :v2c)
    end
  }
]

for %{name: case_name, message_func: func} <- test_cases do
  IO.puts("\n#{String.duplicate("=", 80)}")
  IO.puts("Testing: #{case_name}")
  IO.puts(String.duplicate("=", 80))
  
  # Build the message
  message = func.()
  IO.puts("Original message: #{inspect(message)}")
  
  # Encode the message
  case SnmpLib.PDU.encode_message(message) do
    {:ok, encoded} ->
      IO.puts("✓ Encoding successful, size: #{byte_size(encoded)} bytes")
      IO.puts("  Encoded (hex): #{Base.encode16(encoded)}")
      
      # Decode the message
      case SnmpLib.PDU.decode_message(encoded) do
        {:ok, decoded} ->
          IO.puts("✓ Decoding successful")
          IO.puts("Decoded message: #{inspect(decoded)}")
          
          # Compare varbinds
          original_vb = hd(message.pdu.varbinds)
          decoded_vb = hd(decoded.pdu.varbinds)
          
          IO.puts("\nVariable binding comparison:")
          IO.puts("  Original: #{inspect(original_vb)}")
          IO.puts("  Decoded:  #{inspect(decoded_vb)}")
          
          if original_vb == decoded_vb do
            IO.puts("  ✓ Variable bindings match exactly")
          else
            IO.puts("  ⚠ Variable bindings differ")
            
            # Analyze the differences
            {orig_oid, orig_type, orig_value} = original_vb
            {dec_oid, dec_type, dec_value} = decoded_vb
            
            IO.puts("    OID match: #{orig_oid == dec_oid}")
            IO.puts("    Type match: #{orig_type == dec_type}")
            IO.puts("    Value match: #{orig_value == dec_value}")
            
            if orig_type != dec_type do
              IO.puts("    Type changed: #{orig_type} → #{dec_type}")
            end
            
            if orig_value != dec_value do
              IO.puts("    Value changed: #{inspect(orig_value)} → #{inspect(dec_value)}")
            end
          end
          
        {:error, decode_error} ->
          IO.puts("✗ Decoding failed: #{inspect(decode_error)}")
      end
      
    {:error, encode_error} ->
      IO.puts("✗ Encoding failed: #{inspect(encode_error)}")
  end
end

IO.puts("\n#{String.duplicate("=", 80)}")
IO.puts("Testing object identifier with specific value formats")
IO.puts(String.duplicate("=", 80))

# Test specific object identifier cases that might be causing issues
test_cases_specific = [
  %{
    name: "Response with OID value as list",
    varbinds: [{test_oid_list, :object_identifier, test_oid_list}]
  },
  %{
    name: "Response with OID value as string", 
    varbinds: [{test_oid_list, :object_identifier, test_oid_string}]
  },
  %{
    name: "Response with OID tuple value",
    varbinds: [{test_oid_list, :object_identifier, {:object_identifier, test_oid_string}}]
  },
  %{
    name: "Mixed varbinds with different OID formats",
    varbinds: [
      {test_oid_list, :object_identifier, test_oid_list},
      {test_oid_list, :null, :null},
      {test_oid_list, :string, "test"}
    ]
  }
]

for %{name: case_name, varbinds: varbinds} <- test_cases_specific do
  IO.puts("\n--- #{case_name} ---")
  
  pdu = SnmpLib.PDU.build_response(88888, 0, 0, varbinds)
  message = SnmpLib.PDU.build_message(pdu, "public", :v2c)
  
  IO.puts("Original varbinds: #{inspect(varbinds)}")
  
  case SnmpLib.PDU.encode_message(message) do
    {:ok, encoded} ->
      case SnmpLib.PDU.decode_message(encoded) do
        {:ok, decoded} ->
          decoded_varbinds = decoded.pdu.varbinds
          IO.puts("Decoded varbinds:  #{inspect(decoded_varbinds)}")
          
          # Check each varbind
          for {i, {orig_vb, dec_vb}} <- Enum.with_index(Enum.zip(varbinds, decoded_varbinds)) do
            if orig_vb == dec_vb do
              IO.puts("  VB #{i + 1}: ✓ Match")
            else
              IO.puts("  VB #{i + 1}: ✗ Differ")
              IO.puts("    Original: #{inspect(orig_vb)}")
              IO.puts("    Decoded:  #{inspect(dec_vb)}")
            end
          end
        {:error, reason} ->
          IO.puts("✗ Decoding failed: #{inspect(reason)}")
      end
    {:error, reason} ->
      IO.puts("✗ Encoding failed: #{inspect(reason)}")
  end
end

IO.puts("\n=== Object Identifier Debug Complete ===")