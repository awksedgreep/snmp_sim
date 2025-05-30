defmodule SNMPSimEx.Core.PDU do
  @moduledoc """
  Complete SNMP PDU encoding/decoding for v1 and v2c protocols.
  Handles GET, GETNEXT, GETBULK, and SET operations.
  """

  # SNMP PDU Types
  @get_request 0xA0
  @getnext_request 0xA1
  @get_response 0xA2
  @set_request 0xA3
  @getbulk_request 0xA5

  # SNMP Data Types
  @integer 0x02
  @octet_string 0x04
  @null 0x05
  @object_identifier 0x06
  @counter32 0x41
  @gauge32 0x42
  @timeticks 0x43
  @counter64 0x46
  @no_such_object 0x80
  @no_such_instance 0x81
  @end_of_mib_view 0x82

  # SNMP Error Status
  @no_error 0

  defstruct [
    :version,
    :community,
    :pdu_type,
    :request_id,
    :error_status,
    :error_index,
    :variable_bindings,
    :non_repeaters,
    :max_repetitions
  ]

  @doc """
  Decode an SNMP packet from binary data.
  
  ## Examples
  
      {:ok, pdu} = SNMPSimEx.Core.PDU.decode(packet_data)
      
  """
  def decode(binary_packet) when is_binary(binary_packet) do
    try do
      {packet, _remaining} = decode_sequence(binary_packet)
      parse_snmp_message(packet)
    rescue
      _error -> 
        {:error, :malformed_packet}
    end
  end

  @doc """
  Encode an SNMP response PDU to binary format.
  
  ## Examples
  
      response = %SNMPSimEx.Core.PDU{
        version: 1,
        community: "public",
        pdu_type: @get_response,
        request_id: 12345,
        error_status: @no_error,
        error_index: 0,
        variable_bindings: [{"1.3.6.1.2.1.1.1.0", "Test Device"}]
      }
      
      {:ok, binary} = SNMPSimEx.Core.PDU.encode(response)
      
  """
  def encode(%__MODULE__{} = pdu) do
    try do
      binary = encode_snmp_message(pdu)
      {:ok, binary}
    rescue
      _ -> {:error, :encoding_failed}
    end
  end

  @doc """
  Validate community string for v1/v2c authentication.
  """
  def validate_community(packet, expected_community) do
    case decode(packet) do
      {:ok, %{community: ^expected_community}} -> :ok
      {:ok, %{community: _other}} -> {:error, :invalid_community}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Create an error response PDU.
  """
  def create_error_response(request_pdu, error_status, error_index \\ 0) do
    %__MODULE__{
      version: request_pdu.version,
      community: request_pdu.community,
      pdu_type: @get_response,
      request_id: request_pdu.request_id,
      error_status: error_status,
      error_index: error_index,
      variable_bindings: request_pdu.variable_bindings
    }
  end

  # Private functions for BER/DER encoding/decoding

  defp decode_sequence(<<0x30, length_byte, rest::binary>>) when length_byte < 0x80 do
    <<data::binary-size(length_byte), remaining::binary>> = rest
    {decode_sequence_contents(data), remaining}
  end

  defp decode_sequence(<<0x30, 0x81, length_byte, rest::binary>>) do
    <<data::binary-size(length_byte), remaining::binary>> = rest
    {decode_sequence_contents(data), remaining}
  end

  defp decode_sequence(<<0x30, 0x82, length::16, rest::binary>>) do
    <<data::binary-size(length), remaining::binary>> = rest
    {decode_sequence_contents(data), remaining}
  end

  defp decode_sequence_contents(data) do
    decode_sequence_items(data, [])
  end

  defp decode_sequence_items("", acc), do: Enum.reverse(acc)

  defp decode_sequence_items(data, acc) do
    {item, remaining} = decode_item(data)
    decode_sequence_items(remaining, [item | acc])
  end

  defp decode_item(<<tag, length_byte, rest::binary>>) when length_byte < 0x80 do
    <<value::binary-size(length_byte), remaining::binary>> = rest
    {decode_value(tag, value), remaining}
  end

  defp decode_item(<<tag, 0x81, length_byte, rest::binary>>) do
    <<value::binary-size(length_byte), remaining::binary>> = rest
    {decode_value(tag, value), remaining}
  end

  defp decode_item(<<tag, 0x82, length::16, rest::binary>>) do
    <<value::binary-size(length), remaining::binary>> = rest
    {decode_value(tag, value), remaining}
  end

  defp decode_value(@integer, value), do: decode_integer(value)
  defp decode_value(@octet_string, value), do: value
  defp decode_value(@null, _), do: nil
  defp decode_value(@object_identifier, value), do: decode_oid(value)
  defp decode_value(@counter32, value), do: {:counter32, decode_integer(value)}
  defp decode_value(@gauge32, value), do: {:gauge32, decode_integer(value)}
  defp decode_value(@timeticks, value), do: {:timeticks, decode_integer(value)}
  defp decode_value(@counter64, value), do: {:counter64, decode_integer(value)}
  defp decode_value(@no_such_object, _), do: {:no_such_object, nil}
  defp decode_value(@no_such_instance, _), do: {:no_such_instance, nil}
  defp decode_value(@end_of_mib_view, _), do: {:end_of_mib_view, nil}
  defp decode_value(tag, value) when tag in [@get_request, @getnext_request, @get_response, @set_request, @getbulk_request] do
    {:pdu, tag, decode_sequence_contents(value)}
  end
  defp decode_value(0x30, value), do: {:sequence, decode_sequence_contents(value)}
  defp decode_value(_tag, value), do: value

  defp decode_integer(<<>>), do: 0
  defp decode_integer(<<byte>>) do
    if byte >= 128, do: byte - 256, else: byte
  end
  defp decode_integer(<<0, rest::binary>>) when byte_size(rest) > 0 do
    # Leading zero for positive integers
    :binary.decode_unsigned(rest, :big)
  end
  defp decode_integer(bytes) do
    # Check if it's a negative number (MSB is 1)
    <<msb, _rest::binary>> = bytes
    if msb >= 128 do
      # Negative number in two's complement
      bit_size = byte_size(bytes) * 8
      max_value = :math.pow(2, bit_size) |> trunc()
      unsigned_value = :binary.decode_unsigned(bytes, :big)
      unsigned_value - max_value
    else
      :binary.decode_unsigned(bytes, :big)
    end
  end

  defp decode_oid(<<first_byte, rest::binary>>) do
    {first, second} = if first_byte >= 80 do
      {2, first_byte - 80}
    else
      {div(first_byte, 40), rem(first_byte, 40)}
    end
    remaining_oids = decode_oid_subids(rest, [])
    Enum.join([first, second | remaining_oids], ".")
  end

  defp decode_oid_subids(<<>>, acc), do: Enum.reverse(acc)
  defp decode_oid_subids(data, acc) do
    {subid, remaining} = decode_oid_subid(data, 0)
    decode_oid_subids(remaining, [subid | acc])
  end

  defp decode_oid_subid(<<0::1, value::7, rest::binary>>, acc) do
    {acc * 128 + value, rest}
  end

  defp decode_oid_subid(<<1::1, value::7, rest::binary>>, acc) do
    decode_oid_subid(rest, acc * 128 + value)
  end

  defp parse_snmp_message([version, community, {:pdu, pdu_type, pdu_contents}]) do
    case pdu_type do
      @getbulk_request ->
        [request_id, non_repeaters, max_repetitions, varbind_sequence] = pdu_contents
        {:ok, %__MODULE__{
          version: version,
          community: community,
          pdu_type: pdu_type,
          request_id: request_id,
          non_repeaters: non_repeaters,
          max_repetitions: max_repetitions,
          variable_bindings: parse_varbinds_sequence(varbind_sequence)
        }}

      _ ->
        [request_id, error_status, error_index, varbind_sequence] = pdu_contents
        {:ok, %__MODULE__{
          version: version,
          community: community,
          pdu_type: pdu_type,
          request_id: request_id,
          error_status: error_status,
          error_index: error_index,
          variable_bindings: parse_varbinds_sequence(varbind_sequence)
        }}
    end
  end

  defp parse_varbinds_sequence({:sequence, varbind_list}) do
    parse_varbinds(varbind_list)
  end
  
  defp parse_varbinds_sequence(_), do: []

  defp parse_varbinds(varbind_list) do
    varbind_list
    |> Enum.map(&parse_varbind/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_varbind({:sequence, [oid, value]}) do
    {oid, value}
  end

  defp parse_varbind(_), do: nil

  defp encode_snmp_message(%__MODULE__{} = pdu) do
    version_encoded = encode_integer(pdu.version)
    community_encoded = encode_octet_string(pdu.community)
    pdu_encoded = encode_pdu(pdu)

    sequence_contents = version_encoded <> community_encoded <> pdu_encoded
    encode_sequence(sequence_contents)
  end

  defp encode_pdu(%__MODULE__{pdu_type: @getbulk_request} = pdu) do
    request_id_encoded = encode_integer(pdu.request_id)
    non_repeaters_encoded = encode_integer(pdu.non_repeaters || 0)
    max_repetitions_encoded = encode_integer(pdu.max_repetitions || 10)
    varbinds_encoded = encode_varbinds(pdu.variable_bindings)

    pdu_contents = request_id_encoded <> non_repeaters_encoded <> max_repetitions_encoded <> varbinds_encoded
    encode_tag_length_value(pdu.pdu_type, pdu_contents)
  end

  defp encode_pdu(%__MODULE__{} = pdu) do
    request_id_encoded = encode_integer(pdu.request_id)
    error_status_encoded = encode_integer(pdu.error_status || @no_error)
    error_index_encoded = encode_integer(pdu.error_index || 0)
    varbinds_encoded = encode_varbinds(pdu.variable_bindings)

    pdu_contents = request_id_encoded <> error_status_encoded <> error_index_encoded <> varbinds_encoded
    encode_tag_length_value(pdu.pdu_type, pdu_contents)
  end

  defp encode_varbinds(varbinds) when is_list(varbinds) do
    encoded_varbinds = Enum.map(varbinds, &encode_varbind/1)
    encode_sequence(Enum.join(encoded_varbinds))
  end

  defp encode_varbind({oid, value}) do
    oid_encoded = encode_oid(oid)
    value_encoded = encode_value(value)
    varbind_contents = oid_encoded <> value_encoded
    encode_sequence(varbind_contents)
  end

  defp encode_value(value) when is_binary(value), do: encode_octet_string(value)
  defp encode_value(value) when is_integer(value), do: encode_integer(value)
  defp encode_value({:counter32, value}), do: encode_tag_length_value(@counter32, encode_integer_bytes(value))
  defp encode_value({:gauge32, value}), do: encode_tag_length_value(@gauge32, encode_integer_bytes(value))
  defp encode_value({:timeticks, value}), do: encode_tag_length_value(@timeticks, encode_integer_bytes(value))
  defp encode_value({:counter64, value}), do: encode_tag_length_value(@counter64, encode_integer_bytes(value))
  defp encode_value({:no_such_object, _}), do: encode_tag_length_value(@no_such_object, "")
  defp encode_value({:no_such_instance, _}), do: encode_tag_length_value(@no_such_instance, "")
  defp encode_value({:end_of_mib_view, _}), do: encode_tag_length_value(@end_of_mib_view, "")
  defp encode_value(nil), do: encode_tag_length_value(@null, "")
  defp encode_value(_), do: encode_tag_length_value(@null, "")

  defp encode_integer(value) do
    encode_tag_length_value(@integer, encode_integer_bytes(value))
  end

  defp encode_integer_bytes(value) when value >= 0 and value <= 127 do
    <<value>>
  end

  defp encode_integer_bytes(value) when value >= 128 do
    encoded = :binary.encode_unsigned(value, :big)
    # Ensure the most significant bit is 0 for positive integers
    case encoded do
      <<msb, _rest::binary>> when msb >= 128 ->
        <<0>> <> encoded
      _ ->
        encoded
    end
  end

  defp encode_integer_bytes(value) when value < 0 do
    # Two's complement for negative integers
    pos_value = abs(value)
    bit_length = bit_size(:binary.encode_unsigned(pos_value, :big))
    byte_length = div(bit_length + 7, 8)
    max_value = :math.pow(2, byte_length * 8) |> trunc()
    encoded_value = max_value + value
    :binary.encode_unsigned(encoded_value, :big)
  end

  defp encode_octet_string(value) when is_binary(value) do
    encode_tag_length_value(@octet_string, value)
  end

  defp encode_oid(oid_string) when is_binary(oid_string) do
    oid_parts = String.split(oid_string, ".") |> Enum.map(&String.to_integer/1)
    encode_tag_length_value(@object_identifier, encode_oid_bytes(oid_parts))
  end

  defp encode_oid_bytes([first, second | rest]) do
    first_byte = first * 40 + second
    encoded_rest = Enum.map(rest, &encode_oid_subid/1) |> Enum.join("")
    <<first_byte>> <> encoded_rest
  end

  defp encode_oid_subid(value) when value < 128 do
    <<value>>
  end

  defp encode_oid_subid(value) do
    encode_oid_subid_bytes(value, [])
  end

  defp encode_oid_subid_bytes(0, [byte | rest]) do
    :binary.list_to_bin([byte | rest])
  end

  defp encode_oid_subid_bytes(value, []) do
    encode_oid_subid_bytes(div(value, 128), [rem(value, 128)])
  end

  defp encode_oid_subid_bytes(value, acc) do
    encode_oid_subid_bytes(div(value, 128), [rem(value, 128) + 128 | acc])
  end

  defp encode_sequence(contents) do
    encode_tag_length_value(0x30, contents)
  end

  defp encode_tag_length_value(tag, contents) when is_binary(contents) do
    length = byte_size(contents)
    <<tag>> <> encode_length(length) <> contents
  end

  defp encode_length(length) when length < 128 do
    <<length>>
  end

  defp encode_length(length) when length < 256 do
    <<0x81, length>>
  end

  defp encode_length(length) when length < 65536 do
    <<0x82, length::16>>
  end

  defp encode_length(length) do
    bytes = :binary.encode_unsigned(length, :big)
    byte_count = byte_size(bytes)
    <<0x80 + byte_count>> <> bytes
  end
end