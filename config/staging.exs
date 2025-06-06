# Staging environment configuration
import Config

# Staging overrides - production-like but with lower limits and more debugging
config :snmp_sim,
  # Moderate limits for staging
  max_devices: 5000,
  max_memory_mb: 1024,
  
  # Moderate port range for staging
  port_range_start: 30_000,
  port_range_end: 32_000,
  
  # Moderate timeouts for staging
  idle_timeout_ms: 20 * 60 * 1000,     # 20 minutes
  cleanup_interval_ms: 5 * 60 * 1000,  # 5 minutes
  health_check_interval_ms: 30_000,    # 30 seconds
  
  # Moderate performance settings
  worker_pool_size: 16,
  socket_count: 4,
  optimization_level: :normal,
  
  # Staging features - enable for testing
  enable_error_injection: true,
  enable_telemetry: true,
  enable_performance_monitoring: true,
  enable_persistence: true,
  
  # Staging data directory
  data_dir: "/app/staging_data"

# Staging logging - more verbose than production
config :logger,
  level: :info,
  backends: [:console]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :device_id, :port, :scenario_id, :module, :function],
  colors: [
    enabled: true,
    debug: :cyan,
    info: :normal,
    warning: :yellow,
    error: :red
  ]

# Performance monitoring for staging
config :snmp_sim, :performance_monitor,
  enabled: true,
  collection_interval_ms: 30_000,      # 30 seconds
  metrics_retention_hours: 48,         # 2 days
  alert_thresholds: %{
    memory_usage_mb: 800,              # 80% of 1GB
    cpu_usage_percent: 75,
    response_time_ms: 150,
    error_rate_percent: 3.0,
    device_failure_rate_percent: 8.0
  },
  alert_cooldown_ms: 5 * 60 * 1000     # 5 minutes

# Resource manager for staging
config :snmp_sim, :resource_manager,
  enabled: true,
  max_devices: 5000,
  max_memory_mb: 1024,
  cleanup_threshold_percent: 75,
  monitoring_interval_ms: 60_000,      # 1 minute
  emergency_cleanup_enabled: true

# Device pool for staging
config :snmp_sim, :device_pool,
  optimization_enabled: true,
  tier_system_enabled: true,
  tier_promotion_threshold: 200,       # Moderate threshold
  tier_demotion_threshold: 20,
  cache_cleanup_interval_ms: 5 * 60 * 1000, # 5 minutes
  hot_tier_max_devices: 500,
  warm_tier_max_devices: 2500

# Enable test scenarios for staging validation
config :snmp_sim, :test_scenarios,
  enabled: true,
  default_duration_seconds: 300,       # 5 minutes
  max_concurrent_scenarios: 10,
  scenario_cleanup_enabled: true

# Staging health check configuration
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
    :process_health,
    :disk_space
  ]

# All behavior features enabled for staging testing
config :snmp_sim, :behaviors,
  realistic_counters_enabled: true,
  time_patterns_enabled: true,
  correlations_enabled: true,
  seasonal_patterns_enabled: true,
  device_characteristics_enabled: true

# Staging security settings - slightly more permissive than production
config :snmp_sim, :security,
  enable_rate_limiting: true,
  max_requests_per_second: 5000,
  enable_ip_whitelisting: false,
  allowed_communities: ["public", "private", "staging"],
  enable_audit_logging: true

# Database configuration for staging
config :snmp_sim, :database,
  enabled: true,
  pool_size: 10,
  timeout: 15_000,
  queue_target: 2500,
  queue_interval: 1000

# Staging telemetry and metrics
config :snmp_sim, :telemetry,
  enabled: true,
  metrics_interval_ms: 30_000,
  export_prometheus: true,
  export_influxdb: false,
  retention_policy: "3d"

# Load testing configuration for staging
config :snmp_sim, :load_testing,
  enabled: true,
  max_concurrent_devices: 1000,
  request_rate_per_second: 1000,
  test_duration_minutes: 60,
  ramp_up_duration_minutes: 5,
  scenarios: [
    :device_startup,
    :bulk_operations,
    :error_conditions,
    :resource_exhaustion,
    :cascading_failures
  ]

# Staging-specific debugging features
config :snmp_sim, :debugging,
  enable_request_tracing: true,
  trace_sample_rate: 0.1,              # 10% of requests
  enable_memory_profiling: true,
  profile_interval_minutes: 30,
  enable_slow_query_logging: true,
  slow_query_threshold_ms: 100

# Enhanced error reporting for staging
config :snmp_sim, :error_reporting,
  enabled: true,
  report_internal_errors: true,
  report_performance_issues: true,
  report_resource_warnings: true,
  notification_channels: [:console, :file],
  error_retention_days: 7