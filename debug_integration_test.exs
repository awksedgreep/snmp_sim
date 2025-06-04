defmodule DebugIntegrationTest do
  use ExUnit.Case, async: false

  alias SNMPSimEx.MIB.SharedProfiles

  @moduledoc """
  Debug integration test to understand why SharedProfiles isn't working
  """

  test "debug SharedProfiles walk file loading" do
    # Start SharedProfiles if not already started
    case GenServer.whereis(SharedProfiles) do
      nil ->
        {:ok, _} = SharedProfiles.start_link()
        :ok = SharedProfiles.init_profiles()
      _ ->
        :ok
    end

    # Load walk profile
    result = SharedProfiles.load_walk_profile(
      :cable_modem,
      "priv/walks/cable_modem.walk"
    )
    
    IO.puts("=== Walk profile load result ===")
    IO.puts("Result: #{inspect(result)}")
    
    # Test getting a value
    device_state = %{device_id: "test", uptime: 3600}
    test_oid = "1.3.6.1.2.1.1.1.0"
    
    result = SharedProfiles.get_oid_value(:cable_modem, test_oid, device_state)
    IO.puts("\n=== get_oid_value result ===")
    IO.puts("OID: #{test_oid}")
    IO.puts("Result: #{inspect(result)}")
    
    # List profiles
    profiles = SharedProfiles.list_profiles()
    IO.puts("\n=== Available profiles ===")
    IO.puts("Profiles: #{inspect(profiles)}")
    
    # Get memory stats
    stats = SharedProfiles.get_memory_stats()
    IO.puts("\n=== Memory stats ===")
    IO.puts("Stats: #{inspect(stats)}")

    assert result == :ok || match?({:ok, _}, result)
  end
end