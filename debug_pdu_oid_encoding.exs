#!/usr/bin/env elixir

# Debug script to investigate why object identifiers are becoming :null during PDU encoding/decoding

Mix.install([
  {:snmp_lib, path: "../snmp_lib"},
  {:jason, "~> 1.4"}
])

IO.puts("=== Debugging Object Identifier PDU Encoding/Decoding ===")

# Sleep to allow proper startup
Process.sleep(200)

IO.puts("\n1. Testing basic OID handling...")

# Test OID with object identifier tuple format
test_oid = "1.3.6.1.2.1.1.1.0"
test_oid_list = [1, 3, 6, 1, 2, 1, 1, 1, 0]
test_oid_tuple = {:object_identifier, test_oid}

IO.puts("Original OID string: #{test_oid}")
IO.puts("Original OID list: #{inspect(test_oid_list)}")
IO.puts("Original OID tuple: #{inspect(test_oid_tuple)}")

IO.puts("\n2. Creating PDU with different OID formats...")

# Test with different ways of specifying the OID and value
test_cases = [
  %{
    name: "OID as string, value as :null",
    pdu: %SnmpLib.PDU{
      version: 1,
      community: "public",
      pdu_type: 0xA0,  # GET_REQUEST
      request_id: 12345,
      error_status: 0,
      error_index: 0,
      variable_bindings: [{test_oid, :null}]
    }
  },
  %{
    name: "OID as list, value as :null",
    pdu: %SnmpLib.PDU{
      version: 1,
      community: "public",
      pdu_type: 0xA0,  # GET_REQUEST
      request_id: 12346,
      error_status: 0,
      error_index: 0,
      variable_bindings: [{test_oid_list, :null}]
    }
  },
  %{
    name: "OID as string, value as object_identifier tuple",
    pdu: %SnmpLib.PDU{
      version: 1,
      community: "public",
      pdu_type: 0xA0,  # GET_REQUEST
      request_id: 12347,
      error_status: 0,
      error_index: 0,
      variable_bindings: [{test_oid, test_oid_tuple}]
    }
  },
  %{
    name: "OID as list, value as object_identifier tuple",
    pdu: %SnmpLib.PDU{
      version: 1,
      community: "public",
      pdu_type: 0xA0,  # GET_REQUEST
      request_id: 12348,
      error_status: 0,
      error_index: 0,
      variable_bindings: [{test_oid_list, test_oid_tuple}]
    }
  },
  %{
    name: "Variable binding with type specification",
    pdu: %SnmpLib.PDU{
      version: 1,
      community: "public",
      pdu_type: 0xA0,  # GET_REQUEST
      request_id: 12349,
      error_status: 0,
      error_index: 0,
      variable_bindings: [{test_oid_list, :object_identifier, test_oid_tuple}]
    }
  }
]

IO.puts("\n3. Testing encode/decode for each case...")

for %{name: case_name, pdu: original_pdu} <- test_cases do
  IO.puts("\n--- Testing: #{case_name} ---")
  
  IO.puts("Original PDU:")
  IO.puts("  version: #{inspect(original_pdu.version)}")
  IO.puts("  community: #{inspect(original_pdu.community)}")
  IO.puts("  pdu_type: 0x#{Integer.to_string(original_pdu.pdu_type, 16)}")
  IO.puts("  request_id: #{inspect(original_pdu.request_id)}")
  IO.puts("  variable_bindings: #{inspect(original_pdu.variable_bindings)}")
  
  # Step 1: Encode the PDU
  IO.puts("\nStep 1: Encoding PDU...")
  encode_result = SnmpLib.PDU.encode(original_pdu)
  
  case encode_result do
    {:ok, encoded_binary} ->
      IO.puts("✓ Encoding successful")
      IO.puts("  Encoded size: #{byte_size(encoded_binary)} bytes")
      IO.puts("  First 20 bytes (hex): #{Base.encode16(binary_part(encoded_binary, 0, min(20, byte_size(encoded_binary))))}")
      
      # Step 2: Decode the PDU
      IO.puts("\nStep 2: Decoding PDU...")
      decode_result = SnmpLib.PDU.decode(encoded_binary)
      
      case decode_result do
        {:ok, decoded_pdu} ->
          IO.puts("✓ Decoding successful")
          IO.puts("Decoded PDU:")
          IO.puts("  version: #{inspect(decoded_pdu.version)}")
          IO.puts("  community: #{inspect(decoded_pdu.community)}")
          IO.puts("  pdu_type: 0x#{Integer.to_string(decoded_pdu.pdu_type, 16)}")
          IO.puts("  request_id: #{inspect(decoded_pdu.request_id)}")
          IO.puts("  variable_bindings: #{inspect(decoded_pdu.variable_bindings)}")
          
          # Step 3: Compare original vs decoded
          IO.puts("\nStep 3: Comparison...")
          original_vb = hd(original_pdu.variable_bindings)
          decoded_vb = hd(decoded_pdu.variable_bindings)
          
          IO.puts("Original variable binding: #{inspect(original_vb)}")
          IO.puts("Decoded variable binding:  #{inspect(decoded_vb)}")
          
          # Check if values match
          if original_vb == decoded_vb do
            IO.puts("✓ Variable bindings match exactly")
          else
            IO.puts("✗ Variable bindings differ!")
            IO.puts("  Original type: #{inspect(elem(original_vb, 1))}")
            IO.puts("  Decoded type:  #{inspect(elem(decoded_vb, 1))}")
            
            if tuple_size(original_vb) == 2 and tuple_size(decoded_vb) == 2 do
              IO.puts("  Original value: #{inspect(elem(original_vb, 1))}")
              IO.puts("  Decoded value:  #{inspect(elem(decoded_vb, 1))}")
            end
          end
          
        {:error, decode_error} ->
          IO.puts("✗ Decoding failed: #{inspect(decode_error)}")
      end
      
    {:error, encode_error} ->
      IO.puts("✗ Encoding failed: #{inspect(encode_error)}")
  end
  
  IO.puts(String.duplicate("-", 80))
end

IO.puts("\n4. Testing with SnmpLib.PDU builder functions...")

# Test using the builder functions
IO.puts("\nTesting SnmpLib.PDU.build_get_request...")
built_pdu = SnmpLib.PDU.build_get_request(test_oid_list, 99999)
IO.puts("Built PDU: #{inspect(built_pdu)}")

# Try building message and encoding/decoding
message = SnmpLib.PDU.build_message(built_pdu, "public", :v2c)
IO.puts("Built message: #{inspect(message)}")

case SnmpLib.PDU.encode_message(message) do
  {:ok, encoded_msg} ->
    IO.puts("✓ Message encoding successful")
    IO.puts("  Encoded size: #{byte_size(encoded_msg)} bytes")
    
    case SnmpLib.PDU.decode_message(encoded_msg) do
      {:ok, decoded_msg} ->
        IO.puts("✓ Message decoding successful")
        IO.puts("Decoded message: #{inspect(decoded_msg)}")
      {:error, reason} ->
        IO.puts("✗ Message decoding failed: #{inspect(reason)}")
    end
  {:error, reason} ->
    IO.puts("✗ Message encoding failed: #{inspect(reason)}")
end

IO.puts("\n5. Testing specific object identifier encoding...")

# Test object identifier encoding directly
test_value_cases = [
  {:null, :null},
  {:object_identifier, test_oid},
  {:object_identifier, test_oid_list},
  {:string, "test-value"},
  {:integer, 42}
]

for {value_type, value} <- test_value_cases do
  IO.puts("\nTesting value type :#{value_type} with value #{inspect(value)}")
  
  test_pdu = %SnmpLib.PDU{
    version: 1,
    community: "public",
    pdu_type: 0xA2,  # GET_RESPONSE
    request_id: 55555,
    error_status: 0,
    error_index: 0,
    variable_bindings: [{test_oid_list, value_type, value}]
  }
  
  case SnmpLib.PDU.encode(test_pdu) do
    {:ok, encoded} ->
      case SnmpLib.PDU.decode(encoded) do
        {:ok, decoded} ->
          original_vb = hd(test_pdu.variable_bindings)
          decoded_vb = hd(decoded.variable_bindings)
          IO.puts("  Original: #{inspect(original_vb)}")
          IO.puts("  Decoded:  #{inspect(decoded_vb)}")
          
          if original_vb == decoded_vb do
            IO.puts("  ✓ Round-trip successful")
          else
            IO.puts("  ✗ Round-trip failed - values differ")
          end
        {:error, reason} ->
          IO.puts("  ✗ Decode failed: #{inspect(reason)}")
      end
    {:error, reason} ->
      IO.puts("  ✗ Encode failed: #{inspect(reason)}")
  end
end

IO.puts("\n=== Object Identifier Debug Complete ===")