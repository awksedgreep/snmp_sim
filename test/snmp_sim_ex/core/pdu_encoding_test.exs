defmodule SNMPSimEx.Core.PDUEncodingTest do
  @moduledoc """
  Comprehensive PDU encoding/decoding tests.
  
  This test specifically focuses on edge cases and data type handling
  that could cause "Wrong Type: NULL" issues in SNMP responses.
  """
  
  use ExUnit.Case, async: true
  
  alias SNMPSimEx.Core.PDU
  
  describe "SNMP data type encoding" do
    test "string values encode as OCTET STRING" do
      pdu = create_test_pdu("test string")
      {:ok, encoded} = PDU.encode(pdu)
      {:ok, decoded} = PDU.decode(encoded)
      
      [{_oid, value}] = decoded.variable_bindings
      assert value == "test string"
      assert is_binary(value)
    end
    
    test "integer values encode as INTEGER" do
      pdu = create_test_pdu(42)
      {:ok, encoded} = PDU.encode(pdu)
      {:ok, decoded} = PDU.decode(encoded)
      
      [{_oid, value}] = decoded.variable_bindings
      assert value == 42
      assert is_integer(value)
    end
    
    test "object identifier tuples encode correctly" do
      oid_value = {:object_identifier, "1.3.6.1.2.1.1.1.0"}
      pdu = create_test_pdu(oid_value)
      {:ok, encoded} = PDU.encode(pdu)
      {:ok, decoded} = PDU.decode(encoded)
      
      [{_oid, value}] = decoded.variable_bindings
      assert value == oid_value
    end
    
    test "counter32 values encode correctly" do
      counter_value = {:counter32, 12345}
      pdu = create_test_pdu(counter_value)
      {:ok, encoded} = PDU.encode(pdu)
      {:ok, decoded} = PDU.decode(encoded)
      
      [{_oid, value}] = decoded.variable_bindings
      assert value == counter_value
    end
    
    test "gauge32 values encode correctly" do
      gauge_value = {:gauge32, 67890}
      pdu = create_test_pdu(gauge_value)
      {:ok, encoded} = PDU.encode(pdu)
      {:ok, decoded} = PDU.decode(encoded)
      
      [{_oid, value}] = decoded.variable_bindings
      assert value == gauge_value
    end
    
    test "timeticks values encode correctly" do
      timeticks_value = {:timeticks, 54321}
      pdu = create_test_pdu(timeticks_value)
      {:ok, encoded} = PDU.encode(pdu)
      {:ok, decoded} = PDU.decode(encoded)
      
      [{_oid, value}] = decoded.variable_bindings
      assert value == timeticks_value
    end
    
    test "counter64 values encode correctly" do
      counter64_value = {:counter64, 9876543210}
      pdu = create_test_pdu(counter64_value)
      {:ok, encoded} = PDU.encode(pdu)
      {:ok, decoded} = PDU.decode(encoded)
      
      [{_oid, value}] = decoded.variable_bindings
      assert value == counter64_value
    end
    
    test "SNMP exception types encode correctly" do
      exception_types = [
        {:no_such_object, nil},
        {:no_such_instance, nil},
        {:end_of_mib_view, nil}
      ]
      
      for exception_value <- exception_types do
        pdu = create_test_pdu(exception_value)
        {:ok, encoded} = PDU.encode(pdu)
        {:ok, decoded} = PDU.decode(encoded)
        
        [{_oid, value}] = decoded.variable_bindings
        assert value == exception_value
      end
    end
    
    test "nil values encode as NULL" do
      pdu = create_test_pdu(nil)
      {:ok, encoded} = PDU.encode(pdu)
      {:ok, decoded} = PDU.decode(encoded)
      
      [{_oid, value}] = decoded.variable_bindings
      assert value == nil
    end
    
    test "unknown types encode as NULL" do
      # Test that unknown types fallback to NULL encoding
      pdu = create_test_pdu({:unknown_type, "some value"})
      {:ok, encoded} = PDU.encode(pdu)
      {:ok, decoded} = PDU.decode(encoded)
      
      [{_oid, value}] = decoded.variable_bindings
      assert value == nil
    end
  end
  
  describe "PDU structure encoding" do
    test "GET request PDU encodes correctly" do
      pdu = %PDU{
        version: 1,  # SNMPv2c
        community: "public",
        pdu_type: 0xA0,  # GET_REQUEST
        request_id: 1234,
        error_status: 0,
        error_index: 0,
        variable_bindings: [
          {"1.3.6.1.2.1.1.1.0", nil},
          {"1.3.6.1.2.1.1.3.0", nil}
        ]
      }
      
      {:ok, encoded} = PDU.encode(pdu)
      {:ok, decoded} = PDU.decode(encoded)
      
      assert decoded.version == pdu.version
      assert decoded.community == pdu.community
      assert decoded.pdu_type == pdu.pdu_type
      assert decoded.request_id == pdu.request_id
      assert decoded.error_status == pdu.error_status
      assert decoded.error_index == pdu.error_index
      assert length(decoded.variable_bindings) == 2
    end
    
    test "GET response PDU encodes correctly" do
      pdu = %PDU{
        version: 1,  # SNMPv2c
        community: "public",
        pdu_type: 0xA2,  # GET_RESPONSE
        request_id: 1234,
        error_status: 0,
        error_index: 0,
        variable_bindings: [
          {"1.3.6.1.2.1.1.1.0", "System Description"},
          {"1.3.6.1.2.1.1.3.0", {:timeticks, 12345}}
        ]
      }
      
      {:ok, encoded} = PDU.encode(pdu)
      {:ok, decoded} = PDU.decode(encoded)
      
      assert decoded.version == pdu.version
      assert decoded.community == pdu.community
      assert decoded.pdu_type == pdu.pdu_type
      assert decoded.request_id == pdu.request_id
      assert decoded.error_status == pdu.error_status
      assert decoded.error_index == pdu.error_index
      
      [{oid1, value1}, {oid2, value2}] = decoded.variable_bindings
      # Handle the case where OIDs might be returned as tuples
      oid1_str = case oid1 do
        {:object_identifier, str} -> str
        str when is_binary(str) -> str
      end
      oid2_str = case oid2 do
        {:object_identifier, str} -> str
        str when is_binary(str) -> str
      end
      assert oid1_str == "1.3.6.1.2.1.1.1.0"
      assert value1 == "System Description"
      assert oid2_str == "1.3.6.1.2.1.1.3.0"
      assert value2 == {:timeticks, 12345}
    end
    
    test "GETNEXT request PDU encodes correctly" do
      pdu = %PDU{
        version: 1,
        community: "public",
        pdu_type: 0xA1,  # GETNEXT_REQUEST
        request_id: 5678,
        error_status: 0,
        error_index: 0,
        variable_bindings: [{"1.3.6.1.2.1.1", nil}]
      }
      
      {:ok, encoded} = PDU.encode(pdu)
      {:ok, decoded} = PDU.decode(encoded)
      
      assert decoded.version == pdu.version
      assert decoded.community == pdu.community
      assert decoded.pdu_type == pdu.pdu_type
      assert decoded.request_id == pdu.request_id
    end
    
    test "GETBULK request PDU encodes correctly" do
      pdu = %PDU{
        version: 1,
        community: "public",
        pdu_type: 0xA5,  # GETBULK_REQUEST
        request_id: 9999,
        non_repeaters: 1,
        max_repetitions: 10,
        variable_bindings: [
          {"1.3.6.1.2.1.1.1.0", nil},
          {"1.3.6.1.2.1.2.2.1.1", nil}
        ]
      }
      
      {:ok, encoded} = PDU.encode(pdu)
      {:ok, decoded} = PDU.decode(encoded)
      
      assert decoded.version == pdu.version
      assert decoded.community == pdu.community
      assert decoded.pdu_type == pdu.pdu_type
      assert decoded.request_id == pdu.request_id
      assert decoded.non_repeaters == pdu.non_repeaters
      assert decoded.max_repetitions == pdu.max_repetitions
    end
  end
  
  describe "error response encoding" do
    test "creates proper error response PDUs" do
      original_pdu = %PDU{
        version: 1,
        community: "public",
        pdu_type: 0xA0,  # GET_REQUEST
        request_id: 1111,
        error_status: 0,
        error_index: 0,
        variable_bindings: [{"1.3.6.1.99.99.99.0", nil}]
      }
      
      error_response = PDU.create_error_response(original_pdu, 2, 1)  # noSuchName, index 1
      
      assert error_response.version == original_pdu.version
      assert error_response.community == original_pdu.community
      assert error_response.pdu_type == 0xA2  # GET_RESPONSE
      assert error_response.request_id == original_pdu.request_id
      assert error_response.error_status == 2  # noSuchName
      assert error_response.error_index == 1
      
      # Error response should encode/decode properly
      {:ok, encoded} = PDU.encode(error_response)
      {:ok, decoded} = PDU.decode(encoded)
      assert decoded.error_status == 2
      assert decoded.error_index == 1
    end
  end
  
  describe "edge cases and boundary conditions" do
    test "handles empty variable bindings" do
      pdu = %PDU{
        version: 1,
        community: "public",
        pdu_type: 0xA2,
        request_id: 1,
        error_status: 0,
        error_index: 0,
        variable_bindings: []
      }
      
      {:ok, encoded} = PDU.encode(pdu)
      {:ok, decoded} = PDU.decode(encoded)
      
      assert decoded.variable_bindings == []
    end
    
    test "handles very long OIDs" do
      long_oid = "1.3.6.1.2.1.1.1.0" <> String.duplicate(".999", 50)
      pdu = create_test_pdu("test value", long_oid)
      
      {:ok, encoded} = PDU.encode(pdu)
      {:ok, decoded} = PDU.decode(encoded)
      
      [{decoded_oid, _value}] = decoded.variable_bindings
      # Handle the case where OIDs might be returned as tuples
      decoded_oid_str = case decoded_oid do
        {:object_identifier, str} -> str
        str when is_binary(str) -> str
      end
      assert decoded_oid_str == long_oid
    end
    
    test "handles very long string values" do
      long_string = String.duplicate("a", 10000)
      pdu = create_test_pdu(long_string)
      
      {:ok, encoded} = PDU.encode(pdu)
      {:ok, decoded} = PDU.decode(encoded)
      
      [{_oid, value}] = decoded.variable_bindings
      assert value == long_string
    end
    
    test "handles large integer values" do
      large_integers = [
        0,
        1,
        255,
        256,
        65535,
        65536,
        16777215,
        16777216,
        4294967295,  # Max 32-bit unsigned
        -1,
        -128,
        -32768,
        -2147483648  # Min 32-bit signed
      ]
      
      for int_value <- large_integers do
        pdu = create_test_pdu(int_value)
        {:ok, encoded} = PDU.encode(pdu)
        {:ok, decoded} = PDU.decode(encoded)
        
        [{_oid, value}] = decoded.variable_bindings
        assert value == int_value, "Failed to encode/decode integer: #{int_value}"
      end
    end
    
    test "handles special characters in community strings" do
      special_communities = [
        "public",
        "private",
        "test-community",
        "test_community",
        "community.with.dots",
        "community with spaces",
        "特殊文字",  # Unicode characters
        ""  # Empty community
      ]
      
      for community <- special_communities do
        pdu = %PDU{
          version: 1,
          community: community,
          pdu_type: 0xA2,
          request_id: 1,
          error_status: 0,
          error_index: 0,
          variable_bindings: [{"1.3.6.1.2.1.1.1.0", "test"}]
        }
        
        {:ok, encoded} = PDU.encode(pdu)
        {:ok, decoded} = PDU.decode(encoded)
        
        assert decoded.community == community, "Failed to encode/decode community: #{inspect(community)}"
      end
    end
  end
  
  # Helper function to create test PDUs
  defp create_test_pdu(value, oid \\ "1.3.6.1.2.1.1.1.0") do
    %PDU{
      version: 1,
      community: "public",
      pdu_type: 0xA2,  # GET_RESPONSE
      request_id: 1234,
      error_status: 0,
      error_index: 0,
      variable_bindings: [{oid, value}]
    }
  end
end