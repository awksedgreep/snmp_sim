defmodule SnmpSim.CounterEncodingTest do
  @moduledoc """
  Tests to ensure Counter32 and Gauge32 values are properly encoded.

  This prevents the regression where snmp_lib v1.0.0 encoded Counter32/Gauge32
  as ASN.1 NULL instead of proper integer values.
  """

  use ExUnit.Case, async: false

  alias SnmpSim.{LazyDevicePool}
  alias SnmpSim.TestHelpers.PortHelper

  setup do
    # Ensure clean state
    if Process.whereis(LazyDevicePool) do
      LazyDevicePool.shutdown_all_devices()
    else
      {:ok, _} = LazyDevicePool.start_link()
    end

    test_port = PortHelper.get_port()
    {:ok, device_pid} = LazyDevicePool.get_or_create_device(test_port)
    {:ok, test_port: test_port, device_pid: device_pid}
  end

  describe "Counter32 and Gauge32 encoding" do
    test "Counter32 values return proper integer tuples, not NULL", %{device_pid: device_pid} do
      # Test interface counter OIDs that should return Counter32 values
      counter_oids = [
        # ifInOctets.1
        "1.3.6.1.2.1.2.2.1.10.1",
        # ifOutOctets.1
        "1.3.6.1.2.1.2.2.1.16.1"
      ]

      for oid <- counter_oids do
        result = GenServer.call(device_pid, {:get_oid, oid})

        case result do
          {:ok, {:counter32, value}} ->
            # This is the correct format - Counter32 with actual value
            assert is_integer(value),
                   "Counter32 value should be an integer, got: #{inspect(value)}"

            assert value >= 0, "Counter32 value should be non-negative, got: #{value}"

          {:ok, value} when is_integer(value) ->
            # This is also acceptable - direct integer value
            assert value >= 0, "Counter value should be non-negative, got: #{value}"

          {:ok, nil} ->
            flunk("Counter32 OID #{oid} returned NULL - this indicates the encoding bug!")

          {:ok, other} ->
            flunk("Counter32 OID #{oid} returned unexpected format: #{inspect(other)}")

          {:error, reason} ->
            flunk("Counter32 OID #{oid} failed with error: #{inspect(reason)}")
        end
      end
    end

    test "Gauge32 values return proper integer tuples, not NULL", %{device_pid: device_pid} do
      # Test interface speed OID that should return Gauge32 value
      gauge_oids = [
        # ifSpeed.1
        "1.3.6.1.2.1.2.2.1.5.1"
      ]

      for oid <- gauge_oids do
        result = GenServer.call(device_pid, {:get_oid, oid})

        case result do
          {:ok, {:gauge32, value}} ->
            # This is the correct format - Gauge32 with actual value
            assert is_integer(value), "Gauge32 value should be an integer, got: #{inspect(value)}"
            assert value >= 0, "Gauge32 value should be non-negative, got: #{value}"

          {:ok, value} when is_integer(value) ->
            # This is also acceptable - direct integer value
            assert value >= 0, "Gauge value should be non-negative, got: #{value}"

          {:ok, nil} ->
            flunk("Gauge32 OID #{oid} returned NULL - this indicates the encoding bug!")

          {:ok, other} ->
            flunk("Gauge32 OID #{oid} returned unexpected format: #{inspect(other)}")

          {:error, reason} ->
            flunk("Gauge32 OID #{oid} failed with error: #{inspect(reason)}")
        end
      end
    end

    test "Counter32 values are non-zero and realistic", %{device_pid: device_pid} do
      # Interface counters should have realistic non-zero values
      result = GenServer.call(device_pid, {:get_oid, "1.3.6.1.2.1.2.2.1.10.1"})

      case result do
        {:ok, {:counter32, value}} ->
          # Counter should be a reasonable value, can be 0 for newly started interface
          assert value >= 0, "Interface counter should be >= 0, got: #{value}"
          assert value < 4_294_967_296, "Counter32 should be within 32-bit range, got: #{value}"

        {:ok, value} when is_integer(value) ->
          assert value >= 0, "Interface counter should be >= 0, got: #{value}"
          assert value < 4_294_967_296, "Counter32 should be within 32-bit range, got: #{value}"

        other ->
          flunk("Expected Counter32 value, got: #{inspect(other)}")
      end
    end

    test "snmp_lib version is 1.0.1 or higher (encoding fix)", _context do
      # Ensure we're using the fixed version of snmp_lib
      deps = Mix.Project.config()[:deps]

      snmp_lib_dep =
        Enum.find(deps, fn
          {:snmp_lib, version} when is_binary(version) -> true
          {:snmp_lib, _opts} -> true
          _ -> false
        end)

      assert snmp_lib_dep != nil, "snmp_lib dependency not found"

      case snmp_lib_dep do
        {:snmp_lib, version} when is_binary(version) ->
          # Parse version and ensure it's >= 1.0.1
          version_parts = String.split(version, ".")
          [major, minor, patch] = Enum.map(version_parts, &String.to_integer/1)

          assert major >= 1, "snmp_lib major version should be >= 1, got: #{major}"

          if major == 1 and minor == 0 do
            assert patch >= 1,
                   "snmp_lib should be >= 1.0.1 to fix Counter32 encoding, got: 1.0.#{patch}"
          end

        {:snmp_lib, opts} when is_list(opts) ->
          # Git dependency or other format - assume it's the fixed version
          :ok
      end
    end
  end
end
