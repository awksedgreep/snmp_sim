# SnmpSim Configuration
import Config

# Default application configuration
config :snmp_sim,
  # Application metadata
  app_name: "SnmpSim",
  app_version: "0.1.0",

  # Default SNMP settings
  default_community: "public",
  snmp_versions: [:v1, :v2c],

  # Default device limits
  max_devices: 10_000,
  max_memory_mb: 1024,

  # Default port range
  port_range_start: 30_000,
  port_range_end: 39_999,

  # Default timeouts and intervals
  # 30 minutes
  idle_timeout_ms: 30 * 60 * 1000,
  # 5 minutes
  cleanup_interval_ms: 5 * 60 * 1000,
  # 30 seconds
  health_check_interval_ms: 30_000,

  # Performance defaults
  worker_pool_size: 16,
  socket_count: 4,
  optimization_level: :normal,

  # Profile management
  # 1 hour
  profile_cache_ttl_ms: 60 * 60 * 1000,
  shared_profiles_enabled: true,

  # Error injection (disabled by default)
  enable_error_injection: false,
  default_packet_loss_rate: 0.0,
  default_timeout_rate: 0.0,

  # Telemetry and monitoring
  enable_telemetry: true,
  enable_performance_monitoring: true,

  # Data persistence
  data_dir: "./data",
  enable_persistence: false

# Logger configuration
config :logger,
  level: :info,
  backends: [:console],
  truncate: 4096

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :device_id, :port, :scenario_id],
  colors: [enabled: true]

# Performance monitoring configuration
config :snmp_sim, :performance_monitor,
  enabled: true,
  collection_interval_ms: 30_000,
  metrics_retention_hours: 24,
  alert_thresholds: %{
    memory_usage_mb: 800,
    cpu_usage_percent: 80,
    response_time_ms: 100,
    error_rate_percent: 5.0,
    device_failure_rate_percent: 10.0
  },
  # 5 minutes
  alert_cooldown_ms: 5 * 60 * 1000

# Resource manager configuration  
config :snmp_sim, :resource_manager,
  enabled: true,
  max_devices: 10_000,
  max_memory_mb: 1024,
  cleanup_threshold_percent: 80,
  monitoring_interval_ms: 60_000,
  emergency_cleanup_enabled: true

# Device pool configuration
config :snmp_sim, :device_pool,
  optimization_enabled: true,
  tier_system_enabled: true,
  # Requests per monitoring period
  tier_promotion_threshold: 100,
  # Requests per monitoring period
  tier_demotion_threshold: 10,
  cache_cleanup_interval_ms: 5 * 60 * 1000,
  hot_tier_max_devices: 1000,
  warm_tier_max_devices: 5000

# Behavior configuration
config :snmp_sim, :behaviors,
  realistic_counters_enabled: true,
  time_patterns_enabled: true,
  correlations_enabled: true,
  seasonal_patterns_enabled: true,
  device_characteristics_enabled: true

# Test scenarios configuration
config :snmp_sim, :test_scenarios,
  enabled: false,
  default_duration_seconds: 300,
  max_concurrent_scenarios: 10,
  scenario_cleanup_enabled: true

# Health check configuration
config :snmp_sim, :health_check,
  enabled: true,
  port: 4000,
  path: "/health",
  timeout_ms: 5000,
  checks: [
    :memory_usage,
    :device_count,
    :response_time,
    :error_rate,
    :process_health
  ]

# SNMP Server Configuration
config :snmp_ex,
  port: 49152,
  ip: {127, 0, 0, 1}

# Import environment-specific configuration
import_config "#{config_env()}.exs"
