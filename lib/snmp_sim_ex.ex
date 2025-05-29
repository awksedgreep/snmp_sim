defmodule SnmpSimEx do
  @moduledoc """
  SNMP Simulator for Elixir - Production-ready SNMP device simulation.
  
  Provides high-performance SNMP device simulation supporting walk files,
  realistic behaviors, and large-scale testing scenarios.
  """

  alias SnmpSimEx.{ProfileLoader, Device, LazyDevicePool}

  @doc """
  Start a single SNMP device with the given profile.
  
  ## Examples
  
      # Start device with walk file profile
      profile = SnmpSimEx.ProfileLoader.load_profile(
        :cable_modem, 
        {:walk_file, "priv/walks/cable_modem.walk"}
      )
      {:ok, device} = SnmpSimEx.start_device(profile, port: 9001)
      
  """
  def start_device(profile, opts \\ []) do
    Device.start_link(profile, opts)
  end

  @doc """
  Start a population of devices with mixed types and configurations.
  
  ## Examples
  
      device_configs = [
        {:cable_modem, {:walk_file, "priv/walks/cm.walk"}, count: 1000},
        {:switch, {:oid_walk, "priv/walks/switch.walk"}, count: 50}
      ]
      
      {:ok, devices} = SnmpSimEx.start_device_population(
        device_configs, 
        port_range: 30_000..39_999
      )
      
  """
  def start_device_population(device_configs, opts \\ []) do
    LazyDevicePool.start_device_population(device_configs, opts)
  end
end
