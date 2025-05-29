defmodule SnmpSimExTest do
  use ExUnit.Case, async: true
  doctest SnmpSimEx

  alias SnmpSimEx.ProfileLoader

  describe "Main Module API" do
    test "starts device with profile successfully" do
      # Create a simple manual profile for testing
      manual_profile = %{
        "1.3.6.1.2.1.1.1.0" => "Test Device Description",
        "1.3.6.1.2.1.1.2.0" => %{type: "OID", value: "1.3.6.1.4.1.9.1.1"},
        "1.3.6.1.2.1.2.1.0" => 2
      }
      
      {:ok, profile} = ProfileLoader.load_profile(
        :test_device,
        {:manual, manual_profile}
      )
      
      # Find a free port for testing
      {:ok, socket} = :gen_udp.open(0, [:binary])
      {:ok, port} = :inet.port(socket)
      :gen_udp.close(socket)
      
      # Start device
      {:ok, device_pid} = SnmpSimEx.start_device(profile, port: port)
      
      # Verify device started
      assert is_pid(device_pid)
      assert Process.alive?(device_pid)
      
      # Clean up
      GenServer.stop(device_pid)
    end

    test "start_device_population creates multiple devices" do
      device_configs = [
        {:test_device1, {:manual, %{"1.3.6.1.2.1.1.1.0" => "Device 1"}}, count: 2},
        {:test_device2, {:manual, %{"1.3.6.1.2.1.1.1.0" => "Device 2"}}, count: 1}
      ]
      
      # Find a range of free ports
      {:ok, socket} = :gen_udp.open(0, [:binary])
      {:ok, start_port} = :inet.port(socket)
      :gen_udp.close(socket)
      
      port_range = start_port..(start_port + 2)
      
      {:ok, devices} = SnmpSimEx.start_device_population(
        device_configs,
        port_range: port_range
      )
      
      # Should have 3 devices total
      assert map_size(devices) == 3
      
      # All should be valid PIDs
      Enum.each(devices, fn {_info, pid} ->
        assert is_pid(pid)
        assert Process.alive?(pid)
      end)
      
      # Clean up
      Enum.each(devices, fn {_info, pid} ->
        GenServer.stop(pid)
      end)
    end

    test "handles errors gracefully" do
      # Test with invalid profile source
      result = SnmpSimEx.start_device_population([
        {:bad_device, {:walk_file, "non_existent_file.walk"}, count: 1}
      ], port_range: 9001..9001)
      
      assert {:error, _reason} = result
    end
  end

  describe "Module Documentation" do
    test "has proper module documentation" do
      {:docs_v1, _annotation, _beam_language, _format, module_doc, _metadata, _docs} = 
        Code.fetch_docs(SnmpSimEx)
      
      assert module_doc != :hidden
      assert module_doc != :none
    end
  end
end
