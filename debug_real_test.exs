defmodule DebugRealTest do
  use ExUnit.Case, async: false

  alias SNMPSimEx.MIB.SharedProfiles
  alias SNMPSimEx.Device

  test "mimic exact integration test setup" do
    # Mimic the exact setup from the integration test

    # 1. First, check if SharedProfiles is running 
    IO.puts("=== Initial SharedProfiles status ===")
    case GenServer.whereis(SharedProfiles) do
      nil -> IO.puts("SharedProfiles NOT running")
      pid -> IO.puts("SharedProfiles running at #{inspect(pid)}")
    end

    # 2. Try to load walk profile WITHOUT starting SharedProfiles first (like the test does)
    IO.puts("\n=== Attempting to load walk profile without starting SharedProfiles ===")
    result1 = try do
      SharedProfiles.load_walk_profile(:cable_modem, "priv/walks/cable_modem.walk")
    catch
      :exit, reason -> {:caught_exit, reason}
    end
    IO.puts("Result: #{inspect(result1)}")

    # 3. Now properly start SharedProfiles like our working test
    IO.puts("\n=== Starting SharedProfiles properly ===")
    case GenServer.whereis(SharedProfiles) do
      nil ->
        {:ok, _} = SharedProfiles.start_link()
        :ok = SharedProfiles.init_profiles()
        IO.puts("SharedProfiles started")
      _ ->
        IO.puts("SharedProfiles already running")
    end

    # 4. Load walk profile again
    IO.puts("\n=== Loading walk profile with SharedProfiles running ===")
    result2 = SharedProfiles.load_walk_profile(:cable_modem, "priv/walks/cable_modem.walk")
    IO.puts("Result: #{inspect(result2)}")

    # 5. Test device creation and OID retrieval
    IO.puts("\n=== Testing device creation ===")
    device_config = %{
      port: 9999,
      device_type: :cable_modem,
      device_id: "test_cable_modem",
      community: "public"
    }

    {:ok, device} = Device.start_link(device_config)
    IO.puts("Device started")

    # 6. Test direct OID access
    IO.puts("\n=== Testing direct OID access ===")
    result3 = Device.get(device, "1.3.6.1.2.1.1.1.0")
    IO.puts("Device.get result: #{inspect(result3)}")

    # Cleanup
    Device.stop(device)

    assert result2 == :ok
  end
end