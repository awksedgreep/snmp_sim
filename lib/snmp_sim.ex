defmodule SnmpSim do
  @moduledoc """
  SNMP Simulator for Elixir - Production-ready SNMP device simulation.

  Provides high-performance SNMP device simulation supporting walk files,
  realistic behaviors, and large-scale testing scenarios.
  """

  alias SnmpSim.{Device, LazyDevicePool}

  @doc """
  Start a single SNMP device with the given profile.

  ## Examples

      # Start device with walk file profile
      profile = SnmpSim.ProfileLoader.load_profile(
        :cable_modem, 
        {:walk_file, "priv/walks/cable_modem.walk"}
      )
      {:ok, device} = SnmpSim.start_device(profile, port: 9001)
      
  """
  def start_device(profile, opts \\ []) do
    port = Keyword.fetch!(opts, :port)
    device_type = profile.device_type
    device_id = Keyword.get(opts, :device_id, "#{device_type}_#{port}")

    device_config = %{
      port: port,
      device_type: device_type,
      device_id: device_id,
      profile: profile,
      community: Keyword.get(opts, :community, "public")
    }

    Device.start_link(device_config)
  end

  @doc """
  Start a population of devices with mixed types and configurations.

  ## Examples

      device_configs = [
        {:cable_modem, {:walk_file, "priv/walks/cm.walk"}, count: 1000},
        {:switch, {:oid_walk, "priv/walks/switch.walk"}, count: 50}
      ]
      
      {:ok, devices} = SnmpSim.start_device_population(
        device_configs, 
        port_range: 30_000..39_999
      )
      
  """
  def start_device_population(device_configs, opts \\ []) do
    LazyDevicePool.start_device_population(device_configs, opts)
  end

  def start(_type, _args) do
    # Get port from configuration, default to 1161 for tests if not set
    port = Application.get_env(:snmp_ex, :port, 1161)
    
    # Start SNMP with configured port
    children = [
      {SNMP, [
        port: port
      ]}
    ]

    opts = [strategy: :one_for_one, name: SnmpSim.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
