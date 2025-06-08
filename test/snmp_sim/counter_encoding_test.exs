defmodule SnmpSim.CounterEncodingTest do
  @moduledoc """
  Tests to ensure Counter32 and Gauge32 values are properly encoded.

  This prevents the regression where snmp_lib v1.0.0 encoded Counter32/Gauge32
  as ASN.1 NULL instead of proper integer values.
  """

  use ExUnit.Case, async: false

  alias SnmpSim.{LazyDevicePool, Device}
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
    {:ok, device: Device.new(device_pid), test_port: test_port, device_pid: device_pid}
  end

  describe "Counter32 and Gauge32 encoding" do
    test "Counter32 values return proper integer tuples, not NULL", %{device: device} do
      # Test interface counter OIDs that should return Counter32 values
      counter_oids = [
        # ifInOctets.1
        "1.3.6.1.2.1.2.2.1.10.1",
        # ifOutOctets.1
        "1.3.6.1.2.1.2.2.1.16.1"
      ]

      for oid <- counter_oids do
        case Device.get(device, oid) do
          {:ok, {^oid, :counter32, value}} ->
            assert is_integer(value), "Counter32 OID #{oid} should return integer value, got: #{inspect(value)}"
            assert value >= 0, "Counter32 OID #{oid} value should be non-negative, got: #{value}"
          {:error, reason} ->
            flunk("Counter32 OID #{oid} failed with error: #{inspect(reason)}")
          other ->
            flunk("Counter32 OID #{oid} returned unexpected format: #{inspect(other)}")
        end
      end
    end

    test "Gauge32 values return proper integer tuples, not NULL", %{device: device} do
      # Test interface speed OID that should return Gauge32 value
      gauge_oids = [
        # ifSpeed.1
        "1.3.6.1.2.1.2.2.1.5.1"
      ]

      for oid <- gauge_oids do
        case Device.get(device, oid) do
          {:ok, {^oid, :gauge32, value}} ->
            assert is_integer(value), "Gauge32 OID #{oid} should return integer value, got: #{inspect(value)}"
            assert value >= 0, "Gauge32 OID #{oid} value should be non-negative, got: #{value}"
          {:error, reason} ->
            flunk("Gauge32 OID #{oid} failed with error: #{inspect(reason)}")
          other ->
            flunk("Gauge32 OID #{oid} returned unexpected format: #{inspect(other)}")
        end
      end
    end

    test "Counter32 values are non-zero and realistic", %{device: device} do
      # Interface counters should have realistic non-zero values
      result = Device.get(device, "1.3.6.1.2.1.2.2.1.10.1")

      case result do
        {:ok, {oid, :counter32, value}} ->
          assert oid == "1.3.6.1.2.1.2.2.1.10.1", "OID should match, got: #{oid}"
          assert value > 0, "Counter32 value should be greater than 0, got: #{value}"
          assert value < 4_294_967_296, "Counter32 value should be less than 2^32, got: #{value}"
        {:error, reason} ->
          flunk("Expected Counter32 value, got error: #{inspect(reason)}")
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
