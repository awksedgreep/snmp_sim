import Config

# Runtime configuration for SNMPSimEx
# This file is evaluated at runtime and allows for dynamic configuration
# based on environment variables and system state.

# Basic application configuration
config :snmp_sim_ex,
  # Environment settings
  environment: System.get_env("MIX_ENV", "prod"),
  
  # SNMP configuration
  snmp_host: System.get_env("SNMP_SIM_EX_HOST", "0.0.0.0"),
  snmp_community: System.get_env("SNMP_SIM_EX_COMMUNITY", "public"),
  
  # Port range configuration
  port_range_start: String.to_integer(System.get_env("SNMP_SIM_EX_PORT_RANGE_START", "30000")),
  port_range_end: String.to_integer(System.get_env("SNMP_SIM_EX_PORT_RANGE_END", "39999")),
  
  # Device limits
  max_devices: String.to_integer(System.get_env("SNMP_SIM_EX_MAX_DEVICES", "10000")),
  max_memory_mb: String.to_integer(System.get_env("SNMP_SIM_EX_MAX_MEMORY_MB", "1024")),
  
  # Performance settings
  idle_timeout_ms: String.to_integer(System.get_env("SNMP_SIM_EX_IDLE_TIMEOUT_MS", "1800000")), # 30 minutes
  cleanup_interval_ms: String.to_integer(System.get_env("SNMP_SIM_EX_CLEANUP_INTERVAL_MS", "300000")), # 5 minutes
  
  # Worker pool configuration
  worker_pool_size: String.to_integer(System.get_env("SNMP_SIM_EX_WORKER_POOL_SIZE", "16")),
  socket_count: String.to_integer(System.get_env("SNMP_SIM_EX_SOCKET_COUNT", "4")),
  
  # Monitoring and telemetry
  enable_telemetry: System.get_env("SNMP_SIM_EX_ENABLE_TELEMETRY", "true") == "true",
  telemetry_host: System.get_env("SNMP_SIM_EX_TELEMETRY_HOST", "localhost"),
  telemetry_port: String.to_integer(System.get_env("SNMP_SIM_EX_TELEMETRY_PORT", "4000")),
  
  # Data persistence
  data_dir: System.get_env("SNMP_SIM_EX_DATA_DIR", "/app/data"),
  profile_cache_ttl_ms: String.to_integer(System.get_env("SNMP_SIM_EX_PROFILE_CACHE_TTL_MS", "3600000")), # 1 hour
  
  # Error injection settings (for testing)
  enable_error_injection: System.get_env("SNMP_SIM_EX_ENABLE_ERROR_INJECTION", "false") == "true",
  default_packet_loss_rate: String.to_float(System.get_env("SNMP_SIM_EX_DEFAULT_PACKET_LOSS_RATE", "0.0")),
  default_timeout_rate: String.to_float(System.get_env("SNMP_SIM_EX_DEFAULT_TIMEOUT_RATE", "0.0"))

# Logger configuration
log_level = 
  case System.get_env("SNMP_SIM_EX_LOG_LEVEL", "info") do
    "debug" -> :debug
    "info" -> :info
    "warn" -> :warning
    "error" -> :error
    _ -> :info
  end

config :logger,
  level: log_level,
  backends: [:console]

# Console logger configuration
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :device_id, :port, :scenario_id]

# File logger configuration (if enabled)
if System.get_env("SNMP_SIM_EX_ENABLE_FILE_LOGGING", "false") == "true" do
  log_path = System.get_env("SNMP_SIM_EX_LOG_PATH", "/app/data/logs/snmp_sim_ex.log")
  
  config :logger,
    backends: [:console, {LoggerFileBackend, :info_log}]

  config :logger, :info_log,
    path: log_path,
    level: log_level,
    format: "$dateT$time $metadata[$level] $message\n",
    metadata: [:request_id, :device_id, :port, :scenario_id]
end

# Performance monitoring configuration
if System.get_env("SNMP_SIM_EX_ENABLE_PERFORMANCE_MONITORING", "true") == "true" do
  config :snmp_sim_ex, :performance_monitor,
    enabled: true,
    collection_interval_ms: String.to_integer(System.get_env("SNMP_SIM_EX_PERF_COLLECTION_INTERVAL_MS", "30000")),
    alert_thresholds: %{
      memory_usage_mb: String.to_integer(System.get_env("SNMP_SIM_EX_ALERT_MEMORY_THRESHOLD_MB", "800")),
      cpu_usage_percent: String.to_integer(System.get_env("SNMP_SIM_EX_ALERT_CPU_THRESHOLD_PERCENT", "80")),
      response_time_ms: String.to_integer(System.get_env("SNMP_SIM_EX_ALERT_RESPONSE_TIME_MS", "100")),
      error_rate_percent: String.to_float(System.get_env("SNMP_SIM_EX_ALERT_ERROR_RATE_PERCENT", "5.0"))
    }
end

# Resource manager configuration
config :snmp_sim_ex, :resource_manager,
  max_devices: String.to_integer(System.get_env("SNMP_SIM_EX_MAX_DEVICES", "10000")),
  max_memory_mb: String.to_integer(System.get_env("SNMP_SIM_EX_MAX_MEMORY_MB", "1024")),
  cleanup_threshold_percent: String.to_integer(System.get_env("SNMP_SIM_EX_CLEANUP_THRESHOLD_PERCENT", "80")),
  monitoring_interval_ms: String.to_integer(System.get_env("SNMP_SIM_EX_RESOURCE_MONITORING_INTERVAL_MS", "60000"))

# Device pool configuration
config :snmp_sim_ex, :device_pool,
  tier_promotion_threshold: String.to_integer(System.get_env("SNMP_SIM_EX_TIER_PROMOTION_THRESHOLD", "100")),
  tier_demotion_threshold: String.to_integer(System.get_env("SNMP_SIM_EX_TIER_DEMOTION_THRESHOLD", "10")),
  cache_cleanup_interval_ms: String.to_integer(System.get_env("SNMP_SIM_EX_CACHE_CLEANUP_INTERVAL_MS", "300000"))

# Development and testing configurations
if config_env() == :dev do
  config :snmp_sim_ex,
    max_devices: 100,
    max_memory_mb: 256,
    port_range_start: 30000,
    port_range_end: 30100
end

if config_env() == :test do
  config :snmp_sim_ex,
    max_devices: 50,
    max_memory_mb: 128,
    port_range_start: 40000,
    port_range_end: 40050,
    idle_timeout_ms: 5000,
    cleanup_interval_ms: 1000

  config :logger,
    level: :warning
end

# Health check endpoint configuration
if System.get_env("SNMP_SIM_EX_ENABLE_HEALTH_ENDPOINT", "true") == "true" do
  config :snmp_sim_ex, :health_check,
    enabled: true,
    port: String.to_integer(System.get_env("SNMP_SIM_EX_HEALTH_PORT", "4000")),
    path: System.get_env("SNMP_SIM_EX_HEALTH_PATH", "/health")
end