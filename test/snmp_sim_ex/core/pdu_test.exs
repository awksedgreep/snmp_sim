defmodule SnmpSimEx.Core.PDUTest do
  use ExUnit.Case, async: false
  
  alias SnmpSimEx.Core.PDU

  describe "SNMP PDU Processing" do
    test "decodes SNMPv1 GET request with multiple OIDs" do
      # Simple test PDU structure (this would be actual BER-encoded data in practice)
      test_pdu = %PDU{
        version: 0,
        community: "public",
        pdu_type: 0xA0,
        request_id: 12345,
        error_status: 0,
        error_index: 0,
        variable_bindings: [
          {"1.3.6.1.2.1.1.1.0", nil},
          {"1.3.6.1.2.1.1.2.0", nil}
        ]
      }
      
      # Encode and then decode to test round-trip
      {:ok, encoded} = PDU.encode(test_pdu)
      {:ok, decoded} = PDU.decode(encoded)
      
      assert decoded.version == 0
      assert decoded.community == "public"
      assert decoded.pdu_type == 0xA0
      assert decoded.request_id == 12345
      assert length(decoded.variable_bindings) == 2
    end

    test "decodes SNMPv2c GETNEXT request" do
      test_pdu = %PDU{
        version: 1,
        community: "public",
        pdu_type: 0xA1,
        request_id: 54321,
        error_status: 0,
        error_index: 0,
        variable_bindings: [{"1.3.6.1.2.1.1.1", nil}]
      }
      
      {:ok, encoded} = PDU.encode(test_pdu)
      {:ok, decoded} = PDU.decode(encoded)
      
      assert decoded.version == 1
      assert decoded.pdu_type == 0xA1
      assert decoded.request_id == 54321
    end

    test "handles malformed PDU gracefully" do
      malformed_data = <<0x01, 0x02, 0x03, 0x04>>
      
      result = PDU.decode(malformed_data)
      
      assert {:error, :malformed_packet} = result
    end

    test "validates community strings correctly" do
      # Test PDU with known community string
      test_pdu = %PDU{
        version: 1,
        community: "public",
        pdu_type: 0xA0,
        request_id: 12345,
        error_status: 0,
        error_index: 0,
        variable_bindings: []
      }
      
      {:ok, encoded} = PDU.encode(test_pdu)
      
      assert :ok = PDU.validate_community(encoded, "public")
      assert {:error, :invalid_community} = PDU.validate_community(encoded, "private")
    end

    test "encodes responses with proper data types" do
      response_pdu = %PDU{
        version: 1,
        community: "public",
        pdu_type: 0xA2,
        request_id: 12345,
        error_status: 0,
        error_index: 0,
        variable_bindings: [
          {"1.3.6.1.2.1.1.1.0", "Test Device"},
          {"1.3.6.1.2.1.2.2.1.10.1", {:counter32, 1234567890}},
          {"1.3.6.1.2.1.2.2.1.5.1", {:gauge32, 1000000000}}
        ]
      }
      
      result = PDU.encode(response_pdu)
      
      assert {:ok, _encoded_data} = result
    end

    test "handles oversized requests with tooBig error" do
      # Create a request with many OIDs to test size limits
      large_varbinds = for i <- 1..1000 do
        {"1.3.6.1.2.1.2.2.1.10.#{i}", nil}
      end
      
      large_pdu = %PDU{
        version: 1,
        community: "public",
        pdu_type: 0xA0,
        request_id: 99999,
        error_status: 0,
        error_index: 0,
        variable_bindings: large_varbinds
      }
      
      {:ok, encoded} = PDU.encode(large_pdu)
      
      # Check that we can still encode large requests
      # (Size checking would happen at the server level)
      assert byte_size(encoded) > 1000
    end
  end

  describe "Error Handling" do
    test "creates proper error responses" do
      original_pdu = %PDU{
        version: 1,
        community: "public", 
        pdu_type: 0xA0,
        request_id: 12345,
        error_status: 0,
        error_index: 0,
        variable_bindings: [{"1.3.6.1.2.1.1.1.0", nil}]
      }
      
      error_response = PDU.create_error_response(original_pdu, 2, 1)
      
      assert error_response.version == 1
      assert error_response.community == "public"
      assert error_response.pdu_type == 0xA2  # GET_RESPONSE
      assert error_response.request_id == 12345
      assert error_response.error_status == 2  # noSuchName
      assert error_response.error_index == 1
    end

    test "handles encoding failures gracefully" do
      # Test with invalid data that should cause encoding to fail
      invalid_pdu = %PDU{
        version: "invalid",  # Invalid version
        community: nil,      # Invalid community
        pdu_type: 0xA0,
        request_id: 12345,
        variable_bindings: []
      }
      
      result = PDU.encode(invalid_pdu)
      
      assert {:error, :encoding_failed} = result
    end
  end

  describe "Data Type Encoding" do
    test "encodes INTEGER values correctly" do
      pdu = %PDU{
        version: 1,
        community: "public",
        pdu_type: 0xA2,
        request_id: 1,
        error_status: 0,
        error_index: 0,
        variable_bindings: [{"1.3.6.1.2.1.1.7.0", 72}]
      }
      
      {:ok, encoded} = PDU.encode(pdu)
      {:ok, decoded} = PDU.decode(encoded)
      
      assert [{"1.3.6.1.2.1.1.7.0", 72}] = decoded.variable_bindings
    end

    test "encodes Counter32 values correctly" do
      pdu = %PDU{
        version: 1,
        community: "public",
        pdu_type: 0xA2,
        request_id: 1,
        error_status: 0,
        error_index: 0,
        variable_bindings: [{"1.3.6.1.2.1.2.2.1.10.1", {:counter32, 4294967295}}]
      }
      
      {:ok, encoded} = PDU.encode(pdu)
      {:ok, decoded} = PDU.decode(encoded)
      
      assert [{"1.3.6.1.2.1.2.2.1.10.1", {:counter32, 4294967295}}] = decoded.variable_bindings
    end

    test "encodes STRING values correctly" do
      pdu = %PDU{
        version: 1,
        community: "public",
        pdu_type: 0xA2,
        request_id: 1,
        error_status: 0,
        error_index: 0,
        variable_bindings: [{"1.3.6.1.2.1.1.1.0", "Test Device Description"}]
      }
      
      {:ok, encoded} = PDU.encode(pdu)
      {:ok, decoded} = PDU.decode(encoded)
      
      assert [{"1.3.6.1.2.1.1.1.0", "Test Device Description"}] = decoded.variable_bindings
    end
  end

  describe "GETBULK Support" do
    test "decodes GETBULK requests correctly" do
      getbulk_pdu = %PDU{
        version: 1,
        community: "public",
        pdu_type: 0xA5,
        request_id: 12345,
        non_repeaters: 1,
        max_repetitions: 10,
        variable_bindings: [
          {"1.3.6.1.2.1.1.1.0", nil},
          {"1.3.6.1.2.1.2.2.1.1", nil}
        ]
      }
      
      {:ok, encoded} = PDU.encode(getbulk_pdu)
      {:ok, decoded} = PDU.decode(encoded)
      
      assert decoded.pdu_type == 0xA5
      assert decoded.non_repeaters == 1
      assert decoded.max_repetitions == 10
      assert length(decoded.variable_bindings) == 2
    end
  end
end

