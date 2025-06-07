# Development environment configuration
import Config

# Development-specific overrides
config :snmp_sim,
  # Reduced limits for development
  max_devices: 100,
  max_memory_mb: 256,

  # Smaller port range for development
  port_range_start: 30_000,
  port_range_end: 30_100,

  # Shorter timeouts for faster development feedback
  # 5 minutes
  idle_timeout_ms: 5 * 60 * 1000,
  # 1 minute
  cleanup_interval_ms: 60 * 1000,
  # 10 seconds
  health_check_interval_ms: 10_000,

  # Development performance settings
  worker_pool_size: 4,
  socket_count: 1,
  optimization_level: :normal,

  # Enable all features for testing
  enable_error_injection: true,
  enable_telemetry: true,
  enable_performance_monitoring: true,

  # Development data directory
  data_dir: "./dev_data"

# Enhanced logging for development
config :logger,
  level: :debug,
  backends: [:console]

config :logger, :console,
  format: "\n$time $metadata[$level] $message\n",
  metadata: [:request_id, :device_id, :port, :scenario_id, :module, :function, :line],
  colors: [
    enabled: true,
    debug: :cyan,
    info: :normal,
    warning: :yellow,
    error: :red
  ]

# Performance monitoring with more frequent collection
config :snmp_sim, :performance_monitor,
  enabled: true,
  # 10 seconds for development
  collection_interval_ms: 10_000,
  # Shorter retention
  metrics_retention_hours: 2,
  alert_thresholds: %{
    # Lower threshold for development
    memory_usage_mb: 200,
    cpu_usage_percent: 70,
    response_time_ms: 50,
    error_rate_percent: 10.0,
    device_failure_rate_percent: 20.0
  },
  # 30 seconds
  alert_cooldown_ms: 30_000

# Resource manager with development limits
config :snmp_sim, :resource_manager,
  enabled: true,
  max_devices: 100,
  max_memory_mb: 256,
  # More aggressive cleanup
  cleanup_threshold_percent: 70,
  # More frequent monitoring
  monitoring_interval_ms: 30_000,
  emergency_cleanup_enabled: true

# Device pool with smaller tiers
config :snmp_sim, :device_pool,
  optimization_enabled: true,
  tier_system_enabled: true,
  # Lower threshold for development
  tier_promotion_threshold: 10,
  tier_demotion_threshold: 2,
  # 1 minute
  cache_cleanup_interval_ms: 60_000,
  hot_tier_max_devices: 20,
  warm_tier_max_devices: 50

# Enable test scenarios for development
config :snmp_sim, :test_scenarios,
  enabled: true,
  # Shorter scenarios
  default_duration_seconds: 60,
  max_concurrent_scenarios: 5,
  scenario_cleanup_enabled: true

# Health check configuration for development
config :snmp_sim, :health_check,
  enabled: true,
  port: 4000,
  path: "/health",
  # Faster timeout
  timeout_ms: 2000,
  checks: [
    :memory_usage,
    :device_count,
    :response_time,
    :error_rate,
    :process_health
  ]

# Enable all behavior features for development testing
config :snmp_sim, :behaviors,
  realistic_counters_enabled: true,
  time_patterns_enabled: true,
  correlations_enabled: true,
  seasonal_patterns_enabled: true,
  device_characteristics_enabled: true

# Development-specific ExUnit configuration
config :ex_unit,
  capture_log: true,
  exclude: [:slow, :shell_integration],
  formatters: [ExUnit.CLIFormatter],
  max_failures: 5
