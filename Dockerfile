# Multi-stage Dockerfile for SNMPSimEx
# Stage 1: Build environment
FROM hexpm/elixir:1.15.7-erlang-26.1.2-alpine-3.18.4 AS build

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    git \
    nodejs \
    npm

# Set build environment
ENV MIX_ENV=prod

# Create app directory
WORKDIR /app

# Copy mix files
COPY mix.exs mix.lock ./

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Install dependencies
RUN mix deps.get --only=prod && \
    mix deps.compile

# Copy application code
COPY . .

# Compile application
RUN mix compile

# Build release
RUN mix release

# Stage 2: Runtime environment
FROM alpine:3.18.4 AS runtime

# Install runtime dependencies
RUN apk add --no-cache \
    ncurses-libs \
    openssl \
    libgcc \
    libstdc++

# Create non-root user
RUN addgroup -g 1000 snmp && \
    adduser -u 1000 -G snmp -s /bin/sh -D snmp

# Create app directory
WORKDIR /app
RUN chown snmp:snmp /app

# Switch to non-root user
USER snmp

# Copy release from build stage
COPY --from=build --chown=snmp:snmp /app/_build/prod/rel/snmp_sim_ex ./

# Create directories for runtime data
RUN mkdir -p /app/data/logs /app/data/metrics /app/data/profiles

# Expose SNMP ports (30000-39999 range)
EXPOSE 30000-39999/udp

# Expose management/API port
EXPOSE 4000

# Set environment variables
ENV MIX_ENV=prod
ENV SNMP_SIM_EX_HOST=0.0.0.0
ENV SNMP_SIM_EX_PORT_RANGE_START=30000
ENV SNMP_SIM_EX_PORT_RANGE_END=39999
ENV SNMP_SIM_EX_MAX_DEVICES=10000
ENV SNMP_SIM_EX_MAX_MEMORY_MB=1024

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD /app/bin/snmp_sim_ex eval "SNMPSimEx.health_check()" || exit 1

# Start the application
CMD ["/app/bin/snmp_sim_ex", "start"]