# Analyze the encoded bytes to understand the object_identifier issue
# Run with: mix run analyze_encoding.exs

IO.puts("=== Analyzing Object Identifier Encoding ===")
IO.puts("")

# The encoded bytes from our test
encoded_bytes = <<48, 39, 2, 1, 1, 4, 6, 112, 117, 98, 108, 105, 99, 162, 26, 2, 2, 48, 57, 2, 1, 0, 2, 1, 0, 48, 14, 48, 12, 6, 8, 43, 6, 1, 2, 1, 1, 1, 0, 5, 0>>

IO.puts("Encoded bytes: #{inspect(encoded_bytes, limit: :infinity)}")
IO.puts("Total length: #{byte_size(encoded_bytes)} bytes")
IO.puts("")

# Let's break down the ASN.1 BER structure
IO.puts("=== ASN.1 BER Structure Analysis ===")
IO.puts("")

# Parse the structure manually
<<
  0x30, _len1,           # SEQUENCE (SNMP message)
  0x02, 0x01, version,   # INTEGER (version)
  0x04, 0x06, community::binary-size(6), # OCTET STRING (community)
  0xA2, pdu_len,        # PDU (GET_RESPONSE)
  pdu_data::binary-size(pdu_len)
>> = encoded_bytes

IO.puts("SNMP Message Structure:")
IO.puts("  SEQUENCE tag: 0x30")
IO.puts("  Version: #{version}")
IO.puts("  Community: #{inspect(community)}")
IO.puts("  PDU tag: 0xA2 (GET_RESPONSE)")
IO.puts("  PDU length: #{pdu_len}")
IO.puts("  PDU data: #{inspect(pdu_data, limit: :infinity)}")
IO.puts("")

# Parse PDU structure
<<
  0x02, 0x02, req_id::16,  # REQUEST-ID
  0x02, 0x01, err_stat,    # ERROR-STATUS  
  0x02, 0x01, err_idx,     # ERROR-INDEX
  0x30, varbinds_len,      # SEQUENCE OF VarBind
  varbinds_data::binary-size(varbinds_len)
>> = pdu_data

IO.puts("PDU Structure:")
IO.puts("  Request ID: #{req_id}")
IO.puts("  Error Status: #{err_stat}")
IO.puts("  Error Index: #{err_idx}")
IO.puts("  VarBinds length: #{varbinds_len}")
IO.puts("  VarBinds data: #{inspect(varbinds_data, limit: :infinity)}")
IO.puts("")

# Parse VarBind structure
<<
  0x30, varbind_len,      # SEQUENCE (single VarBind)
  varbind_data::binary-size(varbind_len)
>> = varbinds_data

IO.puts("VarBind Structure:")
IO.puts("  VarBind length: #{varbind_len}")
IO.puts("  VarBind data: #{inspect(varbind_data, limit: :infinity)}")
IO.puts("")

# Parse the OID and value in the VarBind
<<
  0x06, oid_len,          # OBJECT IDENTIFIER tag
  oid_data::binary-size(oid_len),
  value_tag,              # Value tag
  value_len,              # Value length
  value_data::binary-size(value_len)
>> = varbind_data

IO.puts("VarBind Contents:")
IO.puts("  OID tag: 0x06 (OBJECT IDENTIFIER)")
IO.puts("  OID length: #{oid_len}")
IO.puts("  OID data: #{inspect(oid_data, limit: :infinity)}")
IO.puts("  Value tag: 0x#{Integer.to_string(value_tag, 16)} (#{if value_tag == 5, do: "NULL", else: "UNKNOWN"})")
IO.puts("  Value length: #{value_len}")
IO.puts("  Value data: #{inspect(value_data, limit: :infinity)}")
IO.puts("")

IO.puts("=== PROBLEM ANALYSIS ===")
IO.puts("")
IO.puts("🔍 The issue is clear now:")
IO.puts("  1. The object_identifier value was ENCODED as a NULL (tag 0x05, length 0)")
IO.puts("  2. This means the encoding step is wrong, not the decoding step")
IO.puts("  3. The encode_snmp_value_fast function is not handling {:object_identifier, string} correctly")
IO.puts("")
IO.puts("📍 Location of the bug:")
IO.puts("  File: lib/snmp_lib/pdu.ex")
IO.puts("  Function: encode_snmp_value_fast/2")
IO.puts("  Issue: Missing or incorrect handling of {:object_identifier, string} tuples")
IO.puts("")
IO.puts("🔧 Expected encoding:")
IO.puts("  - The object_identifier value should be encoded as tag 0x06 (OBJECT IDENTIFIER)")
IO.puts("  - Instead it's being encoded as tag 0x05 (NULL)")
IO.puts("  - The string '1.3.6.1.2.1.1.1.0' should be converted to proper OID encoding")
IO.puts("")
IO.puts("💡 Fix needed:")
IO.puts("  - Add proper case for {:object_identifier, string} in encode_snmp_value_fast/2")
IO.puts("  - Convert the string to an OID list and encode it properly")
IO.puts("  - The function already has some object_identifier handling but it may not cover all cases")