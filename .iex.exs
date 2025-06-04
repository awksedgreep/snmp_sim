# SNMPSimEx IEx Helper Functions
# Load this with: iex -S mix

IO.puts """
🚀 SNMPSimEx Interactive Console
================================

Quick Start:
  Sim.start()                    # Start sample devices
  Sim.create_cable_modem(9001)   # Create single cable modem
  Sim.list_devices()             # Show running devices
  Sim.test_device(9001)          # Test device responses
  Sim.monitor()                  # Watch live simulation updates
  Sim.stop_all()                 # Clean shutdown

Device Creation:
  Sim.create_cable_modem(port)
  Sim.create_cmts(port)
  Sim.create_switch(port)
  Sim.create_many(:cable_modem, count)

Testing & Monitoring:
  Sim.walk_device(port)
  Sim.get_counters(port)
  Sim.get_gauges(port)
  Sim.device_stats(port)
  Sim.simulation_performance()

Configuration:
  Sim.with_jitter(device_pid, config)
  Sim.set_utilization(device_pid, level)
  Sim.inject_errors(device_pid)
"""

defmodule Sim do
  @moduledoc "SNMPSimEx Interactive Helpers"

  alias SNMPSimEx.{Device, Config, Core.Server}
  alias SNMPSimEx.Performance.{PerformanceMonitor, ResourceManager}
  
  @doc "Start sample devices for testing"
  def start do
    IO.puts "🚀 Starting sample devices..."
    
    devices = [
      %{port: 9001, device_type: :cable_modem, device_id: "cm_001"},
      %{port: 9002, device_type: :cable_modem, device_id: "cm_002"},
      %{port: 9003, device_type: :cmts, device_id: "cmts_001"},
      %{port: 9004, device_type: :switch, device_id: "sw_001"}
    ]
    
    results = Enum.map(devices, fn config ->
      case Device.start_link(config) do
        {:ok, pid} ->
          Process.register(pid, String.to_atom("device_#{config.port}"))
          {config.port, config.device_type, pid, :ok}
        {:error, reason} ->
          {config.port, config.device_type, nil, {:error, reason}}
      end
    end)
    
    successes = Enum.filter(results, fn {_, _, _, status} -> status == :ok end)
    failures = Enum.filter(results, fn {_, _, _, status} -> status != :ok end)
    
    IO.puts "✅ Started #{length(successes)} devices"
    if length(failures) > 0 do
      IO.puts "❌ Failed to start #{length(failures)} devices"
      Enum.each(failures, fn {port, type, _, {:error, reason}} ->
        IO.puts "   Port #{port} (#{type}): #{inspect(reason)}"
      end)
    end
    
    list_devices()
  end

  @doc "Create a single cable modem"
  def create_cable_modem(port) when is_integer(port) do
    create_device(port, :cable_modem, "cm_#{port}")
  end

  @doc "Create a single CMTS"
  def create_cmts(port) when is_integer(port) do
    create_device(port, :cmts, "cmts_#{port}")
  end

  @doc "Create a single switch"
  def create_switch(port) when is_integer(port) do
    create_device(port, :switch, "sw_#{port}")
  end

  @doc "Create multiple devices of the same type"
  def create_many(device_type, count, start_port \\ 10000) do
    IO.puts "🚀 Creating #{count} #{device_type} devices starting at port #{start_port}..."
    
    start_time = :os.system_time(:millisecond)
    
    results = Enum.map(0..(count-1), fn i ->
      port = start_port + i
      device_id = "#{device_type}_#{String.pad_leading(to_string(i+1), 3, "0")}"
      create_device(port, device_type, device_id, false) # Don't print each one
    end)
    
    end_time = :os.system_time(:millisecond)
    duration = end_time - start_time
    
    successes = Enum.count(results, fn {_, status} -> status == :ok end)
    failures = count - successes
    
    IO.puts "✅ Created #{successes}/#{count} devices in #{duration}ms"
    if failures > 0, do: IO.puts "❌ #{failures} failed to start"
    
    list_devices()
  end

  @doc "List all running devices"
  def list_devices do
    devices = Process.registered()
    |> Enum.filter(fn name -> 
      String.starts_with?(Atom.to_string(name), "device_")
    end)
    |> Enum.map(fn name ->
      pid = Process.whereis(name)
      if Process.alive?(pid) do
        port = name |> Atom.to_string() |> String.replace("device_", "") |> String.to_integer()
        info = Device.get_info(pid)
        {port, info.device_type, info.device_id, pid}
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort()

    if length(devices) == 0 do
      IO.puts "📭 No devices running"
    else
      IO.puts "\n📡 Running Devices (#{length(devices)}):"
      IO.puts "Port  | Type         | Device ID    | PID"
      IO.puts "------|--------------|--------------|-------------"
      
      Enum.each(devices, fn {port, type, device_id, pid} ->
        port_str = String.pad_trailing(to_string(port), 5)
        type_str = String.pad_trailing(to_string(type), 12)
        id_str = String.pad_trailing(device_id, 12)
        pid_str = inspect(pid)
        IO.puts "#{port_str} | #{type_str} | #{id_str} | #{pid_str}"
      end)
    end
    
    devices
  end

  @doc "Test a device by getting basic OIDs"
  def test_device(port) when is_integer(port) do
    case get_device_pid(port) do
      {:ok, pid} ->
        IO.puts "🧪 Testing device on port #{port}..."
        
        test_oids = [
          {"1.3.6.1.2.1.1.1.0", "sysDescr"},
          {"1.3.6.1.2.1.1.3.0", "sysUpTime"},
          {"1.3.6.1.2.1.2.1.0", "ifNumber"},
          {"1.3.6.1.2.1.2.2.1.10.1", "ifInOctets"}
        ]
        
        Enum.each(test_oids, fn {oid, name} ->
          case Device.get(pid, oid) do
            {:ok, value} -> 
              IO.puts "  ✅ #{name}: #{inspect(value)}"
            {:error, reason} -> 
              IO.puts "  ❌ #{name}: #{inspect(reason)}"
          end
        end)
        
      {:error, reason} ->
        IO.puts "❌ #{reason}"
    end
  end

  @doc "Walk all OIDs from a device"
  def walk_device(port, root_oid \\ "1.3.6.1.2.1") do
    case get_device_pid(port) do
      {:ok, pid} ->
        IO.puts "🚶 Walking device on port #{port} from #{root_oid}..."
        
        case Device.walk(pid, root_oid) do
          {:ok, results} ->
            IO.puts "Found #{length(results)} OIDs:"
            
            Enum.take(results, 20) # Show first 20
            |> Enum.each(fn {oid, value} ->
              IO.puts "  #{oid} = #{inspect(value)}"
            end)
            
            if length(results) > 20 do
              IO.puts "  ... and #{length(results) - 20} more"
            end
            
            results
            
          {:error, reason} ->
            IO.puts "❌ Walk failed: #{inspect(reason)}"
            {:error, reason}
        end
        
      {:error, reason} ->
        IO.puts "❌ #{reason}"
    end
  end

  @doc "Get counter values from a device"
  def get_counters(port) do
    case get_device_pid(port) do
      {:ok, pid} ->
        counter_oids = [
          {"1.3.6.1.2.1.2.2.1.10.1", "ifInOctets"},
          {"1.3.6.1.2.1.2.2.1.16.1", "ifOutOctets"},
          {"1.3.6.1.2.1.31.1.1.1.6.1", "ifHCInOctets"},
          {"1.3.6.1.2.1.31.1.1.1.10.1", "ifHCOutOctets"},
          {"1.3.6.1.2.1.2.2.1.11.1", "ifInUcastPkts"},
          {"1.3.6.1.2.1.2.2.1.17.1", "ifOutUcastPkts"},
          {"1.3.6.1.2.1.2.2.1.14.1", "ifInErrors"},
          {"1.3.6.1.2.1.2.2.1.20.1", "ifOutErrors"}
        ]
        
        IO.puts "📊 Counter values for port #{port}:"
        
        results = Enum.map(counter_oids, fn {oid, name} ->
          case Device.get(pid, oid) do
            {:ok, value} -> 
              formatted_value = format_counter_value(value)
              IO.puts "  #{String.pad_trailing(name, 15)}: #{formatted_value}"
              {name, value}
            {:error, reason} -> 
              IO.puts "  #{String.pad_trailing(name, 15)}: ERROR #{inspect(reason)}"
              {name, {:error, reason}}
          end
        end)
        
        results
        
      {:error, reason} ->
        IO.puts "❌ #{reason}"
    end
  end

  @doc "Get gauge values from a device"
  def get_gauges(port) do
    case get_device_pid(port) do
      {:ok, pid} ->
        gauge_oids = [
          {"1.3.6.1.2.1.2.2.1.5.1", "ifSpeed"},
          {"1.3.6.1.2.1.10.127.1.1.4.1.5.3", "SNR (dB)"},
          {"1.3.6.1.2.1.25.3.3.1.2.1", "hrProcessorLoad"},
          {"1.3.6.1.2.1.25.2.3.1.6.1", "hrStorageUsed"}
        ]
        
        IO.puts "📈 Gauge values for port #{port}:"
        
        results = Enum.map(gauge_oids, fn {oid, name} ->
          case Device.get(pid, oid) do
            {:ok, value} -> 
              formatted_value = format_gauge_value(value)
              IO.puts "  #{String.pad_trailing(name, 18)}: #{formatted_value}"
              {name, value}
            {:error, reason} -> 
              IO.puts "  #{String.pad_trailing(name, 18)}: ERROR #{inspect(reason)}"
              {name, {:error, reason}}
          end
        end)
        
        results
        
      {:error, reason} ->
        IO.puts "❌ #{reason}"
    end
  end

  @doc "Get device statistics and info"
  def device_stats(port) do
    case get_device_pid(port) do
      {:ok, pid} ->
        info = Device.get_info(pid)
        
        IO.puts "📋 Device Statistics for port #{port}:"
        IO.puts "  Device ID: #{info.device_id}"
        IO.puts "  Type: #{info.device_type}"
        IO.puts "  MAC Address: #{info.mac_address}"
        IO.puts "  Uptime: #{format_uptime(info.uptime)} seconds"
        IO.puts "  OID Count: #{info.oid_count}"
        IO.puts "  Counters: #{info.counters}"
        IO.puts "  Gauges: #{info.gauges}"
        IO.puts "  Status Variables: #{info.status_vars}"
        
        info
        
      {:error, reason} ->
        IO.puts "❌ #{reason}"
    end
  end

  @doc "Monitor live simulation updates"
  def monitor(duration_seconds \\ 30) do
    IO.puts "👁️  Monitoring simulation for #{duration_seconds} seconds..."
    IO.puts "Press Ctrl+C to stop early\n"
    
    devices = get_running_devices()
    if length(devices) == 0 do
      IO.puts "❌ No devices running"
    else
      start_time = :os.system_time(:second)
      end_time = start_time + duration_seconds
      
      # Take baseline readings
      baseline = take_readings(devices)
      
      monitor_loop(devices, baseline, end_time, 1)
    end
  end

  @doc "Configure jitter for a device"
  def with_jitter(device_pid, jitter_config \\ %{}) when is_pid(device_pid) do
    default_config = %{
      jitter_pattern: :uniform,
      jitter_amount: 0.05,
      jitter_burst_probability: 0.1
    }
    
    config = Map.merge(default_config, jitter_config)
    
    IO.puts "⚙️  Configuring jitter: #{inspect(config)}"
    
    # This would require extending the Device module to accept runtime config
    # For now, just show what the config would be
    IO.puts "✅ Jitter configuration set (simulated)"
    config
  end

  @doc "Set utilization level for a device"
  def set_utilization(device_pid, level) when is_pid(device_pid) and is_number(level) do
    IO.puts "📊 Setting utilization to #{level * 100}%"
    
    # This would require extending the Device module for runtime state changes
    # For now, just simulate the change
    IO.puts "✅ Utilization level set (simulated)"
    {:ok, level}
  end

  @doc "Inject errors into a device"
  def inject_errors(device_pid, error_rate \\ 0.1) when is_pid(device_pid) do
    IO.puts "💥 Injecting #{error_rate * 100}% error rate"
    
    # This would require extending the Device module for error injection
    IO.puts "✅ Error injection enabled (simulated)"
    {:ok, error_rate}
  end

  @doc "Show simulation performance metrics"
  def simulation_performance do
    IO.puts "⚡ Simulation Performance Metrics:"
    
    # Get system metrics
    process_count = length(Process.list())
    memory_usage = :erlang.memory()
    
    IO.puts "  Processes: #{process_count}"
    IO.puts "  Total Memory: #{format_bytes(memory_usage[:total])}"
    IO.puts "  Process Memory: #{format_bytes(memory_usage[:processes])}"
    IO.puts "  System Memory: #{format_bytes(memory_usage[:system])}"
    
    # Get device count
    device_count = get_running_devices() |> length()
    IO.puts "  Active Devices: #{device_count}"
    
    if device_count > 0 do
      memory_per_device = div(memory_usage[:processes], device_count)
      IO.puts "  Memory per Device: #{format_bytes(memory_per_device)}"
    end
    
    %{
      process_count: process_count,
      memory_usage: memory_usage,
      device_count: device_count
    }
  end

  @doc "Stop all devices"
  def stop_all do
    devices = get_running_devices()
    
    IO.puts "🛑 Stopping #{length(devices)} devices..."
    
    Enum.each(devices, fn {_port, _type, _id, pid} ->
      Device.stop(pid)
    end)
    
    # Wait a moment for clean shutdown
    Process.sleep(500)
    
    IO.puts "✅ All devices stopped"
  end

  @doc "Clean restart - stop all and start fresh"
  def restart do
    stop_all()
    Process.sleep(1000)
    start()
  end

  # Private helper functions
  
  defp create_device(port, device_type, device_id, print \\ true) do
    config = %{
      port: port,
      device_type: device_type,
      device_id: device_id
    }
    
    case Device.start_link(config) do
      {:ok, pid} ->
        Process.register(pid, String.to_atom("device_#{port}"))
        if print do
          IO.puts "✅ Created #{device_type} on port #{port} (#{device_id})"
        end
        {pid, :ok}
        
      {:error, reason} ->
        if print do
          IO.puts "❌ Failed to create device on port #{port}: #{inspect(reason)}"
        end
        {nil, {:error, reason}}
    end
  end

  defp get_device_pid(port) do
    name = String.to_atom("device_#{port}")
    
    case Process.whereis(name) do
      nil -> {:error, "No device running on port #{port}"}
      pid when is_pid(pid) ->
        if Process.alive?(pid) do
          {:ok, pid}
        else
          {:error, "Device on port #{port} is not alive"}
        end
    end
  end

  defp get_running_devices do
    Process.registered()
    |> Enum.filter(fn name -> 
      String.starts_with?(Atom.to_string(name), "device_")
    end)
    |> Enum.map(fn name ->
      pid = Process.whereis(name)
      if Process.alive?(pid) do
        port = name |> Atom.to_string() |> String.replace("device_", "") |> String.to_integer()
        info = Device.get_info(pid)
        {port, info.device_type, info.device_id, pid}
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort()
  end

  defp take_readings(devices) do
    Enum.map(devices, fn {port, _type, _id, pid} ->
      counters = [
        {"1.3.6.1.2.1.2.2.1.10.1", "ifInOctets"},
        {"1.3.6.1.2.1.2.2.1.16.1", "ifOutOctets"},
        {"1.3.6.1.2.1.31.1.1.1.6.1", "ifHCInOctets"},
        {"1.3.6.1.2.1.31.1.1.1.10.1", "ifHCOutOctets"}
      ]
      
      readings = Enum.map(counters, fn {oid, name} ->
        case Device.get(pid, oid) do
          {:ok, value} -> {name, extract_counter_value(value)}
          {:error, _} -> {name, 0}
        end
      end) |> Map.new()
      
      {port, readings}
    end) |> Map.new()
  end

  defp monitor_loop(devices, baseline, end_time, iteration) do
    current_time = :os.system_time(:second)
    
    if current_time >= end_time do
      IO.puts "\n✅ Monitoring complete"
    else
    
      # Take current readings
      current = take_readings(devices)
      
      # Calculate and display changes
      IO.puts "\n📊 Update ##{iteration} (#{end_time - current_time}s remaining):"
      
      Enum.each(devices, fn {port, type, _id, _pid} ->
        base_in = get_in(baseline, [port, "ifInOctets"]) || 0
        base_out = get_in(baseline, [port, "ifOutOctets"]) || 0
        curr_in = get_in(current, [port, "ifInOctets"]) || 0
        curr_out = get_in(current, [port, "ifOutOctets"]) || 0
        
        delta_in = curr_in - base_in
        delta_out = curr_out - base_out
        
        IO.puts "  Port #{port} (#{type}): +#{format_counter_value(delta_in)} in, +#{format_counter_value(delta_out)} out"
      end)
      
      Process.sleep(3000) # Update every 3 seconds
      monitor_loop(devices, baseline, end_time, iteration + 1)
    end
  end

  defp format_counter_value({:counter32, value}), do: format_number(value)
  defp format_counter_value({:counter64, value}), do: format_number(value)
  defp format_counter_value(value) when is_integer(value), do: format_number(value)
  defp format_counter_value(value), do: inspect(value)

  defp format_gauge_value({:gauge32, value}), do: format_number(value)
  defp format_gauge_value(value) when is_integer(value), do: format_number(value)
  defp format_gauge_value(value), do: inspect(value)

  defp extract_counter_value({:counter32, value}), do: value
  defp extract_counter_value({:counter64, value}), do: value
  defp extract_counter_value(value) when is_integer(value), do: value
  defp extract_counter_value(_), do: 0

  defp format_number(num) when is_integer(num) do
    num
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp format_bytes(bytes) do
    cond do
      bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 2)} GB"
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 2)} MB"
      bytes >= 1_024 -> "#{Float.round(bytes / 1_024, 2)} KB"
      true -> "#{bytes} B"
    end
  end

  defp format_uptime(uptime) when is_integer(uptime), do: uptime
  defp format_uptime(_), do: "unknown"
end

# Make Device and other modules easily accessible
alias SNMPSimEx.{Device, Config, ValueSimulator}
alias SNMPSimEx.Core.Server
alias SnmpLib.PDU
alias SNMPSimEx.MIB.{BehaviorAnalyzer, SharedProfiles}

IO.puts "✅ Helper functions loaded! Type Sim.start() to begin."