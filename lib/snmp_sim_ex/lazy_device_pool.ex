defmodule SnmpSimEx.LazyDevicePool do
  @moduledoc """
  Basic device pool management for Phase 1.
  Simplified version that starts devices immediately.
  Full lazy creation will be implemented in Phase 4.
  """

  alias SnmpSimEx.{ProfileLoader, Device}
  require Logger

  @doc """
  Start a population of devices with the given configurations.
  
  ## Examples
  
      device_configs = [
        {:cable_modem, {:walk_file, "priv/walks/cm.walk"}, count: 10},
        {:switch, {:oid_walk, "priv/walks/switch.walk"}, count: 5}
      ]
      
      {:ok, devices} = SnmpSimEx.LazyDevicePool.start_device_population(
        device_configs,
        port_range: 9001..9020
      )
      
  """
  def start_device_population(device_configs, opts \\ []) do
    port_range = Keyword.get(opts, :port_range, 9001..9100)
    community = Keyword.get(opts, :community, "public")
    
    # Calculate total device count
    total_devices = Enum.sum(Enum.map(device_configs, fn {_type, _source, opts} ->
      Keyword.get(opts, :count, 1)
    end))
    
    # Check if we have enough ports
    available_ports = Enum.count(port_range)
    if total_devices > available_ports do
      {:error, {:insufficient_ports, total_devices, available_ports}}
    else
      start_devices(device_configs, port_range, community)
    end
  end

  # Private functions

  defp start_devices(device_configs, port_range, community) do
    port_list = Enum.to_list(port_range)
    
    {devices, _remaining_ports} = 
      Enum.reduce(device_configs, {[], port_list}, fn config, {acc_devices, remaining_ports} ->
        {new_devices, used_ports} = start_device_group(config, remaining_ports, community)
        {acc_devices ++ new_devices, used_ports}
      end)
    
    case Enum.find(devices, fn {_device_info, result} -> match?({:error, _}, result) end) do
      nil ->
        # All devices started successfully
        successful_devices = 
          devices
          |> Enum.map(fn {device_info, {:ok, pid}} -> {device_info, pid} end)
          |> Map.new()
        
        Logger.info("Successfully started #{map_size(successful_devices)} devices")
        {:ok, successful_devices}
        
      {device_info, {:error, reason}} ->
        # At least one device failed to start
        Logger.error("Failed to start device #{inspect(device_info)}: #{inspect(reason)}")
        
        # Stop any devices that did start
        devices
        |> Enum.each(fn 
          {_info, {:ok, pid}} -> GenServer.stop(pid)
          _ -> :ok
        end)
        
        {:error, {:device_start_failed, device_info, reason}}
    end
  end

  defp start_device_group({device_type, source, opts}, available_ports, community) do
    count = Keyword.get(opts, :count, 1)
    device_opts = Keyword.get(opts, :device_opts, [])
    
    # Load the profile once for this device type
    case ProfileLoader.load_profile(device_type, source, opts) do
      {:ok, profile} ->
        {ports_to_use, remaining_ports} = Enum.split(available_ports, count)
        
        devices = 
          ports_to_use
          |> Enum.with_index()
          |> Enum.map(fn {port, index} ->
            device_info = %{
              device_type: device_type,
              port: port,
              device_id: "#{device_type}_#{port}",
              index: index
            }
            
            start_opts = [
              port: port,
              community: community
            ] ++ device_opts
            
            result = Device.start_link(profile, start_opts)
            {device_info, result}
          end)
        
        {devices, remaining_ports}
        
      {:error, reason} ->
        Logger.error("Failed to load profile for #{device_type}: #{inspect(reason)}")
        
        # Return error results for all devices in this group
        error_devices = 
          1..count
          |> Enum.map(fn index ->
            device_info = %{
              device_type: device_type,
              port: nil,
              device_id: "#{device_type}_#{index}",
              index: index
            }
            {device_info, {:error, {:profile_load_failed, reason}}}
          end)
        
        {error_devices, available_ports}
    end
  end
end