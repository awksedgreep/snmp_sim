# SnmpSim IEx Helper Functions
# Load this with: iex -S mix

# Ensure the application and devices are started
Application.ensure_all_started(:snmp_sim)

# Wait a moment for startup
Process.sleep(1000)

# Check if devices are running and start them if not
case DynamicSupervisor.which_children(SnmpSim.DeviceSupervisor) do
  [] ->
    IO.puts "🔧 No devices found, starting test devices..."

    # Start test devices manually if config didn't load
    test_devices = [
      %{port: 30000, device_type: :cable_modem, device_id: "test_cable_modems_30000", community: "public"},
      %{port: 30001, device_type: :cable_modem, device_id: "test_cable_modems_30001", community: "public"},
      %{port: 31000, device_type: :switch, device_id: "test_switches_31000", community: "public"},
      %{port: 32000, device_type: :router, device_id: "test_routers_32000", community: "public"}
    ]

    Enum.each(test_devices, fn config ->
      case DynamicSupervisor.start_child(SnmpSim.DeviceSupervisor, {SnmpSim.Device, config}) do
        {:ok, _pid} ->
          IO.puts "✅ Started device #{config.device_id} on port #{config.port}"
        {:error, reason} ->
          IO.puts "❌ Failed to start device #{config.device_id}: #{inspect(reason)}"
      end
    end)

  children ->
    IO.puts "✅ Found #{length(children)} running devices"
end

# Show running devices
running_devices = DynamicSupervisor.which_children(SnmpSim.DeviceSupervisor)
IO.puts "📊 Active devices: #{length(running_devices)}"

IO.puts """
🚀 SnmpSim Interactive Console
================================

Quick Start:
  Sim.start()                    # Start sample devices
  Sim.create_cable_modem(9001)   # Create single cable modem
  Sim.list_devices()             # Show running devices
  Sim.test_device(9001)          # Test device responses
  Sim.monitor()                  # Watch live simulation updates
  Sim.stop_all()                 # Clean shutdown

Device Creation:
  Sim.create_cable_modem(9999)
  Sim.create_cmts(9998)
  Sim.create_switch(9997)
  Sim.create_many(:cable_modem, 10)

Walk File Support:
  Sim.list_walks()               # List available walk files
  Sim.create_with_walk(9999, "cable_modem_oids.walk")
  Sim.demo_type_fidelity(9999)   # Demo type preservation
  Sim.show_types(9999)           # Show SNMP types vs values

Testing & Monitoring:
  Sim.walk_device(9999)          # Walk all OIDs (shows all by default)
  Sim.walk_device(9999, "1.3.6.1.2.1", 20)  # Limit to first 20
  Sim.get_counters(9999)
  Sim.get_gauges(9999)
  Sim.device_stats(9999)
  Sim.simulation_performance()

Configuration:
  Sim.with_jitter(device_pid, config)
  Sim.set_utilization(device_pid, level)
  Sim.inject_errors(device_pid)
"""

defmodule Sim do
  @moduledoc "SnmpSim Interactive Helpers"

  alias SnmpSim.{Device, Config, Core.Server}
  alias SnmpSim.Performance.{PerformanceMonitor, ResourceManager}

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
      case DynamicSupervisor.start_child(SnmpSim.DeviceSupervisor, {SnmpSim.Device, config}) do
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
    devices = DynamicSupervisor.which_children(SnmpSim.DeviceSupervisor)
    |> Enum.map(fn {_, pid, _, _} ->
      if Process.alive?(pid) do
        info = Device.get_info(pid)
        {info.port, info.device_type, info.device_id, pid}
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
  def walk_device(port, root_oid \\ "1.3.6.1.2.1", limit \\ :all) do
    case get_device_pid(port) do
      {:ok, pid} ->
        IO.puts "🚶 Walking device on port #{port} from #{root_oid}..."

        case Device.walk(pid, root_oid) do
          {:ok, results} ->
            total_count = length(results)
            IO.puts "Found #{total_count} OIDs:"

            results_to_show = case limit do
              :all -> results
              n when is_integer(n) -> Enum.take(results, n)
            end

            results_to_show
            |> Enum.each(fn {oid, value} ->
              IO.puts "  #{oid} = #{inspect(value)}"
            end)

            if limit != :all and total_count > limit do
              IO.puts "  ... and #{total_count - limit} more (use walk_device(#{port}, \"#{root_oid}\", :all) to see all)"
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

    case DynamicSupervisor.start_child(SnmpSim.DeviceSupervisor, {SnmpSim.Device, config}) do
      {:ok, pid} ->
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
    devices = DynamicSupervisor.which_children(SnmpSim.DeviceSupervisor)
    |> Enum.map(fn {_, pid, _, _} ->
      if Process.alive?(pid) do
        info = Device.get_info(pid)
        if info.port == port do
          pid
        else
          nil
        end
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.take(1) # Only take the first match

    case devices do
      [pid] -> {:ok, pid}
      [] -> {:error, "No device running on port #{port}"}
      _ -> {:error, "Multiple devices found on port #{port}"}
    end
  end

  defp get_running_devices do
    DynamicSupervisor.which_children(SnmpSim.DeviceSupervisor)
    |> Enum.map(fn {_, pid, _, _} ->
      if Process.alive?(pid) do
        info = Device.get_info(pid)
        {info.port, info.device_type, info.device_id, pid}
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

  # Walk file and type fidelity helpers

  @doc "List available walk files in priv/walks/"
  def list_walks do
    walk_dir = Path.join([File.cwd!(), "priv", "walks"])

    case File.ls(walk_dir) do
      {:ok, files} ->
        walk_files = files
        |> Enum.filter(&String.ends_with?(&1, ".walk"))
        |> Enum.sort()

        if length(walk_files) == 0 do
          IO.puts "📁 No walk files found in priv/walks/"
        else
          IO.puts "\n📁 Available Walk Files (#{length(walk_files)}):"
          Enum.each(walk_files, fn file ->
            IO.puts "  • #{file}"
          end)
        end

        walk_files

      {:error, reason} ->
        IO.puts "❌ Could not read priv/walks/: #{reason}"
        []
    end
  end

  @doc "Create a device with a specific walk file profile"
  def create_with_walk(port, walk_file, device_id \\ nil) do
    device_id = device_id || "walk_device_#{port}"
    device_type = String.to_atom("walk_#{Path.basename(walk_file, ".walk")}")

    # First, load the walk profile into SharedProfiles
    walk_path = Path.join([File.cwd!(), "priv", "walks", walk_file])

    IO.puts "📁 Loading walk profile: #{walk_file}"
    case SnmpSim.MIB.SharedProfiles.load_walk_profile(device_type, walk_path) do
      :ok ->
        IO.puts "✅ Walk profile loaded for device type: #{device_type}"

        # Now create the device with that device type
        config = %{
          port: port,
          device_type: device_type,
          device_id: device_id
        }

        case DynamicSupervisor.start_child(SnmpSim.DeviceSupervisor, {SnmpSim.Device, config}) do
          {:ok, pid} ->
            IO.puts "✅ Created device #{device_id} on port #{port} with walk profile: #{walk_file}"
            {:ok, pid}

          {:error, reason} ->
            IO.puts "❌ Failed to create device: #{inspect(reason)}"
            {:error, reason}
        end

      {:error, reason} ->
        IO.puts "❌ Failed to load walk profile: #{inspect(reason)}"
        {:error, reason}
    end
  end

  @doc "Demonstrate type fidelity by showing SNMP types vs values"
  def show_types(port, oids \\ nil) do
    case get_device_pid(port) do
      {:ok, pid} ->
        # Default OIDs that show different SNMP types
        test_oids = oids || [
          "1.3.6.1.2.1.1.1.0",
          "1.3.6.1.2.1.1.3.0",
          "1.3.6.1.2.1.2.1.0",
          "1.3.6.1.2.1.2.2.1.5.1",
          "1.3.6.1.2.1.2.2.1.10.1",
          "1.3.6.1.2.1.2.2.1.6.1"
        ]

        IO.puts "\n🔍 Type Fidelity Demo for Port #{port}:"
        IO.puts "OID                    | Type      | Value"
        IO.puts "-----------------------|-----------|------------------------"

        Enum.each(test_oids, fn oid ->
          case Device.get(pid, oid) do
            {:ok, {type, value}} ->
              oid_short = String.slice(oid, -15..-1) |> String.pad_trailing(22)
              type_str = String.pad_trailing(to_string(type), 9)
              value_str = inspect(value) |> String.slice(0..20)
              IO.puts "#{oid_short} | #{type_str} | #{value_str}"

            {:ok, value} ->
              # Fallback for old format
              oid_short = String.slice(oid, -15..-1) |> String.pad_trailing(22)
              IO.puts "#{oid_short} | auto      | #{inspect(value) |> String.slice(0..20)}"

            {:error, reason} ->
              oid_short = String.slice(oid, -15..-1) |> String.pad_trailing(22)
              IO.puts "#{oid_short} | ERROR     | #{inspect(reason)}"
          end
        end)

      {:error, reason} ->
        IO.puts "❌ #{reason}"
    end
  end

  @doc "Quick demo: create cable modem with walk file and show types"
  def demo_type_fidelity(port \\ 9999) do
    IO.puts "🎯 Type Fidelity Demo Starting..."

    # Create device with cable modem walk
    case create_with_walk(port, "cable_modem_oids.walk", "demo_cm_#{port}") do
      {:ok, _pid} ->
        Process.sleep(1000)  # Let device initialize
        IO.puts "\n📊 Testing SNMP type preservation..."
        show_types(port)
        IO.puts "\n✅ Demo complete! Device running on port #{port}"

      {:error, reason} ->
        IO.puts "❌ Demo failed: #{inspect(reason)}"
    end
  end

  @doc "Bulk walk a device to see all OIDs and types"
  def walk_with_types(port, base_oid \\ "1.3.6.1.2.1.1") do
    case get_device_pid(port) do
      {:ok, pid} ->
        IO.puts "\n🚶 Walking device on port #{port} starting from #{base_oid}:"

        # This would require implementing a walk function in Device
        # For now, just test a few common OIDs under the base
        test_oids = [
          "#{base_oid}.1.0",
          "#{base_oid}.2.0",
          "#{base_oid}.3.0",
          "#{base_oid}.4.0",
          "#{base_oid}.5.0"
        ]

        Enum.each(test_oids, fn oid ->
          case Device.get(pid, oid) do
            {:ok, {type, value}} ->
              IO.puts "  #{oid} = #{type}: #{inspect(value)}"
            {:ok, value} ->
              IO.puts "  #{oid} = auto: #{inspect(value)}"
            {:error, _} ->
              # Skip missing OIDs
              nil
          end
        end)

      {:error, reason} ->
        IO.puts "❌ #{reason}"
    end
  end
end

# Make Device and other modules easily accessible
alias SnmpSim.{Device, Config, ValueSimulator}
alias SnmpSim.Core.Server
alias SnmpLib.PDU
alias SnmpSim.MIB.{BehaviorAnalyzer, SharedProfiles}

IO.puts "✅ Helper functions loaded! Type Sim.start() to begin."
