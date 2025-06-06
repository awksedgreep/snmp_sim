# Production environment configuration
import Config

# Production overrides for maximum performance and stability
config :snmp_sim,
  # Production device limits
  max_devices: 50_000,
  max_memory_mb: 4096,
  
  # Full port range for production
  port_range_start: 30_000,
  port_range_end: 39_999,
  
  # Production timeouts - longer for stability
  idle_timeout_ms: 60 * 60 * 1000,     # 1 hour
  cleanup_interval_ms: 15 * 60 * 1000,  # 15 minutes
  health_check_interval_ms: 60_000,     # 1 minute
  
  # Maximum performance settings
  worker_pool_size: 32,
  socket_count: 8,
  optimization_level: :aggressive,
  
  # Production features
  enable_error_injection: false,
  enable_telemetry: true,
  enable_performance_monitoring: true,
  enable_persistence: true,
  
  # Production data directory
  data_dir: "/app/data"

# Production logging - minimal and structured
config :logger,
  level: :info,
  backends: [:console]

config :logger, :console,
  format: "$dateT$time $metadata[$level] $message\n",
  metadata: [:request_id, :device_id, :port, :scenario_id],
  colors: [enabled: false]

# Performance monitoring for production
config :snmp_sim, :performance_monitor,
  enabled: true,
  collection_interval_ms: 60_000,      # 1 minute
  metrics_retention_hours: 168,        # 1 week
  alert_thresholds: %{
    memory_usage_mb: 3200,             # 80% of 4GB
    cpu_usage_percent: 85,
    response_time_ms: 200,
    error_rate_percent: 2.0,
    device_failure_rate_percent: 5.0
  },
  alert_cooldown_ms: 15 * 60 * 1000    # 15 minutes

# Resource manager for production
config :snmp_sim, :resource_manager,
  enabled: true,
  max_devices: 50_000,
  max_memory_mb: 4096,
  cleanup_threshold_percent: 85,
  monitoring_interval_ms: 2 * 60 * 1000, # 2 minutes
  emergency_cleanup_enabled: true

# Device pool optimized for production
config :snmp_sim, :device_pool,
  optimization_enabled: true,
  tier_system_enabled: true,
  tier_promotion_threshold: 500,        # Higher threshold for production
  tier_demotion_threshold: 50,
  cache_cleanup_interval_ms: 10 * 60 * 1000, # 10 minutes
  hot_tier_max_devices: 5000,
  warm_tier_max_devices: 25000

# Disable test scenarios in production
config :snmp_sim, :test_scenarios,
  enabled: false,
  default_duration_seconds: 600,
  max_concurrent_scenarios: 20,
  scenario_cleanup_enabled: true

# Production health check configuration
config :snmp_sim, :health_check,
  enabled: true,
  port: 4000,
  path: "/health",
  timeout_ms: 10_000,                   # Longer timeout for production
  checks: [
    :memory_usage,
    :device_count,
    :response_time,
    :error_rate,
    :process_health,
    :disk_space,
    :network_connectivity
  ]

# All behavior features enabled for production
config :snmp_sim, :behaviors,
  realistic_counters_enabled: true,
  time_patterns_enabled: true,
  correlations_enabled: true,
  seasonal_patterns_enabled: true,
  device_characteristics_enabled: true

# Production security settings
config :snmp_sim, :security,
  enable_rate_limiting: true,
  max_requests_per_second: 10000,
  enable_ip_whitelisting: false,
  allowed_communities: ["public", "private"],
  enable_audit_logging: true

# Database connection pool for production persistence
config :snmp_sim, :database,
  enabled: true,
  pool_size: 20,
  timeout: 30_000,
  queue_target: 5000,
  queue_interval: 1000

# Production telemetry and metrics
config :snmp_sim, :telemetry,
  enabled: true,
  metrics_interval_ms: 30_000,
  export_prometheus: true,
  export_influxdb: false,
  retention_policy: "7d"