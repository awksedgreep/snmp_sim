# Container Deployment Guide

This guide covers deploying SNMPSimEx in containerized environments including Docker, Docker Compose, Kubernetes, and cloud platforms.

## Quick Start

### 1. Pull and Run (Simplest)

```bash
# Pull the latest image
docker pull snmp-sim-ex:latest

# Run with basic configuration
docker run -d \
  --name snmp-simulator \
  -p 30000-30999:30000-30999/udp \
  -p 4000:4000 \
  -e SNMP_SIM_EX_MAX_DEVICES=1000 \
  -e SNMP_SIM_EX_DEVICE_COUNT=100 \
  snmp-sim-ex:latest
```

### 2. Quick Test

```bash
# Test the running container
snmpget -v2c -c public localhost:30001 1.3.6.1.2.1.1.1.0

# Check health
curl http://localhost:4000/health
```

## Docker Deployment

### Basic Docker Run

```bash
# Basic deployment with environment variables
docker run -d \
  --name snmp-sim-ex \
  --restart unless-stopped \
  -p 30000-35000:30000-35000/udp \
  -p 4000:4000 \
  -e SNMP_SIM_EX_MAX_DEVICES=5000 \
  -e SNMP_SIM_EX_MAX_MEMORY_MB=1024 \
  -e SNMP_SIM_EX_DEVICE_COUNT=1000 \
  -e SNMP_SIM_EX_COMMUNITY=public \
  -e SNMP_SIM_EX_LOG_LEVEL=info \
  -v snmp_data:/app/data \
  snmp-sim-ex:latest
```

### Advanced Docker Run with Configuration File

```bash
# Create configuration directory
mkdir -p ./config
cp config/sample_devices.yaml ./config/devices.yaml

# Edit configuration as needed
vim ./config/devices.yaml

# Run with configuration file
docker run -d \
  --name snmp-sim-ex-advanced \
  --restart unless-stopped \
  -p 30000-39999:30000-39999/udp \
  -p 4000:4000 \
  -e SNMP_SIM_EX_CONFIG_FILE=/app/config/devices.yaml \
  -v $(pwd)/config:/app/config:ro \
  -v $(pwd)/walks:/app/priv/walks:ro \
  -v snmp_data:/app/data \
  snmp-sim-ex:latest
```

### Docker with Custom Walk Files

```bash
# Prepare custom walk files
mkdir -p ./custom_walks
cp your_device.walk ./custom_walks/

# Run with custom walks
docker run -d \
  --name snmp-sim-custom \
  -p 30000-30099:30000-30099/udp \
  -p 4000:4000 \
  -e SNMP_SIM_EX_DEVICE_COUNT=100 \
  -e SNMP_SIM_EX_WALK_FILE=priv/walks/your_device.walk \
  -v $(pwd)/custom_walks:/app/priv/walks:ro \
  -v snmp_data:/app/data \
  snmp-sim-ex:latest
```

## Docker Compose Deployment

### Production Docker Compose

Create `docker-compose.yml`:

```yaml
version: '3.8'

services:
  snmp-simulator:
    image: snmp-sim-ex:latest
    container_name: snmp_sim_ex_prod
    hostname: snmp-simulator
    restart: unless-stopped
    ports:
      - "30000-39999:30000-39999/udp"
      - "4000:4000"
    environment:
      - MIX_ENV=prod
      - SNMP_SIM_EX_HOST=0.0.0.0
      - SNMP_SIM_EX_MAX_DEVICES=10000
      - SNMP_SIM_EX_MAX_MEMORY_MB=2048
      - SNMP_SIM_EX_CONFIG_FILE=/app/config/production.yaml
    env_file:
      - .env
    volumes:
      - ./config:/app/config:ro
      - ./custom_walks:/app/priv/walks:ro
      - snmp_data:/app/data
      - snmp_logs:/app/logs
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    deploy:
      resources:
        limits:
          memory: 2.5G
          cpus: '2.0'
        reservations:
          memory: 1G
          cpus: '0.5'
    networks:
      - snmp_network

  # Optional: Monitoring stack
  prometheus:
    image: prom/prometheus:latest
    container_name: snmp_prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    networks:
      - snmp_network
    profiles: ["monitoring"]

  grafana:
    image: grafana/grafana:latest
    container_name: snmp_grafana
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - grafana_data:/var/lib/grafana
      - ./monitoring/grafana:/etc/grafana/provisioning:ro
    networks:
      - snmp_network
    profiles: ["monitoring"]

volumes:
  snmp_data:
    driver: local
  snmp_logs:
    driver: local
  prometheus_data:
    driver: local
  grafana_data:
    driver: local

networks:
  snmp_network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
```

### Development Docker Compose

Create `docker-compose.dev.yml`:

```yaml
version: '3.8'

services:
  snmp-simulator-dev:
    build:
      context: .
      dockerfile: Dockerfile.dev
    container_name: snmp_sim_ex_dev
    ports:
      - "30000-30999:30000-30999/udp"
      - "4000:4000"
    environment:
      - MIX_ENV=dev
      - SNMP_SIM_EX_MAX_DEVICES=100
      - SNMP_SIM_EX_DEVICE_COUNT=50
      - SNMP_SIM_EX_LOG_LEVEL=debug
    volumes:
      - .:/app
      - mix_deps:/app/deps
      - mix_build:/app/_build
    working_dir: /app
    command: ["mix", "run", "--no-halt"]
    networks:
      - snmp_dev_network

volumes:
  mix_deps:
  mix_build:

networks:
  snmp_dev_network:
    driver: bridge
```

### Running Docker Compose

```bash
# Production deployment
docker-compose up -d

# With monitoring stack
docker-compose --profile monitoring up -d

# Development deployment
docker-compose -f docker-compose.dev.yml up -d

# View logs
docker-compose logs -f snmp-simulator

# Stop deployment
docker-compose down

# Stop with volume cleanup
docker-compose down -v
```

## Environment Configuration

### Complete Environment File (.env)

```bash
# Core Settings
SNMP_SIM_EX_HOST=0.0.0.0
SNMP_SIM_EX_COMMUNITY=public
SNMP_SIM_EX_MAX_DEVICES=10000
SNMP_SIM_EX_MAX_MEMORY_MB=2048

# Port Configuration
SNMP_SIM_EX_PORT_RANGE_START=30000
SNMP_SIM_EX_PORT_RANGE_END=39999

# Device Configuration
SNMP_SIM_EX_DEVICE_COUNT=5000
SNMP_SIM_EX_WALK_FILE=priv/walks/cable_modem.walk

# Performance Settings
SNMP_SIM_EX_WORKER_POOL_SIZE=32
SNMP_SIM_EX_SOCKET_COUNT=8
SNMP_SIM_EX_OPTIMIZATION_LEVEL=aggressive

# Monitoring
SNMP_SIM_EX_ENABLE_TELEMETRY=true
SNMP_SIM_EX_ENABLE_PERFORMANCE_MONITORING=true
SNMP_SIM_EX_HEALTH_PORT=4000

# Logging
SNMP_SIM_EX_LOG_LEVEL=info
SNMP_SIM_EX_ENABLE_FILE_LOGGING=true
SNMP_SIM_EX_LOG_PATH=/app/logs/snmp_sim_ex.log

# Data Persistence
SNMP_SIM_EX_DATA_DIR=/app/data
```

### Configuration File Deployment

Create `config/production.yaml`:

```yaml
snmp_sim_ex:
  global_settings:
    max_devices: 10000
    max_memory_mb: 2048
    enable_telemetry: true
    enable_performance_monitoring: true
    worker_pool_size: 32
    socket_count: 8

  device_groups:
    - name: cable_modems
      device_type: cable_modem
      count: 8000
      port_range:
        start: 30000
        end: 37999
      community: public
      walk_file: priv/walks/cable_modem.walk
      behaviors:
        - realistic_counters
        - time_patterns

    - name: switches
      device_type: switch
      count: 1500
      port_range:
        start: 38000
        end: 39499
      community: private
      walk_file: priv/walks/switch.walk
      behaviors:
        - realistic_counters
        - correlations

    - name: routers
      device_type: router
      count: 500
      port_range:
        start: 39500
        end: 39999
      community: public
      walk_file: priv/walks/router.walk

  monitoring:
    health_check:
      enabled: true
      port: 4000
      path: /health
    performance_monitor:
      collection_interval_ms: 60000
      alert_thresholds:
        memory_usage_mb: 1600
        response_time_ms: 100
        error_rate_percent: 2.0
```

## Kubernetes Deployment

### Basic Kubernetes Deployment

Create `k8s/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: snmp-sim-ex
  labels:
    app: snmp-sim-ex
spec:
  replicas: 1
  selector:
    matchLabels:
      app: snmp-sim-ex
  template:
    metadata:
      labels:
        app: snmp-sim-ex
    spec:
      containers:
      - name: snmp-sim-ex
        image: snmp-sim-ex:latest
        ports:
        - containerPort: 4000
          name: health
        - containerPort: 30000
          protocol: UDP
          name: snmp-start
        env:
        - name: SNMP_SIM_EX_HOST
          value: "0.0.0.0"
        - name: SNMP_SIM_EX_MAX_DEVICES
          value: "5000"
        - name: SNMP_SIM_EX_MAX_MEMORY_MB
          value: "1024"
        - name: SNMP_SIM_EX_CONFIG_FILE
          value: "/app/config/k8s-config.yaml"
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
        volumeMounts:
        - name: config-volume
          mountPath: /app/config
          readOnly: true
        - name: data-volume
          mountPath: /app/data
        livenessProbe:
          httpGet:
            path: /health
            port: 4000
          initialDelaySeconds: 30
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /health
            port: 4000
          initialDelaySeconds: 10
          periodSeconds: 10
      volumes:
      - name: config-volume
        configMap:
          name: snmp-sim-ex-config
      - name: data-volume
        persistentVolumeClaim:
          claimName: snmp-sim-ex-data
---
apiVersion: v1
kind: Service
metadata:
  name: snmp-sim-ex-service
spec:
  selector:
    app: snmp-sim-ex
  ports:
  - name: health
    port: 4000
    targetPort: 4000
  - name: snmp
    port: 30000
    targetPort: 30000
    protocol: UDP
  type: LoadBalancer
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: snmp-sim-ex-config
data:
  k8s-config.yaml: |
    snmp_sim_ex:
      global_settings:
        max_devices: 5000
        max_memory_mb: 1024
        enable_telemetry: true
      device_groups:
        - name: k8s_devices
          device_type: cable_modem
          count: 1000
          port_range:
            start: 30000
            end: 30999
          community: public
          walk_file: priv/walks/cable_modem.walk
      monitoring:
        health_check:
          enabled: true
          port: 4000
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: snmp-sim-ex-data
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
```

### Deploy to Kubernetes

```bash
# Apply the deployment
kubectl apply -f k8s/deployment.yaml

# Check deployment status
kubectl get deployments
kubectl get pods
kubectl get services

# View logs
kubectl logs -f deployment/snmp-sim-ex

# Scale deployment
kubectl scale deployment snmp-sim-ex --replicas=3

# Update deployment
kubectl set image deployment/snmp-sim-ex snmp-sim-ex=snmp-sim-ex:v2

# Delete deployment
kubectl delete -f k8s/deployment.yaml
```

### Kubernetes with Horizontal Pod Autoscaler

Create `k8s/hpa.yaml`:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: snmp-sim-ex-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: snmp-sim-ex
  minReplicas: 1
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

```bash
# Apply HPA
kubectl apply -f k8s/hpa.yaml

# Check HPA status
kubectl get hpa
```

## Cloud Platform Deployment

### AWS ECS Deployment

Create `aws/task-definition.json`:

```json
{
  "family": "snmp-sim-ex",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "1024",
  "memory": "2048",
  "executionRoleArn": "arn:aws:iam::ACCOUNT:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::ACCOUNT:role/ecsTaskRole",
  "containerDefinitions": [
    {
      "name": "snmp-sim-ex",
      "image": "YOUR_ECR_REPO/snmp-sim-ex:latest",
      "portMappings": [
        {
          "containerPort": 4000,
          "protocol": "tcp"
        },
        {
          "containerPort": 30000,
          "protocol": "udp"
        }
      ],
      "environment": [
        {
          "name": "SNMP_SIM_EX_MAX_DEVICES",
          "value": "5000"
        },
        {
          "name": "SNMP_SIM_EX_MAX_MEMORY_MB",
          "value": "1024"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/snmp-sim-ex",
          "awslogs-region": "us-west-2",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "mountPoints": [
        {
          "sourceVolume": "efs-data",
          "containerPath": "/app/data"
        }
      ]
    }
  ],
  "volumes": [
    {
      "name": "efs-data",
      "efsVolumeConfiguration": {
        "fileSystemId": "fs-XXXXXXXXX"
      }
    }
  ]
}
```

### Google Cloud Run Deployment

```bash
# Build and push to Google Container Registry
gcloud builds submit --tag gcr.io/PROJECT_ID/snmp-sim-ex

# Deploy to Cloud Run
gcloud run deploy snmp-sim-ex \
  --image gcr.io/PROJECT_ID/snmp-sim-ex \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated \
  --port 4000 \
  --memory 2Gi \
  --cpu 1 \
  --set-env-vars SNMP_SIM_EX_MAX_DEVICES=5000,SNMP_SIM_EX_MAX_MEMORY_MB=1024
```

### Azure Container Instances

```bash
# Create resource group
az group create --name snmp-sim-ex-rg --location eastus

# Deploy container
az container create \
  --resource-group snmp-sim-ex-rg \
  --name snmp-sim-ex \
  --image snmp-sim-ex:latest \
  --ports 4000 30000 \
  --protocol TCP UDP \
  --cpu 1 \
  --memory 2 \
  --environment-variables \
    SNMP_SIM_EX_MAX_DEVICES=5000 \
    SNMP_SIM_EX_MAX_MEMORY_MB=1024 \
  --restart-policy Always
```

## Monitoring and Observability

### Health Check Monitoring

```bash
# Basic health check
curl http://localhost:4000/health

# Health check with timeout
timeout 5 curl -f http://localhost:4000/health || echo "Health check failed"

# Docker health check script
#!/bin/bash
response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:4000/health)
if [ $response = "200" ]; then
  exit 0
else
  exit 1
fi
```

### Prometheus Monitoring

Create `monitoring/prometheus.yml`:

```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'snmp-sim-ex'
    static_configs:
      - targets: ['snmp-simulator:4000']
    metrics_path: '/metrics'
    scrape_interval: 30s
```

### Grafana Dashboard

Create `monitoring/grafana/dashboards/snmp-sim-ex.json`:

```json
{
  "dashboard": {
    "title": "SNMPSimEx Dashboard",
    "panels": [
      {
        "title": "Active Devices",
        "type": "stat",
        "targets": [
          {
            "expr": "snmp_sim_ex_active_devices"
          }
        ]
      },
      {
        "title": "Requests per Second",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(snmp_sim_ex_requests_total[5m])"
          }
        ]
      },
      {
        "title": "Memory Usage",
        "type": "graph",
        "targets": [
          {
            "expr": "snmp_sim_ex_memory_usage_bytes"
          }
        ]
      }
    ]
  }
}
```

## Troubleshooting

### Common Issues

#### Container Won't Start
```bash
# Check container logs
docker logs snmp-sim-ex

# Check resource limits
docker stats snmp-sim-ex

# Verify configuration
docker exec snmp-sim-ex cat /app/config/devices.yaml
```

#### Port Binding Issues
```bash
# Check port conflicts
netstat -an | grep 30000

# Use different port range
docker run -e SNMP_SIM_EX_PORT_RANGE_START=40000 snmp-sim-ex
```

#### Memory Issues
```bash
# Monitor memory usage
docker exec snmp-sim-ex cat /proc/meminfo

# Adjust memory limits
docker run -m 2g snmp-sim-ex
```

#### Performance Issues
```bash
# Check CPU usage
docker exec snmp-sim-ex top

# Adjust worker settings
docker run -e SNMP_SIM_EX_WORKER_POOL_SIZE=64 snmp-sim-ex
```

### Debug Mode

```bash
# Run with debug logging
docker run -e SNMP_SIM_EX_LOG_LEVEL=debug snmp-sim-ex

# Interactive debugging
docker run -it --entrypoint /bin/sh snmp-sim-ex

# Attach to running container
docker exec -it snmp-sim-ex /bin/sh
```

## Security Considerations

### Network Security
- Use internal networks for container communication
- Expose only necessary ports
- Implement proper firewall rules
- Use TLS for management interfaces

### Container Security
- Run containers as non-root user
- Use read-only filesystems where possible
- Implement resource limits
- Regularly update base images

### Configuration Security
- Store secrets in secure secret management systems
- Use environment variables for sensitive data
- Implement proper access controls
- Audit configuration changes

## Performance Optimization

### Container Optimization
```dockerfile
# Use multi-stage builds
FROM elixir:1.18-alpine AS builder
# ... build stage

FROM alpine:3.18 AS runtime
# ... minimal runtime
```

### Resource Allocation
```yaml
# Docker Compose resource limits
deploy:
  resources:
    limits:
      memory: 4G
      cpus: '2.0'
    reservations:
      memory: 1G
      cpus: '0.5'
```

### Network Optimization
```bash
# Optimize for high UDP throughput
docker run --sysctl net.core.rmem_max=134217728 snmp-sim-ex
```

This comprehensive container deployment guide covers all major containerization scenarios from simple Docker runs to complex Kubernetes deployments, providing everything needed to deploy SNMPSimEx in any containerized environment.