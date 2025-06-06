# Test environment configuration
import Config

# Test environment overrides for fast, isolated testing
config :snmp_sim,
  # Minimal limits for testing
  max_devices: 50,
  max_memory_mb: 128,
  
  # Small port range for testing
  port_range_start: 40_000,
  port_range_end: 40_050,
  
  # Fast timeouts for testing
  idle_timeout_ms: 5 * 1000,           # 5 seconds
  cleanup_interval_ms: 1 * 1000,       # 1 second
  health_check_interval_ms: 1_000,     # 1 second
  
  # Minimal performance settings for testing
  worker_pool_size: 2,
  socket_count: 1,
  optimization_level: :minimal,
  
  # Testing features
  enable_error_injection: true,
  enable_telemetry: false,              # Disabled for cleaner test output
  enable_performance_monitoring: false, # Disabled for faster tests
  enable_persistence: false,            # Disabled for test isolation
  
  # Test data directory (cleaned between tests)
  data_dir: "./test_data"

# Minimal logging for tests
config :logger,
  level: :warning,
  backends: [:console]

config :logger, :console,
  format: "[$level] $message\n",
  metadata: [],
  colors: [enabled: false]

# Disabled performance monitoring for tests
config :snmp_sim, :performance_monitor,
  enabled: false,
  collection_interval_ms: 1000,
  metrics_retention_hours: 1,
  alert_thresholds: %{
    memory_usage_mb: 100,
    cpu_usage_percent: 90,
    response_time_ms: 1000,
    error_rate_percent: 50.0,
    device_failure_rate_percent: 80.0
  },
  alert_cooldown_ms: 1000

# Minimal resource manager for tests
config :snmp_sim, :resource_manager,
  enabled: false,                       # Disabled for test isolation
  max_devices: 50,
  max_memory_mb: 128,
  cleanup_threshold_percent: 50,
  monitoring_interval_ms: 1000,
  emergency_cleanup_enabled: false

# Minimal device pool for tests
config :snmp_sim, :device_pool,
  optimization_enabled: false,          # Disabled for predictable tests
  tier_system_enabled: false,           # Disabled for simpler tests
  tier_promotion_threshold: 5,
  tier_demotion_threshold: 1,
  cache_cleanup_interval_ms: 1000,
  hot_tier_max_devices: 10,
  warm_tier_max_devices: 30

# Enable test scenarios for testing
config :snmp_sim, :test_scenarios,
  enabled: true,
  default_duration_seconds: 5,          # Very short for tests
  max_concurrent_scenarios: 3,
  scenario_cleanup_enabled: true

# Fast health checks for tests
config :snmp_sim, :health_check,
  enabled: false,                       # Disabled unless specifically testing
  port: 4001,                          # Different port to avoid conflicts
  path: "/health",
  timeout_ms: 500,                     # Fast timeout
  checks: [
    :memory_usage,
    :device_count,
    :response_time
  ]

# Minimal behavior features for faster tests
config :snmp_sim, :behaviors,
  realistic_counters_enabled: false,    # Disabled for predictable tests
  time_patterns_enabled: false,         # Disabled for faster tests
  correlations_enabled: false,          # Disabled for simpler tests
  seasonal_patterns_enabled: false,     # Disabled for faster tests
  device_characteristics_enabled: false # Disabled for predictable tests

# Test-specific ExUnit configuration
config :ex_unit,
  capture_log: true,
  exclude: [:slow, :integration, :shell_integration],
  include: [:unit],
  formatters: [ExUnit.CLIFormatter],
  timeout: 30_000,                      # 30 seconds per test
  assert_receive_timeout: 1000

# Test database configuration (if needed)
config :snmp_sim, :database,
  enabled: false,                       # Disabled for test isolation
  pool_size: 1,
  timeout: 5000

# Test security settings (permissive for testing)
config :snmp_sim, :security,
  enable_rate_limiting: false,
  max_requests_per_second: 1000,
  enable_ip_whitelisting: false,
  allowed_communities: ["public", "test"],
  enable_audit_logging: false

# Disabled telemetry for tests
config :snmp_sim, :telemetry,
  enabled: false,
  metrics_interval_ms: 1000,
  export_prometheus: false,
  export_influxdb: false

# Test helper configuration
config :snmp_sim, :test_helpers,
  cleanup_on_exit: true,
  auto_start_devices: false,
  mock_network_delays: false,
  enable_debug_logging: false,
  test_data_persistence: false