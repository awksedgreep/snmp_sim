# Getting Started with SnmpSim

This guide will help you get up and running with SnmpSim quickly, whether you're using it from Elixir code, configuration files, or container deployments.

## Quick Start (5 Minutes)

### 1. Basic Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:snmp_sim_ex, "~> 0.1.0"}
  ]
end
```

Run:
```bash
mix deps.get
```

### 2. Start Your First Device

```elixir
# Start the application
{:ok, _} = Application.ensure_all_started(:snmp_sim_ex)

# Create a simple device
{:ok, device} = SnmpSim.Device.start_link(
  community: "public",
  host: "127.0.0.1",
  port: 9001,
  walk_file: "priv/walks/cable_modem.walk"
)

# Test it works
:snmp.start()
{:ok, response} = :snmp.sync_get("127.0.0.1", 9001, "public", ["1.3.6.1.2.1.1.1.0"])
IO.inspect(response)
```

### 3. Verify It's Working

```bash
# Test with snmpget (if you have net-snmp tools installed)
snmpget -v2c -c public 127.0.0.1:9001 1.3.6.1.2.1.1.1.0

# Or test with snmpwalk
snmpwalk -v2c -c public 127.0.0.1:9001 1.3.6.1.2.1.1
```

## Configuration-Driven Setup

For easier management, especially in containers, SnmpSim supports JSON and YAML configuration files.

### JSON Configuration

Create `config/devices.json`:

```json
{
  "snmp_sim_ex": {
    "global_settings": {
      "max_devices": 1000,
      "max_memory_mb": 512,
      "enable_telemetry": true,
      "enable_performance_monitoring": true
    },
    "device_groups": [
      {
        "name": "cable_modems",
        "device_type": "cable_modem",
        "count": 100,
        "port_range": {
          "start": 30000,
          "end": 30099
        },
        "community": "public",
        "walk_file": "priv/walks/cable_modem.walk",
        "behaviors": ["realistic_counters", "time_patterns"],
        "error_injection": {
          "packet_loss_rate": 0.01,
          "timeout_rate": 0.005
        }
      },
      {
        "name": "switches",
        "device_type": "switch",
        "count": 20,
        "port_range": {
          "start": 31000,
          "end": 31019
        },
        "community": "private",
        "walk_file": "priv/walks/switch.walk",
        "behaviors": ["realistic_counters", "correlations"]
      }
    ],
    "monitoring": {
      "health_check": {
        "enabled": true,
        "port": 4000,
        "path": "/health"
      },
      "performance_monitor": {
        "collection_interval_ms": 30000,
        "alert_thresholds": {
          "memory_usage_mb": 400,
          "response_time_ms": 100,
          "error_rate_percent": 5.0
        }
      }
    }
  }
}
```

### YAML Configuration

Create `config/devices.yaml`:

```yaml
snmp_sim_ex:
  global_settings:
    max_devices: 1000
    max_memory_mb: 512
    enable_telemetry: true
    enable_performance_monitoring: true

  device_groups:
    - name: cable_modems
      device_type: cable_modem
      count: 100
      port_range:
        start: 30000
        end: 30099
      community: public
      walk_file: priv/walks/cable_modem.walk
      behaviors:
        - realistic_counters
        - time_patterns
      error_injection:
        packet_loss_rate: 0.01
        timeout_rate: 0.005

    - name: switches
      device_type: switch
      count: 20
      port_range:
        start: 31000
        end: 31019
      community: private
      walk_file: priv/walks/switch.walk
      behaviors:
        - realistic_counters
        - correlations

  monitoring:
    health_check:
      enabled: true
      port: 4000
      path: /health
    performance_monitor:
      collection_interval_ms: 30000
      alert_thresholds:
        memory_usage_mb: 400
        response_time_ms: 100
        error_rate_percent: 5.0
```

### Loading Configuration

```elixir
# Load from JSON
{:ok, config} = SnmpSim.Config.load_from_file("config/devices.json")
{:ok, _devices} = SnmpSim.Config.start_from_config(config)

# Load from YAML (requires :yaml_elixir dependency)
{:ok, config} = SnmpSim.Config.load_yaml("config/devices.yaml")
{:ok, _devices} = SnmpSim.Config.start_from_config(config)
```

## Container Usage

### Docker with Configuration Files

Create `docker-compose.yml`:

```yaml
version: '3.8'

services:
  snmp-sim:
    image: snmp-sim-ex:latest
    ports:
      - "30000-30999:30000-30999/udp"  # SNMP device ports
      - "4000:4000"                    # Health check port
    environment:
      - SNMP_SIM_EX_CONFIG_FILE=/app/config/devices.yaml
      - SNMP_SIM_EX_MAX_DEVICES=1000
      - SNMP_SIM_EX_MAX_MEMORY_MB=512
    volumes:
      - ./config:/app/config
      - ./walks:/app/priv/walks
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
```

### Environment Variable Configuration

```bash
# Basic settings
export SNMP_SIM_EX_MAX_DEVICES=5000
export SNMP_SIM_EX_MAX_MEMORY_MB=1024
export SNMP_SIM_EX_PORT_RANGE_START=30000
export SNMP_SIM_EX_PORT_RANGE_END=35000

# Performance settings
export SNMP_SIM_EX_WORKER_POOL_SIZE=32
export SNMP_SIM_EX_SOCKET_COUNT=8

# Monitoring
export SNMP_SIM_EX_ENABLE_TELEMETRY=true
export SNMP_SIM_EX_HEALTH_PORT=4000

# Run the application
docker run -d \
  -p 30000-35000:30000-35000/udp \
  -p 4000:4000 \
  --env-file .env \
  snmp-sim-ex:latest
```

## Common Use Cases

### 1. Load Testing Setup

```elixir
# Create a large device population for load testing
device_specs = [
  {:cable_modem, 5000},   # 5K cable modems
  {:switch, 200},         # 200 switches  
  {:router, 50}           # 50 routers
]

{:ok, devices} = SnmpSim.MultiDeviceStartup.start_device_population(
  device_specs,
  port_range: 30_000..39_999,
  behaviors: [:realistic_counters, :time_patterns, :correlations],
  error_injection: [packet_loss: 0.005, timeouts: 0.001]
)

# Monitor performance
{:ok, _monitor} = SnmpSim.Performance.PerformanceMonitor.start_link()

# Check stats
stats = SnmpSim.Performance.PerformanceMonitor.get_current_metrics()
IO.inspect(stats)
```

### 2. Development Testing

```elixir
# Start a few devices for development
{:ok, _} = SnmpSim.TestHelpers.create_test_devices(
  count: 10,
  community: "public",
  port_start: 30000,
  walk_file: "priv/walks/cable_modem.walk"
)

# Enable debug logging
Logger.configure(level: :debug)

# Test with error injection
device = Process.whereis({:device, 30001})
SnmpSim.ErrorInjector.inject_packet_loss(device, 0.1)  # 10% packet loss
```

### 3. CI/CD Integration

```elixir
# test/integration_test.exs
defmodule IntegrationTest do
  use ExUnit.Case
  
  setup_all do
    # Start test devices
    {:ok, devices} = SnmpSim.TestHelpers.create_test_devices(count: 5)
    
    on_exit(fn ->
      SnmpSim.TestHelpers.cleanup_devices(devices)
    end)
    
    {:ok, devices: devices}
  end
  
  test "devices respond to SNMP requests", %{devices: devices} do
    device = List.first(devices)
    {:ok, response} = SnmpSim.Device.get(device, "1.3.6.1.2.1.1.1.0")
    assert response.value != nil
  end
end
```

## Performance Tuning

### Memory Optimization

```elixir
# Configure resource limits
{:ok, _} = SnmpSim.Performance.ResourceManager.start_link([
  max_devices: 10_000,
  max_memory_mb: 1024,
  cleanup_threshold_percent: 80,
  monitoring_interval_ms: 60_000
])

# Enable device pooling with tiers
Application.put_env(:snmp_sim_ex, :device_pool, [
  optimization_enabled: true,
  tier_system_enabled: true,
  hot_tier_max_devices: 1000,
  warm_tier_max_devices: 5000
])
```

### Network Optimization

```elixir
# Start optimized UDP server
{:ok, server} = SnmpSim.Performance.OptimizedUdpServer.start_optimized(9001, [
  socket_count: 8,           # Multiple sockets for load distribution
  worker_pool_size: 32,      # More concurrent workers
  optimization_level: :aggressive
])
```

## Monitoring and Health Checks

### Health Endpoints

```bash
# Basic health check
curl http://localhost:4000/health

# Detailed metrics
curl http://localhost:4000/metrics

# Performance stats
curl http://localhost:4000/performance
```

### Programmatic Monitoring

```elixir
# Get real-time metrics
metrics = SnmpSim.Performance.PerformanceMonitor.get_current_metrics()
%{
  requests_per_second: 45_231,
  avg_latency_ms: 3.2,
  memory_usage_mb: 432,
  active_devices: 5000,
  error_rate_percent: 0.8
}

# Check system health
health = SnmpSim.TestHelpers.check_system_health()
%{
  memory_usage_mb: 432.5,
  process_count: 15_432,
  active_devices: 5000,
  system_healthy: true
}
```

## Troubleshooting

### Common Issues

1. **Port conflicts**:
   ```bash
   # Check if ports are in use
   netstat -an | grep 30000
   
   # Use different port range
   export SNMP_SIM_EX_PORT_RANGE_START=40000
   ```

2. **Memory issues**:
   ```elixir
   # Check memory usage
   :erlang.system_info(:memory)
   
   # Enable aggressive cleanup
   Application.put_env(:snmp_sim_ex, :cleanup_threshold_percent, 70)
   ```

3. **Performance issues**:
   ```elixir
   # Enable performance monitoring
   {:ok, _} = SnmpSim.Performance.PerformanceMonitor.start_link()
   
   # Check for bottlenecks
   stats = SnmpSim.Performance.PerformanceMonitor.get_current_metrics()
   ```

### Debug Mode

```elixir
# Enable debug logging
Logger.configure(level: :debug)

# Enable telemetry events
Application.put_env(:snmp_sim_ex, :enable_telemetry, true)

# Monitor specific device
device = Process.whereis({:device, 30001})
Process.monitor(device)
```

## Next Steps

1. **Read the full documentation**: See `README.md` for complete feature overview
2. **Explore examples**: Check `test/` directory for usage patterns
3. **Production deployment**: See deployment guides for Docker and Elixir releases
4. **Performance testing**: Use built-in benchmarking tools for validation
5. **Custom behaviors**: Implement custom device behaviors and profiles

## Configuration Reference

### Complete Environment Variables

```bash
# Core settings
SNMP_SIM_EX_HOST=0.0.0.0
SNMP_SIM_EX_COMMUNITY=public
SNMP_SIM_EX_MAX_DEVICES=10000
SNMP_SIM_EX_MAX_MEMORY_MB=1024

# Port configuration
SNMP_SIM_EX_PORT_RANGE_START=30000
SNMP_SIM_EX_PORT_RANGE_END=39999

# Performance settings
SNMP_SIM_EX_WORKER_POOL_SIZE=16
SNMP_SIM_EX_SOCKET_COUNT=4
SNMP_SIM_EX_IDLE_TIMEOUT_MS=1800000

# Monitoring
SNMP_SIM_EX_ENABLE_TELEMETRY=true
SNMP_SIM_EX_ENABLE_PERFORMANCE_MONITORING=true
SNMP_SIM_EX_HEALTH_PORT=4000

# Data persistence
SNMP_SIM_EX_DATA_DIR=/app/data
SNMP_SIM_EX_ENABLE_FILE_LOGGING=false

# Testing features
SNMP_SIM_EX_ENABLE_ERROR_INJECTION=false
SNMP_SIM_EX_DEFAULT_PACKET_LOSS_RATE=0.0
```

For more advanced configuration and deployment options, see the main README.md and deployment documentation.