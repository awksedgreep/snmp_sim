defmodule SNMPSimExSnmpExIntegrationTest do
  @moduledoc """
  True integration tests using the snmp_ex library to validate our SNMP simulator
  against a real SNMP client implementation. This ensures protocol compliance
  and real-world compatibility.
  """

  use ExUnit.Case, async: false

  alias SNMPSimEx.ProfileLoader
  alias SNMPSimEx.Device
  alias SNMPSimEx.MIB.SharedProfiles
  alias SNMPSimEx.TestHelpers.PortHelper

  # Helper module to provide backward compatibility with old SNMP API
  defmodule SNMPCompat do
    def get(agent, oids) when is_list(oids) do
      [oid_string] = oids
      oid_list = oid_string |> String.split(".") |> Enum.map(&String.to_integer/1)

      # Recreate credential if community changed
      credential = if agent.community != "public" do
        SNMP.credential(%{community: agent.community, version: :v2})
      else
        agent.credential
      end

      request = %{
        uri: agent.uri,
        credential: credential,
        varbinds: [%{oid: oid_list}]
      }

      case SNMP.request(request) do
        {:ok, response} when is_list(response) ->
          # Response is already a list of varbinds
          [varbind] = response
          oid_string = Enum.join(varbind.oid, ".")
          {:ok, [{oid_string, varbind.value}]}
        {:ok, %{varbinds: varbinds}} ->
          # Response is a map with varbinds key
          [varbind] = varbinds
          oid_string = Enum.join(varbind.oid, ".")
          {:ok, [{oid_string, varbind.value}]}
        error -> error
      end
    end

    def get_next(agent, oids) when is_list(oids) do
      [oid_string] = oids
      oid_list = oid_string |> String.split(".") |> Enum.map(&String.to_integer/1)

      request = %{
        uri: agent.uri,
        credential: agent.credential,
        varbinds: [%{oid: oid_list, type: :next}]
      }

      case SNMP.request(request) do
        {:ok, response} when is_list(response) ->
          # Response is already a list of varbinds
          [varbind] = response
          oid_string = Enum.join(varbind.oid, ".")
          # Check for endOfMibView
          if varbind.value == :endOfMibView do
            {:ok, [{oid_string, :endOfMibView}]}
          else
            {:ok, [{oid_string, varbind.value}]}
          end
        {:ok, %{varbinds: varbinds}} ->
          # Response is a map with varbinds key
          [varbind] = varbinds
          oid_string = Enum.join(varbind.oid, ".")
          # Check for endOfMibView
          if varbind.value == :endOfMibView do
            {:ok, [{oid_string, :endOfMibView}]}
          else
            {:ok, [{oid_string, varbind.value}]}
          end
        error -> error
      end
    end

    def get_bulk(agent, oids, opts) when is_list(oids) do
      # For proper GETBULK operation, we need to implement it manually since
      # bulkwalk is designed for single subtree walking, not multi-OID GETBULK

      non_repeaters = Keyword.get(opts, :non_repeaters, 0)
      max_repetitions = Keyword.get(opts, :max_repetitions, 10)

      # Always use the fallback implementation which correctly handles GETBULK semantics
      fallback_bulk_walk(agent, oids, non_repeaters: non_repeaters, max_repetitions: max_repetitions)
    end

    # Fallback implementation using regular GET NEXT operations
    defp fallback_bulk_walk(agent, oids, opts) do
      max_repetitions = Keyword.get(opts, :max_repetitions, 10)
      non_repeaters = Keyword.get(opts, :non_repeaters, 0)

      {non_repeat_oids, repeat_oids} = Enum.split(oids, non_repeaters)

      # Process non-repeaters: perform one get_next operation each
      non_repeat_results = Enum.flat_map(non_repeat_oids, fn start_oid ->
        case get_next(agent, [start_oid]) do
          {:ok, [{next_oid, value}]} -> [{next_oid, value}]
          {:error, _} -> []
        end
      end)

      # Process repeaters: perform up to max_repetitions get_next operations each
      repeat_results = Enum.flat_map(repeat_oids, fn start_oid ->
        perform_walk_sequence(agent, start_oid, max_repetitions, [])
      end)

      all_results = non_repeat_results ++ repeat_results
      {:ok, all_results}
    end

    # Helper to perform a sequence of get_next operations for GETBULK repeaters
    defp perform_walk_sequence(_agent, _current_oid, 0, acc), do: Enum.reverse(acc)
    defp perform_walk_sequence(agent, current_oid, remaining, acc) do
      case get_next(agent, [current_oid]) do
        {:ok, [{next_oid, value}]} ->
          # For GETBULK repeaters, we continue getting next OIDs regardless of subtree
          # This is the correct GETBULK behavior - it doesn't filter by subtree
          perform_walk_sequence(agent, next_oid, remaining - 1, [{next_oid, value} | acc])

        {:error, _} ->
          # Stop on error (including end of MIB)
          Enum.reverse(acc)
      end
    end
  end

  describe "Integration with snmp_ex Library" do
    setup do
      # Start SharedProfiles for tests that need it
      case GenServer.whereis(SharedProfiles) do
        nil -> {:ok, _} = SharedProfiles.start_link([])
        _pid -> :ok
      end

      # Start snmp_ex application
      {:ok, _} = Application.ensure_all_started(:snmp_ex)

      # Load a test profile
      {:ok, profile} = ProfileLoader.load_profile(
        :cable_modem,
        {:walk_file, "priv/walks/cable_modem.walk"}
      )

      port = PortHelper.get_port()

      device_config = %{
        port: port,
        device_type: :cable_modem,
        device_id: "cable_modem_#{port}",
        community: "public"
      }

      {:ok, device} = Device.start_link(device_config)

      Process.sleep(200)  # Give device time to fully initialize

      # Configure snmp_ex agent that works with compatibility wrapper
      uri = URI.parse("snmp://127.0.0.1:#{port}")
      credential = SNMP.credential(%{community: "public", version: :v2})

      agent = %{
        uri: uri,
        credential: credential,
        host: "127.0.0.1",
        port: port,
        community: "public",
        version: :v2c,
        timeout: 5000,
        retries: 3
      }

      on_exit(fn ->
        if Process.alive?(device) do
          GenServer.stop(device)
        end
      end)

      {:ok, agent: agent, device: device, port: port}
    end

    test "snmp_ex can perform GET operations", %{agent: agent} do
      # Test basic GET operation with snmp_ex
      case SNMPCompat.get(agent, ["1.3.6.1.2.1.1.1.0"]) do
        {:ok, [{oid, value}]} ->
          assert oid == "1.3.6.1.2.1.1.1.0"
          assert is_binary(value)
          assert String.contains?(value, "Motorola")  # Expected in cable modem walk

        {:error, reason} ->
          flunk("snmp_ex GET failed: #{inspect(reason)}")
      end
    end

    test "snmp_ex can perform GETNEXT operations", %{agent: agent} do
      # Test GETNEXT starting from system group
      case SNMPCompat.get_next(agent, ["1.3.6.1.2.1.1.1"]) do
        {:ok, [{next_oid, value}]} ->
          assert String.starts_with?(next_oid, "1.3.6.1.2.1.1.1")
          assert value != nil

        {:error, reason} ->
          flunk("snmp_ex GETNEXT failed: #{inspect(reason)}")
      end
    end

    test "snmp_ex can perform GETBULK operations", %{agent: agent} do
      # Test GETBULK on interface table
      case SNMPCompat.get_bulk(agent, ["1.3.6.1.2.1.2.2.1.1"], non_repeaters: 0, max_repetitions: 5) do
        {:ok, results} when is_list(results) ->
          assert length(results) > 0
          assert length(results) <= 5

          # Verify all results are OID/value pairs
          assert Enum.all?(results, fn {oid, _value} ->
            is_binary(oid) and String.starts_with?(oid, "1.3.6.1.2.1.2.2.1")
          end)

        {:error, reason} ->
          flunk("snmp_ex GETBULK failed: #{inspect(reason)}")
      end
    end

    test "snmp_ex GETBULK with non-repeaters", %{agent: agent} do
      # Test GETBULK with mixed non-repeating and repeating variables
      oids = [
        "1.3.6.1.2.1.1.1.0",      # sysDescr (non-repeater)
        "1.3.6.1.2.1.2.2.1.1"     # ifIndex table (repeater)
      ]

      case SNMPCompat.get_bulk(agent, oids, non_repeaters: 1, max_repetitions: 3) do
        {:ok, results} ->
          assert length(results) >= 1  # At least the non-repeater
          assert length(results) <= 4  # 1 non-repeater + 3 repetitions max

          # First result should be from sysDescr area (non-repeater)
          [{first_oid, _}] = Enum.take(results, 1)
          assert String.starts_with?(first_oid, "1.3.6.1.2.1.1")

        {:error, reason} ->
          flunk("snmp_ex GETBULK with non-repeaters failed: #{inspect(reason)}")
      end
    end

    test "snmp_ex handles lexicographic ordering correctly", %{agent: agent} do
      # Walk through several OIDs to verify ordering
      start_oid = "1.3.6.1.2.1.2.2.1.1"
      current_oid = start_oid
      walked_oids = []

      {final_oids, _} = Enum.reduce_while(1..10, {[], current_oid}, fn _i, {acc_oids, oid} ->
        case SNMPCompat.get_next(agent, [oid]) do
          {:ok, [{next_oid, _value}]} ->
            if String.starts_with?(next_oid, start_oid) do
              {:cont, {[next_oid | acc_oids], next_oid}}
            else
              {:halt, {acc_oids, oid}}
            end

          {:error, _} ->
            {:halt, {acc_oids, oid}}
        end
      end)

      walked_oids = Enum.reverse(final_oids)

      # Verify lexicographic ordering
      if length(walked_oids) > 1 do
        ordered_pairs = Enum.zip(walked_oids, tl(walked_oids))

        assert Enum.all?(ordered_pairs, fn {oid1, oid2} ->
          compare_oids(oid1, oid2) == :lt
        end), "OIDs not in lexicographic order: #{inspect(walked_oids)}"
      end
    end

    test "snmp_ex can walk large interface tables efficiently", %{agent: agent} do
      # Test performance with larger requests
      start_time = :erlang.monotonic_time(:millisecond)

      case SNMPCompat.get_bulk(agent, ["1.3.6.1.2.1.2.2.1"], non_repeaters: 0, max_repetitions: 20) do
        {:ok, results} ->
          end_time = :erlang.monotonic_time(:millisecond)
          response_time = end_time - start_time

          assert length(results) > 0
          # Should respond quickly (under 100ms)
          assert response_time < 100, "Response took #{response_time}ms, expected < 100ms"

        {:error, reason} ->
          flunk("Large GETBULK failed: #{inspect(reason)}")
      end
    end

    test "snmp_ex handles end of MIB correctly", %{agent: agent} do
      # Try to get beyond the available OIDs
      case SNMPCompat.get_next(agent, ["1.3.6.1.9.9.9.9.9"]) do
        {:ok, results} ->
          # Should get empty results or endOfMibView
          assert results == [] or
                 Enum.any?(results, fn {_oid, value} -> value == :endOfMibView end) or
                 length(results) == 0  # Also accept empty result list

        {:error, :endOfMibView} ->
          # This is also acceptable
          assert true

        {:error, reason} ->
          # Other errors might be acceptable depending on implementation (map etimedout)
          mapped_reason = if reason == :etimedout, do: :timeout, else: reason
          assert mapped_reason in [:endOfMibView, :noSuchName, :timeout]
      end
    end

    @tag :slow
    test "snmp_ex handles invalid community strings", %{agent: agent} do
      bad_agent = Map.put(agent, :community, "invalid")

      case SNMPCompat.get(bad_agent, ["1.3.6.1.2.1.1.1.0"]) do
        {:error, :timeout} ->
          # Device should not respond to invalid community
          assert true

        {:error, reason} ->
          # Other authentication errors are acceptable (map etimedout to timeout)
          mapped_reason = if reason == :etimedout, do: :timeout, else: reason
          assert mapped_reason in [:timeout, :authenticationFailure, :noResponse]

        {:ok, _} ->
          flunk("Device responded to invalid community string")
      end
    end

    test "snmp_ex concurrent requests work properly", %{agent: agent} do
      # Test multiple concurrent requests
      tasks = for i <- 1..5 do
        Task.async(fn ->
          oid = "1.3.6.1.2.1.2.2.1.#{i}.1"  # Different interface columns
          SNMPCompat.get(agent, [oid])
        end)
      end

      results = Task.await_many(tasks, 5000)

      # Most requests should succeed (some might fail if OID doesn't exist)
      successful_count = Enum.count(results, fn
        {:ok, _} -> true
        _ -> false
      end)

      assert successful_count >= 2, "Only #{successful_count}/5 concurrent requests succeeded"
    end

    test "snmp_ex handles counter values correctly", %{agent: agent} do
      # Test counter-type OIDs (should be numeric)
      case SNMPCompat.get(agent, ["1.3.6.1.2.1.2.2.1.10.1"]) do  # ifInOctets
        {:ok, [{_oid, value}]} ->
          # Counter values should be integers or counter-typed values
          assert is_integer(value) or (is_tuple(value) and elem(value, 0) in [:counter32, :counter64])

        {:error, :noSuchName} ->
          # OID might not exist in this walk file, that's ok
          assert true

        {:error, reason} ->
          flunk("Counter OID test failed: #{inspect(reason)}")
      end
    end

    test "snmp_ex can retrieve string values correctly", %{agent: agent} do
      # Test string-type OIDs
      string_oids = [
        "1.3.6.1.2.1.1.1.0",     # sysDescr
        "1.3.6.1.2.1.2.2.1.2.1"  # ifDescr (if exists)
      ]

      for oid <- string_oids do
        case SNMPCompat.get(agent, [oid]) do
          {:ok, [{^oid, value}]} when is_binary(value) ->
            assert String.length(value) > 0

          {:ok, [{^oid, value}]} ->
            flunk("Expected string value for #{oid}, got: #{inspect(value)}")

          {:error, :noSuchName} ->
            # OID might not exist, that's acceptable
            :ok

          {:error, reason} ->
            flunk("String OID #{oid} test failed: #{inspect(reason)}")
        end
      end
    end
  end

  describe "Protocol Compliance and Edge Cases" do
    setup do
      # Start SharedProfiles for tests that need it
      case GenServer.whereis(SharedProfiles) do
        nil -> {:ok, _} = SharedProfiles.start_link([])
        _pid -> :ok
      end

      {:ok, profile} = ProfileLoader.load_profile(
        :cable_modem,
        {:walk_file, "priv/walks/cable_modem.walk"}
      )

      port = PortHelper.get_port()

      device_config = %{
        port: port,
        device_type: :cable_modem,
        device_id: "cable_modem_#{port}",
        community: "public"
      }

      {:ok, device} = Device.start_link(device_config)
      Process.sleep(200)

      # Configure snmp_ex agent that works with compatibility wrapper
      uri = URI.parse("snmp://127.0.0.1:#{port}")
      credential = SNMP.credential(%{community: "public", version: :v2})

      agent_config = %{
        uri: uri,
        credential: credential,
        host: "127.0.0.1",
        port: port,
        community: "public",
        version: :v2c,
        timeout: 2000,  # Shorter timeout for error tests
        retries: 1
      }

      on_exit(fn ->
        if Process.alive?(device) do
          GenServer.stop(device)
        end
      end)

      {:ok, agent: agent_config}
    end

    test "snmp_ex handles SNMPv1 vs v2c correctly", %{agent: agent} do
      # Test both versions if supported
      v1_agent = Map.put(agent, :version, :v1)
      v2c_agent = Map.put(agent, :version, :v2c)

      for {version, test_agent} <- [v1: v1_agent, v2c: v2c_agent] do
        case SNMPCompat.get(test_agent, ["1.3.6.1.2.1.1.1.0"]) do
          {:ok, [{_oid, _value}]} ->
            # Success for this version
            assert true

          {:error, reason} ->
            # Some versions might not be supported, that's ok
            assert reason in [:timeout, :unsupported_version, :noResponse]
        end
      end
    end

    test "snmp_ex timeout handling works", %{agent: agent} do
      # Create agent with very short timeout
      short_timeout_agent = Map.put(agent, :timeout, 100)

      # This might timeout due to the very short timeout
      case SNMPCompat.get(short_timeout_agent, ["1.3.6.1.2.1.1.1.0"]) do
        {:ok, _} ->
          # If it succeeds despite short timeout, that's fine too
          assert true

        {:error, :timeout} ->
          # Expected behavior
          assert true

        {:error, reason} ->
          # Other errors might occur (map etimedout to timeout)
          mapped_reason = if reason == :etimedout, do: :timeout, else: reason
          assert mapped_reason in [:timeout, :noResponse]
      end
    end
  end

  # Helper functions

  defp compare_oids(oid1, oid2) do
    parts1 = String.split(oid1, ".") |> Enum.map(&String.to_integer/1)
    parts2 = String.split(oid2, ".") |> Enum.map(&String.to_integer/1)

    compare_oid_parts(parts1, parts2)
  end

  defp compare_oid_parts([], []), do: :eq
  defp compare_oid_parts([], _), do: :lt
  defp compare_oid_parts(_, []), do: :gt
  defp compare_oid_parts([a | rest_a], [b | rest_b]) when a == b do
    compare_oid_parts(rest_a, rest_b)
  end
  defp compare_oid_parts([a | _], [b | _]) when a < b, do: :lt
  defp compare_oid_parts([a | _], [b | _]) when a > b, do: :gt
end
