defmodule SnmpSim.Device.PduProcessor do
  @moduledoc """
  PDU processing functionality for SNMP device simulation.
  Handles different SNMP request types and response generation.
  """

  require Logger
  alias SnmpLib.PDU
  import SnmpSim.Device.OidHandler
  alias SnmpLib.PDU
  alias SnmpSim.MIB.SharedProfiles
  # import SnmpSim.Device.ErrorInjector

  # SNMP PDU Types (using SnmpLib constants)
  @get_request :get_request
  @getnext_request :get_next_request
  @set_request :set_request

  # SNMP Error Status (using SnmpLib constants)
  @no_error 0
  @no_such_name 2
  @gen_err 5

  # I'll move the PDU processing functions here from device.ex
  # This will be populated in the next step

  def process_snmp_pdu(%{type: pdu_type} = pdu, state)
       when pdu_type in [@get_request, :get_request, 0xA0] do
    variable_bindings =
      process_get_request(Map.get(pdu, :varbinds, Map.get(pdu, :variable_bindings, [])), state)

    # Handle errors differently based on SNMP version for GET requests too
    case Map.get(pdu, :version, 1) do
      # SNMPv1 - use error responses for missing objects
      0 ->
        has_errors =
          Enum.any?(variable_bindings, fn
            {_oid, :no_such_object, _} -> true
            # SNMPv1 treats end_of_mib as error too
            {_oid, :end_of_mib_view, _} -> true
            _ -> false
          end)

        if has_errors do
          error_response = PDU.create_error_response(pdu, @no_such_name, 1)
          {:ok, error_response}
        else
          create_get_response_with_fields(pdu, variable_bindings)
        end

      # SNMPv2c - use exception values in varbinds, no error response needed
      _ ->
        create_get_response_with_fields(pdu, variable_bindings)
    end
  end

  def process_snmp_pdu(%{type: pdu_type} = pdu, state)
       when pdu_type in [@getnext_request, :get_next_request, 0xA1, 0xA5] do
    try do
      variable_bindings =
        process_getnext_request(
          Map.get(pdu, :varbinds, Map.get(pdu, :variable_bindings, [])),
          state
        )

      # Handle errors differently based on SNMP version
      case Map.get(pdu, :version, 1) do
        # SNMPv1 - use error responses for missing objects
        0 ->
          has_errors =
            Enum.any?(variable_bindings, fn
              {_oid, :no_such_object, _} -> true
              # SNMPv1 treats end_of_mib as error too
              {_oid, :end_of_mib_view, _} -> true
              _ -> false
            end)

          if has_errors do
            error_response = PDU.create_error_response(pdu, @no_such_name, 1)
            {:ok, error_response}
          else
            create_get_response_with_fields(pdu, variable_bindings)
          end

        # SNMPv2c - use exception values in varbinds, no error response needed
        _ ->
          create_get_response_with_fields(pdu, variable_bindings)
      end
    catch
      :error, reason ->
        Logger.error("Error in GETNEXT PDU processing: #{inspect(reason)}")
        Logger.error("PDU: #{inspect(pdu)}")
        error_response = PDU.create_error_response(pdu, @gen_err, 1)
        {:ok, error_response}
    end
  end

  def process_snmp_pdu(%{type: pdu_type} = pdu, state)
       when pdu_type in [:getbulk_request, :get_bulk_request, 0xA2] do
    try do
      variable_bindings = process_getbulk_request(pdu, state)

      # Handle errors differently based on SNMP version
      case Map.get(pdu, :version, 1) do
        # SNMPv1 - use error responses for missing objects
        0 ->
          has_errors =
            Enum.any?(variable_bindings, fn
              {_oid, :no_such_object, _} -> true
              # SNMPv1 treats end_of_mib as error too
              {_oid, :end_of_mib_view, _} -> true
              _ -> false
            end)

          if has_errors do
            error_response = PDU.create_error_response(pdu, @no_such_name, 1)
            {:ok, error_response}
          else
            create_get_response_with_fields(pdu, variable_bindings)
          end

        # SNMPv2c - use exception values in varbinds, no error response needed
        _ ->
          create_get_response_with_fields(pdu, variable_bindings)
      end
    catch
      :error, reason ->
        Logger.error("Error in GETBULK PDU processing: #{inspect(reason)}")
        Logger.error("PDU: #{inspect(pdu)}")
        error_response = PDU.create_error_response(pdu, @gen_err, 1)
        {:ok, error_response}
    end
  end

  def process_snmp_pdu(%{type: pdu_type} = pdu, _state)
       when pdu_type in [@set_request, :set_request, 0xA3] do
    # SET operations not supported in this phase
    error_response = PDU.create_error_response(pdu, @gen_err, 1)
    {:ok, error_response}
  end

  def process_snmp_pdu(pdu, _state) do
    # Unknown PDU type
    error_response = PDU.create_error_response(pdu, @gen_err, 0)
    {:ok, error_response}
  end

  def process_get_request(variable_bindings, state) do
    normalized_bindings =
      Enum.map(variable_bindings, fn
        # Extract OID from 3-tuple
        {oid, _type, _value} -> oid
        # Extract OID from 2-tuple
        {oid, _value} -> oid
      end)

    Enum.map(normalized_bindings, fn oid ->
      case get_oid_value(oid, state) do
        {:ok, value} ->
          # Convert value to 3-tuple format {oid, type, value}
          {type, actual_value} = extract_type_and_value(value)
          {oid, type, actual_value}

        {:error, :no_such_name} ->
          {oid, :no_such_object, {:no_such_object, nil}}
      end
    end)
  end

  def process_getnext_request(variable_bindings, state) do
    Enum.map(variable_bindings, fn varbind ->
      oid = extract_oid(varbind)

      oid_string =
        case oid do
          list when is_list(list) -> Enum.join(list, ".")
          str when is_binary(str) -> str
          _ -> raise "Invalid OID format"
        end

      try do
        case SharedProfiles.get_next_oid(state.device_type, oid_string) do
          {:ok, next_oid} ->
            device_state = build_device_state(state)

            case SharedProfiles.get_oid_value(state.device_type, next_oid, device_state) do
              {:ok, value} ->
                next_oid_list = string_to_oid_list(next_oid)
                {type, actual_value} = extract_type_and_value(value)
                {next_oid_list, type, actual_value}

              {:error, _} ->
                # If we can't get the value from SharedProfiles, use fallback
                get_fallback_next_oid(oid_string, state)
            end

          # Reached end of MIB tree
          :end_of_mib ->
            {oid, :end_of_mib_view, {:end_of_mib_view, nil}}

          # Alternative end of MIB format
          {:error, :end_of_mib} ->
            {oid, :end_of_mib_view, {:end_of_mib_view, nil}}

          # Device type not found in SharedProfiles, use fallback
          {:error, :device_type_not_found} ->
            get_fallback_next_oid(oid_string, state)

          # Any other error from SharedProfiles, use fallback
          {:error, _reason} ->
            get_fallback_next_oid(oid_string, state)
        end
      catch
        # SharedProfiles process not running, use fallback directly
        :exit, {:noproc, _} ->
          get_fallback_next_oid(oid_string, state)

        # SharedProfiles process crashed or other exit reason
        :exit, reason ->
          Logger.debug(
            "SharedProfiles unavailable (#{inspect(reason)}), using fallback for OID #{oid_string}"
          )

          # Handle 3-tuple format from fallback and ensure consistent format
          case get_fallback_next_oid(oid_string, state) do
            {next_oid_list, type, value} ->
              next_oid_str =
                if is_list(next_oid_list),
                  do: Enum.join(next_oid_list, "."),
                  else: next_oid_list

              {next_oid_str, type, value}
          end
      end
    end)
  end

  def process_getbulk_request(%{} = pdu, state) do
    # Extract SNMP GetBulk parameters from the PDU
    # non_repeaters: number of variables to get only once (not repeated)
    # max_repetitions: maximum number of repetitions for repeating variables
    non_repeaters = pdu.non_repeaters || 0
    max_repetitions = pdu.max_repetitions || 10

    # Get variable bindings from PDU (try both possible field names for compatibility)
    case Map.get(pdu, :varbinds, Map.get(pdu, :variable_bindings, [])) do
      # If no variables requested, return empty list
      [] ->
        []

      variable_bindings ->
        # PHASE 1: Split variables into non-repeaters and repeaters
        # Non-repeaters are processed once, repeaters are processed up to max_repetitions times
        {non_rep_vars, repeat_vars} = Enum.split(variable_bindings, non_repeaters)

        # PHASE 2: Process non-repeater variables (get next OID for each)
        non_rep_results =
          Enum.map(non_rep_vars, fn varbind ->
            # Extract OID from the variable binding
            oid = extract_oid(varbind)

            try do
              # Try to get the next OID using SharedProfiles (main MIB data source)
              case SharedProfiles.get_next_oid(state.device_type, oid) do
                {:ok, next_oid} ->
                  # Successfully got next OID, now get its value
                  device_state = build_device_state(state)

                  case SharedProfiles.get_oid_value(state.device_type, next_oid, device_state) do
                    {:ok, value} ->
                      # Convert next_oid string to list format for test compatibility
                      next_oid_list = string_to_oid_list(next_oid)
                      # Convert value to 3-tuple format {oid, type, value}
                      {type, actual_value} = extract_type_and_value(value)
                      {next_oid_list, type, actual_value}

                    {:error, _} ->
                      # If we can't get the value from SharedProfiles, use fallback
                      get_fallback_next_oid(oid, state)
                  end

                # Reached end of MIB tree
                :end_of_mib ->
                  {oid, :end_of_mib_view, {:end_of_mib_view, nil}}

                # Alternative end of MIB format
                {:error, :end_of_mib} ->
                  {oid, :end_of_mib_view, {:end_of_mib_view, nil}}

                # Device type not found in SharedProfiles, use fallback
                {:error, :device_type_not_found} ->
                  get_fallback_next_oid(oid, state)

                # Any other error from SharedProfiles, use fallback
                {:error, _reason} ->
                  get_fallback_next_oid(oid, state)
              end
            catch
              # SharedProfiles process not running, use fallback directly
              :exit, {:noproc, _} ->
                get_fallback_next_oid(oid, state)

              # SharedProfiles process crashed or other exit reason
              :exit, reason ->
                Logger.debug(
                  "SharedProfiles unavailable (#{inspect(reason)}), using fallback for OID #{oid}"
                )

                # Handle 3-tuple format from fallback and ensure consistent format
                case get_fallback_next_oid(oid, state) do
                  {next_oid_list, type, value} ->
                    # Convert OID list to string if needed for consistency
                    next_oid_str =
                      if is_list(next_oid_list),
                        do: Enum.join(next_oid_list, "."),
                        else: next_oid_list

                    {next_oid_str, type, value}
                end
            end
          end)

        # PHASE 3: Process repeating variables (bulk operation)
        bulk_results =
          case repeat_vars do
            # No repeating variables requested
            [] ->
              []

            # Process bulk request starting from first repeating variable
            [first_repeat | _] ->
              # Extract starting OID for bulk operation
              start_oid = extract_oid(first_repeat)

              try do
                # Try to get bulk OIDs using SharedProfiles
                case SharedProfiles.get_bulk_oids(state.device_type, start_oid, max_repetitions) do
                  {:ok, bulk_oids} when bulk_oids != [] ->
                    # Ensure all bulk_oids are in proper 3-tuple format {oid, type, value}
                    Enum.map(bulk_oids, fn
                      # Already in correct 3-tuple format
                      {oid, type, value} ->
                        {oid, type, value}

                      # 2-tuple format, assume octet_string type
                      {oid, value} ->
                        {oid, :octet_string, value}

                      # Pass through any other format unchanged
                      other ->
                        other
                    end)

                  {:ok, []} ->
                    # End of MIB reached - return single endOfMibView response
                    [{start_oid, :end_of_mib_view, nil}]

                  # Device type not found in SharedProfiles, use fallback bulk
                  {:error, :device_type_not_found} ->
                    # Convert OID to string format for fallback function
                    start_oid_string = case start_oid do
                      oid when is_list(oid) -> Enum.join(oid, ".")
                      oid when is_binary(oid) -> oid
                      _ -> to_string(start_oid)
                    end
                    
                    # Handle mixed format from fallback bulk function
                    case get_fallback_bulk_oids(start_oid_string, max_repetitions, state) do
                      bulk_list when is_list(bulk_list) ->
                        # Convert any inconsistent formats to proper 3-tuples
                        Enum.map(bulk_list, fn
                          # OID as list, already proper format
                          {oid_list, type, value} when is_list(oid_list) ->
                            {oid_list, type, value}

                          # OID as string or other format, proper 3-tuple
                          {oid, type, value} ->
                            {oid, type, value}

                          # 2-tuple format, assume octet_string type
                          {oid, value} ->
                            {oid, :octet_string, value}

                          # Pass through any other format unchanged
                          other ->
                            other
                        end)

                    end

                  # Any other error from SharedProfiles, return empty list
                  {:error, _reason} ->
                    []
                end
              catch
                # SharedProfiles process not running, use fallback bulk
                :exit, {:noproc, _} ->
                  # Convert OID to string format for fallback function
                  start_oid_string = case start_oid do
                    oid when is_list(oid) -> Enum.join(oid, ".")
                    oid when is_binary(oid) -> oid
                    _ -> to_string(start_oid)
                  end
                    
                  # Handle mixed format from fallback bulk function
                  case get_fallback_bulk_oids(start_oid_string, max_repetitions, state) do
                    bulk_list when is_list(bulk_list) ->
                      # Convert any inconsistent formats to proper 3-tuples
                      Enum.map(bulk_list, fn
                        # OID as list, already proper format
                        {oid_list, type, value} when is_list(oid_list) ->
                          {oid_list, type, value}

                        # OID as string or other format, proper 3-tuple
                        {oid, type, value} ->
                          {oid, type, value}

                        # 2-tuple format, assume octet_string type
                        {oid, value} ->
                          {oid, :octet_string, value}

                        # Pass through any other format unchanged
                        other ->
                          other
                      end)

                  end

                # SharedProfiles process crashed or other exit reason
                :exit, reason ->
                  Logger.debug(
                    "SharedProfiles unavailable (#{inspect(reason)}), using fallback for OID #{start_oid}"
                  )

                  # Convert OID to string format for fallback function
                  start_oid_string = case start_oid do
                    oid when is_list(oid) -> Enum.join(oid, ".")
                    oid when is_binary(oid) -> oid
                    _ -> to_string(start_oid)
                  end
                    
                  # Handle mixed format from fallback bulk function
                  case get_fallback_bulk_oids(start_oid_string, max_repetitions, state) do
                    bulk_list when is_list(bulk_list) ->
                      # Convert any inconsistent formats to proper 3-tuples
                      Enum.map(bulk_list, fn
                        # OID as list, already proper format
                        {oid_list, type, value} when is_list(oid_list) ->
                          {oid_list, type, value}

                        # OID as string or other format, proper 3-tuple
                        {oid, type, value} ->
                          {oid, type, value}

                        # 2-tuple format, assume octet_string type
                        {oid, value} ->
                          {oid, :octet_string, value}

                        # Pass through any other format unchanged
                        other ->
                          other
                      end)

                  end
              end
          end

        # PHASE 4: Combine non-repeater results with bulk results
        # Return the complete list of variable bindings for the GetBulk response
        non_rep_results ++ bulk_results
    end
  end

  def create_get_response_with_fields(pdu, variable_bindings) do
    # Convert to 3-tuple format expected by SnmpLib with list OIDs
    converted_bindings =
      Enum.map(variable_bindings, fn
        {oid, :end_of_mib_view, nil} ->
          oid_list =
            case oid do
              oid when is_list(oid) -> oid
              oid when is_binary(oid) -> string_to_oid_list(oid)
              _ -> oid
            end

          # 3-tuple with exception value
          result = {oid_list, :end_of_mib_view, {:end_of_mib_view, nil}}
          result

        {oid, :end_of_mib_view, _} ->
          oid_list =
            case oid do
              oid when is_list(oid) -> oid
              oid when is_binary(oid) -> string_to_oid_list(oid)
              _ -> oid
            end

          # 3-tuple with exception value
          result = {oid_list, :end_of_mib_view, {:end_of_mib_view, nil}}
          result

        {oid, :no_such_object, _} ->
          oid_list =
            case oid do
              oid when is_list(oid) -> oid
              oid when is_binary(oid) -> string_to_oid_list(oid)
              _ -> oid
            end

          # 3-tuple with exception value
          {oid_list, :no_such_object, {:no_such_object, nil}}

        {oid, type, value} ->
          oid_list =
            case oid do
              oid when is_list(oid) -> oid
              oid when is_binary(oid) -> string_to_oid_list(oid)
              _ -> oid
            end

          # Keep as 3-tuple with list OID
          result = {oid_list, type, value}
          result

        {oid, value} ->
          oid_list =
            case oid do
              oid when is_list(oid) -> oid
              oid when is_binary(oid) -> string_to_oid_list(oid)
              _ -> oid
            end

          # Convert 2-tuple to 3-tuple with list OID
          {oid_list, :unknown, value}

        # Pass through anything else
        other ->
          other
      end)

    # Create response format expected by tests (with :type and :varbinds fields)
    response_pdu = %{
      # TEST format uses :type
      type: :get_response,
      version: Map.get(pdu, :version, 1),
      community: Map.get(pdu, :community, "public"),
      request_id: Map.get(pdu, :request_id, 0),
      # TEST format uses :varbinds
      varbinds: converted_bindings,
      error_status: @no_error,
      error_index: 0
    }

    {:ok, response_pdu}
  end
end
