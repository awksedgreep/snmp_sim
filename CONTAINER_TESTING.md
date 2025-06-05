# SnmpSim Container Testing Guide

This comprehensive guide covers testing SnmpSim in containerized environments using Podman, from small-scale development to large-scale production deployments.

## 🚀 Container Testing Solution Overview

### **Available Test Scripts**

1. **`scripts/test_container.sh`** - Simple 10-device testing environment
2. **`scripts/test_container_hundred.sh`** - Scaled 100-device testing with multiple strategies
3. **Configuration files** - JSON configs for different scales

### **Device Configurations**

| Scale | Script | Devices | Ports | Use Case |
|-------|--------|---------|-------|----------|
| Small | `test_container.sh` | 10 | 30000-32001 | Development, Basic Testing |
| Medium | `test_container_hundred.sh` | 100 | 30000-32004 | Integration Testing, CI/CD |
| Large | Production Setup | 1000+ | Custom Ranges | Production Deployments |

## 📊 Port Mapping Complexity Analysis

### **Small Scale (10 devices)** ✅ **Simple**
```bash
-p 30000:30000/udp -p 30001:30001/udp ... -p 32001:32001/udp
```
**Characteristics:**
- ✅ **Manageable**: 10 individual port mappings
- ✅ **No complexity**: Easy to understand and debug
- ✅ **Direct mapping**: One-to-one port relationship
- ✅ **Perfect for**: Development, learning, small demos

**Command:**
```bash
./scripts/test_container.sh start
```

### **Medium Scale (100 devices)** ⚠️ **Moderate**
```bash
-p 30000-30079:30000-30079/udp -p 31000-31014:31000-31014/udp
```
**Characteristics:**
- ⚠️ **Range mapping**: Much more efficient than individual ports
- ⚠️ **Port conflicts**: Need to ensure host ports are available
- ✅ **Still manageable**: 3-4 port range mappings
- ✅ **Good for**: Integration testing, performance testing

**Commands:**
```bash
./scripts/test_container_hundred.sh ranges start    # Port range strategy
./scripts/test_container_hundred.sh host start      # Host network strategy
./scripts/test_container_hundred.sh offset start    # Port offset strategy
```

### **Large Scale (1000+ devices)** 🚨 **Complex**

**Problems with direct port mapping:**
- 🚨 **Port exhaustion**: Host may not have 1000+ free ports
- 🚨 **Performance overhead**: Container runtime mapping overhead  
- 🚨 **Configuration complexity**: Managing many port ranges
- 🚨 **Resource limits**: System limits on open sockets/ports

**Recommended solutions:**
1. **Host networking**: `--network host` (eliminates mapping complexity)
2. **Multiple containers**: Split devices across containers
3. **Container orchestration**: Use Kubernetes/Docker Swarm
4. **Reverse proxy**: Route through SNMP proxy/load balancer

## 🛠 Quick Start Examples

### **Basic Testing (10 devices)**
Perfect for development and initial testing:

```bash
cd scripts

# Start the environment
./test_container.sh start

# Run automated tests  
./test_container.sh test

# Manual SNMP testing
snmpget -v2c -c public localhost:30000 1.3.6.1.2.1.1.1.0
snmpwalk -v2c -c public localhost:30001 1.3.6.1.2.1.1
snmpbulkget -v2c -c public localhost:31000 1.3.6.1.2.1.2.2.1

# View status and logs
./test_container.sh status
./test_container.sh logs

# Stop when done
./test_container.sh stop
```

**Device Layout:**
- Cable Modems: ports 30000-30004 (5 devices)
- Switches: ports 31000-31002 (3 devices)  
- Routers: ports 32000-32001 (2 devices)
- Management API: port 4000

### **Scaled Testing (100 devices)**
For integration testing and performance validation:

#### **Strategy 1: Host Networking (Simplest)**
```bash
# Start with host networking (recommended)
./test_container_hundred.sh host start

# Run sample tests
./test_container_hundred.sh test

# Test specific devices
snmpget -v2c -c public localhost:30025 1.3.6.1.2.1.1.1.0
snmpwalk -v2c -c public localhost:31007 1.3.6.1.2.1.1
snmpget -v2c -c public localhost:32002 1.3.6.1.2.1.1.5.0
```

#### **Strategy 2: Port Range Mapping**
```bash
# Start with explicit port range mapping
./test_container_hundred.sh ranges start

# Same testing commands as above
./test_container_hundred.sh test
```

#### **Strategy 3: Port Offset Mapping**
```bash
# Start with 10000 port offset to avoid conflicts
./test_container_hundred.sh offset start

# Access devices on offset ports (container port + 10000)
snmpget -v2c -c public localhost:40000 1.3.6.1.2.1.1.1.0  # Container port 30000
snmpget -v2c -c public localhost:41005 1.3.6.1.2.1.1.1.0  # Container port 31005
```

**Device Layout (100 devices):**
- Cable Modems Block 1: ports 30000-30049 (50 devices)
- Cable Modems Block 2: ports 30050-30079 (30 devices)
- Switches: ports 31000-31014 (15 devices)
- Routers: ports 32000-32004 (5 devices)
- Management API: port 4000

### **Production-Like (1000+ devices)**
For large-scale deployments, avoid complex port mapping:

#### **Single Container with Host Network**
```bash
# Build the image first
podman build -t snmp_sim_ex:prod .

# Run with host networking (simplest for large scale)
podman run -d \
  --name snmp_sim_ex_prod \
  --network host \
  -v $(pwd)/config:/app/config:ro \
  -v $(pwd)/priv:/app/priv:ro \
  -e SNMP_SIM_EX_CONFIG_FILE=/app/config/production.json \
  -e SNMP_SIM_EX_HOST=0.0.0.0 \
  -e SNMP_SIM_EX_MAX_DEVICES=1000 \
  -e SNMP_SIM_EX_MAX_MEMORY_MB=2048 \
  snmp_sim_ex:prod

# Test devices across the range
snmpget -v2c -c public localhost:30000 1.3.6.1.2.1.1.1.0
snmpget -v2c -c public localhost:35000 1.3.6.1.2.1.1.1.0
snmpget -v2c -c public localhost:39000 1.3.6.1.2.1.1.1.0
```

#### **Multiple Containers (Scaling Strategy)**
```bash
# Split devices across multiple containers for better resource management
podman run -d --name snmp_block1 --network host \
  -e SNMP_SIM_EX_PORT_RANGE_START=30000 \
  -e SNMP_SIM_EX_PORT_RANGE_END=34999 \
  -e SNMP_SIM_EX_MAX_DEVICES=500 \
  snmp_sim_ex:prod

podman run -d --name snmp_block2 --network host \
  -e SNMP_SIM_EX_PORT_RANGE_START=35000 \
  -e SNMP_SIM_EX_PORT_RANGE_END=39999 \
  -e SNMP_SIM_EX_MAX_DEVICES=500 \
  snmp_sim_ex:prod

# Test devices in different blocks
snmpget -v2c -c public localhost:32000 1.3.6.1.2.1.1.1.0  # Block 1
snmpget -v2c -c public localhost:37000 1.3.6.1.2.1.1.1.0  # Block 2
```

## 🔧 Deployment Strategies Explained

### **1. Host Networking** (`--network host`)
**Best for: Large scale, simplicity, performance**

```bash
podman run -d --name snmp_sim_ex --network host snmp_sim_ex:latest
```

**Pros:**
- ✅ **No port mapping overhead**
- ✅ **Direct access to all ports** 
- ✅ **Best performance**
- ✅ **Simplest configuration**
- ✅ **No port conflicts between containers**

**Cons:**
- ⚠️ **Less network isolation**
- ⚠️ **Container shares host network stack**
- ⚠️ **Port conflicts with host services**

**Use when:**
- Testing/development environments
- Large number of devices (100+)
- Performance is critical
- Network isolation is not required

### **2. Port Range Mapping**
**Best for: Medium scale, controlled environments**

```bash
podman run -d -p 30000-39999:30000-39999/udp snmp_sim_ex:latest
```

**Pros:**
- ✅ **Network isolation maintained**
- ✅ **Efficient for container runtime**
- ✅ **Clear port mapping**
- ✅ **Good for CI/CD pipelines**

**Cons:**
- ⚠️ **Uses many host ports**
- ⚠️ **Potential port conflicts**
- ⚠️ **Complex for very large scales**

**Use when:**
- Medium scale deployments (50-500 devices)
- Need network isolation
- Dedicated test environments
- Port ranges are available

### **3. Port Offset Mapping**
**Best for: Avoiding conflicts, testing multiple instances**

```bash
podman run -d -p 40000-49999:30000-39999/udp snmp_sim_ex:latest
```

**Pros:**
- ✅ **Avoids port conflicts**
- ✅ **Multiple instances possible**
- ✅ **Clear separation**
- ✅ **Good for testing**

**Cons:**
- ⚠️ **More complex configuration**
- ⚠️ **Need to remember offset**
- ⚠️ **Still uses many host ports**

**Use when:**
- Multiple SnmpSim instances
- Port conflicts with other services
- Testing different configurations
- Need clear separation

### **4. Multiple Containers**
**Best for: Very large scale, resource management**

```bash
# Container 1: 500 devices
podman run -d --name snmp1 --network host \
  -e SNMP_SIM_EX_PORT_RANGE_START=30000 \
  -e SNMP_SIM_EX_PORT_RANGE_END=34999 \
  snmp_sim_ex:latest

# Container 2: 500 devices  
podman run -d --name snmp2 --network host \
  -e SNMP_SIM_EX_PORT_RANGE_START=35000 \
  -e SNMP_SIM_EX_PORT_RANGE_END=39999 \
  snmp_sim_ex:latest
```

**Pros:**
- ✅ **Better resource isolation**
- ✅ **Independent scaling**
- ✅ **Fault isolation**
- ✅ **Easier debugging**

**Cons:**
- ⚠️ **More containers to manage**
- ⚠️ **Coordination complexity**
- ⚠️ **Resource overhead**

**Use when:**
- Very large deployments (1000+ devices)
- Need fault isolation
- Different device configurations
- Resource management is important

## 📋 Configuration Files

### **Small Scale Configuration (test_devices.json)**
```json
{
  "snmp_sim_ex": {
    "global_settings": {
      "max_devices": 50,
      "max_memory_mb": 256,
      "host": "0.0.0.0",
      "community": "public"
    },
    "device_groups": [
      {
        "name": "test_cable_modems",
        "device_type": "cable_modem",
        "count": 5,
        "port_range": {"start": 30000, "end": 30004}
      },
      {
        "name": "test_switches", 
        "device_type": "switch",
        "count": 3,
        "port_range": {"start": 31000, "end": 31002}
      }
    ]
  }
}
```

### **Large Scale Configuration (hundred_devices.json)**
```json
{
  "snmp_sim_ex": {
    "global_settings": {
      "max_devices": 100,
      "max_memory_mb": 512,
      "worker_pool_size": 8,
      "socket_count": 4
    },
    "device_groups": [
      {
        "name": "cable_modems_block1",
        "device_type": "cable_modem", 
        "count": 50,
        "port_range": {"start": 30000, "end": 30049}
      },
      {
        "name": "cable_modems_block2",
        "device_type": "cable_modem",
        "count": 30, 
        "port_range": {"start": 30050, "end": 30079}
      }
    ]
  }
}
```

## 🧪 Manual Testing Commands

### **Basic SNMP Operations**
```bash
# Install SNMP tools first (if not already installed)
# Ubuntu/Debian: sudo apt install snmp-utils
# RHEL/CentOS: sudo yum install net-snmp-utils
# macOS: brew install net-snmp

# Basic GET request
snmpget -v2c -c public localhost:30000 1.3.6.1.2.1.1.1.0

# System information walk
snmpwalk -v2c -c public localhost:30000 1.3.6.1.2.1.1

# Interface table bulk request
snmpbulkget -v2c -c public localhost:30000 1.3.6.1.2.1.2.2.1

# Test with timeout and retries
snmpget -v2c -c public -t 5 -r 3 localhost:30000 1.3.6.1.2.1.1.1.0
```

### **Testing Different Device Types**
```bash
# Cable modem (should show DOCSIS-like behavior)
snmpget -v2c -c public localhost:30000 1.3.6.1.2.1.1.1.0
snmpget -v2c -c public localhost:30000 1.3.6.1.2.1.1.5.0

# Switch (should show switch-like interface counts)
snmpget -v2c -c public localhost:31000 1.3.6.1.2.1.1.1.0
snmpwalk -v2c -c public localhost:31000 1.3.6.1.2.1.2.2.1.2

# Router (should show routing-related OIDs)
snmpget -v2c -c public localhost:32000 1.3.6.1.2.1.1.1.0
snmpwalk -v2c -c public localhost:32000 1.3.6.1.2.1.4
```

### **Performance Testing**
```bash
# Test multiple devices rapidly
for port in {30000..30010}; do
  echo "Testing port $port:"
  snmpget -v2c -c public -t 1 localhost:$port 1.3.6.1.2.1.1.1.0
done

# Bulk operations across devices
for port in 30000 30025 30050 31000 32000; do
  echo "Bulk testing port $port:"
  snmpbulkwalk -v2c -c public -t 2 localhost:$port 1.3.6.1.2.1.2.2.1
done

# Stress test with concurrent requests
for i in {1..10}; do
  snmpget -v2c -c public localhost:30000 1.3.6.1.2.1.1.3.0 &
done
wait
```

## 🔍 Monitoring and Debugging

### **Container Status and Logs**
```bash
# Check container status
podman ps -a --filter "name=snmp_sim_ex"

# View logs (last 20 lines)
podman logs snmp_sim_ex_test --tail 20

# Follow logs in real-time
podman logs -f snmp_sim_ex_test

# Open container shell for debugging
podman exec -it snmp_sim_ex_test /bin/sh
```

### **Port Usage Verification**
```bash
# Check which ports are listening (Linux)
netstat -ln | grep :3000
ss -ln | grep :3000

# Check which ports are listening (macOS)
lsof -i :30000
netstat -an | grep 30000

# Test port connectivity
telnet localhost 30000  # Should connect (then Ctrl+C to exit)
nc -u localhost 30000   # UDP test
```

### **Resource Monitoring**
```bash
# Monitor container resource usage
podman stats snmp_sim_ex_test

# Check container processes
podman top snmp_sim_ex_test

# Container details
podman inspect snmp_sim_ex_test

# Health check
podman exec snmp_sim_ex_test /app/bin/snmp_sim_ex eval "SnmpSim.health_check()"
```

### **Network Diagnostics**
```bash
# Check container networking
podman network ls
podman port snmp_sim_ex_test

# Test container connectivity
podman exec snmp_sim_ex_test ping host.containers.internal

# Check iptables rules (if using port mapping)
sudo iptables -L -n | grep 30000
```

## ⚠️ Common Issues and Solutions

### **Port Conflicts**
**Problem:** Port binding errors when starting container
```
Error: cannot listen on the TCP port: listen tcp :30000: bind: address already in use
```

**Solutions:**
1. **Use offset strategy:**
   ```bash
   ./test_container_hundred.sh offset start
   ```

2. **Use host networking:**
   ```bash
   ./test_container_hundred.sh host start
   ```

3. **Find conflicting process:**
   ```bash
   netstat -ln | grep :30000
   lsof -i :30000
   ```

4. **Use different port range:**
   ```bash
   # Modify config to use ports 40000+ instead of 30000+
   ```

### **Container Startup Slow**
**Problem:** Container takes long time to start with many devices

**Solutions:**
1. **Increase timeout:** Allow 60+ seconds for 100 devices
2. **Monitor startup:** 
   ```bash
   ./test_container_hundred.sh logs -f
   ```
3. **Check health:**
   ```bash
   podman exec container_name /app/bin/snmp_sim_ex eval "SnmpSim.health_check()"
   ```
4. **Reduce device count** for testing

### **SNMP Timeouts**
**Problem:** SNMP requests timeout or fail

**Solutions:**
1. **Verify container status:**
   ```bash
   ./test_container.sh status
   ```

2. **Check port mapping:**
   ```bash
   podman port snmp_sim_ex_test
   ```

3. **Use longer timeout:**
   ```bash
   snmpget -t 5 -r 3 -v2c -c public localhost:30000 1.3.6.1.2.1.1.1.0
   ```

4. **Test container networking:**
   ```bash
   podman exec snmp_sim_ex_test netstat -ln | grep :30000
   ```

5. **Check firewall/iptables:**
   ```bash
   sudo iptables -L -n | grep 30000
   ```

### **Memory Issues**
**Problem:** Container uses too much memory or gets OOM killed

**Solutions:**
1. **Monitor usage:**
   ```bash
   podman stats snmp_sim_ex_test
   ```

2. **Adjust memory limits in config:**
   ```json
   "max_memory_mb": 512
   ```

3. **Use multiple smaller containers:**
   ```bash
   # Split 1000 devices into 2 containers of 500 each
   ```

4. **Tune worker pools:**
   ```json
   "worker_pool_size": 4,
   "socket_count": 2
   ```

### **Permission Issues**
**Problem:** Container cannot bind to ports or access files

**Solutions:**
1. **Check SELinux/AppArmor:**
   ```bash
   sudo setenforce 0  # Temporarily disable SELinux
   ```

2. **Use correct volume mounts:**
   ```bash
   -v $(pwd)/config:/app/config:ro,Z  # SELinux context
   ```

3. **Run with appropriate user:**
   ```bash
   --user $(id -u):$(id -g)
   ```

## 🏭 Production Considerations

### **Security**
- ✅ **Change default community strings**
- ✅ **Use SNMPv3 with authentication**
- ✅ **Implement rate limiting**
- ✅ **Network segmentation**
- ✅ **Regular security updates**

### **Persistence**
```bash
# Mount volumes for persistent data
-v snmp_data:/app/data \
-v snmp_config:/app/config \
-v snmp_logs:/app/logs
```

### **Monitoring Integration**
```bash
# Enable Prometheus metrics
-e SNMP_SIM_EX_ENABLE_TELEMETRY=true \
-e SNMP_SIM_EX_PROMETHEUS_PORT=9090

# Mount Grafana dashboards
-v ./monitoring/grafana:/etc/grafana/provisioning
```

### **High Availability**
- ✅ **Multiple container instances**
- ✅ **Load balancer in front**
- ✅ **Health check endpoints**
- ✅ **Graceful shutdown handling**
- ✅ **Backup and restore procedures**

### **Scaling Strategies**

#### **Horizontal Scaling (Recommended)**
```bash
# Multiple containers with different port ranges
podman run -d --name snmp1 -e PORT_RANGE_START=30000 -e PORT_RANGE_END=34999
podman run -d --name snmp2 -e PORT_RANGE_START=35000 -e PORT_RANGE_END=39999
```

#### **Kubernetes Deployment**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: snmp-sim-ex
spec:
  replicas: 3
  selector:
    matchLabels:
      app: snmp-sim-ex
  template:
    spec:
      hostNetwork: true  # For large port ranges
      containers:
      - name: snmp-sim-ex
        image: snmp_sim_ex:latest
        env:
        - name: SNMP_SIM_EX_HOST
          value: "0.0.0.0"
```

#### **Container Orchestration Benefits**
- ✅ **Automatic scaling**
- ✅ **Service discovery**
- ✅ **Health monitoring**
- ✅ **Rolling updates**
- ✅ **Resource management**

## 📚 Examples for Different Use Cases

### **Development Environment**
```bash
# Quick start for development
./scripts/test_container.sh start
./scripts/test_container.sh test
```

### **Integration Testing**
```bash
# Larger scale for integration tests
./scripts/test_container_hundred.sh host start
./scripts/test_container_hundred.sh test

# Automated testing in CI/CD
podman run --rm --network host \
  -e SNMP_SIM_EX_CONFIG_FILE=/app/config/ci_test.json \
  snmp_sim_ex:test
```

### **Performance Testing**
```bash
# Large scale performance testing
./scripts/test_container_hundred.sh ranges start

# Load testing with multiple clients
for i in {1..100}; do
  snmpget -v2c -c public localhost:$((30000 + i % 50)) 1.3.6.1.2.1.1.1.0 &
done
wait
```

### **Demo Environment**
```bash
# Easy demo setup
./scripts/test_container.sh start

# Show different device types
echo "Cable Modem:" && snmpget -v2c -c public localhost:30000 1.3.6.1.2.1.1.1.0
echo "Switch:" && snmpget -v2c -c public localhost:31000 1.3.6.1.2.1.1.1.0
echo "Router:" && snmpget -v2c -c public localhost:32000 1.3.6.1.2.1.1.1.0
```

## 🎯 Summary and Recommendations

### **For Different Scales:**

| Devices | Recommended Strategy | Command | Use Case |
|---------|---------------------|---------|----------|
| 1-10 | Individual Port Mapping | `./test_container.sh start` | Development, Learning |
| 10-100 | Host Networking | `./test_container_hundred.sh host start` | Testing, Integration |
| 100-500 | Port Range Mapping | `./test_container_hundred.sh ranges start` | CI/CD, Staging |
| 500+ | Multiple Containers | Custom deployment | Production |
| 1000+ | Container Orchestration | Kubernetes/Swarm | Enterprise |

### **Key Takeaways:**

1. **Start Simple:** Use the 10-device setup for initial learning and development
2. **Scale Gradually:** Move to 100-device setup when you need more comprehensive testing
3. **Choose Strategy Wisely:** Host networking is simplest for large scales
4. **Plan for Production:** Use container orchestration for enterprise deployments
5. **Monitor and Debug:** Use the provided monitoring tools and debugging techniques

The port mapping complexity is **definitely manageable** for hundreds of devices with the right strategy, and for thousands of devices, you'd typically move to orchestration platforms that handle the complexity for you.

This guide provides everything you need to test SnmpSim at any scale! 🚀