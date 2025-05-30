# SNMPSimEx Container Testing Scripts

This directory contains scripts for testing SNMPSimEx in containerized environments using Podman.

## Quick Start (10 Devices)

For basic testing with a small number of devices:

```bash
# Start the test environment  
./test_container.sh start

# Run SNMP tests
./test_container.sh test

# View status
./test_container.sh status

# Stop when done
./test_container.sh stop
```

## Scaled Testing (100 Devices)

For testing with a hundred devices, there are three strategies:

### 1. Host Networking (Simplest)
```bash
./test_container_hundred.sh host start
./test_container_hundred.sh test
```

### 2. Port Range Mapping
```bash  
./test_container_hundred.sh ranges start
./test_container_hundred.sh test
```

### 3. Port Offset Mapping
```bash
./test_container_hundred.sh offset start
# Access devices on offset ports (container port + 10000)
snmpget -v2c -c public localhost:40000 1.3.6.1.2.1.1.1.0
```

## Port Mapping Complexity

### Small Scale (10 devices)
- **Simple**: Map individual ports explicitly
- **Manageable**: Each port mapped individually
- **Example**: `-p 30000:30000/udp -p 30001:30001/udp`

### Medium Scale (100 devices)  
- **Range Mapping**: Map entire port ranges efficiently
- **Example**: `-p 30000-30079:30000-30079/udp`
- **Pro**: Efficient for container runtime
- **Con**: Uses many host ports

### Large Scale (1000+ devices)
For production deployments with many devices, consider:

1. **Host Networking**: `--network host`
   - Simplest approach
   - No port mapping overhead
   - Direct access to all ports

2. **Multiple Containers**: Split devices across containers
   ```bash
   # Container 1: ports 30000-30999
   # Container 2: ports 31000-31999  
   # Container 3: ports 32000-32999
   ```

3. **Container Orchestration**: Use Kubernetes or Docker Swarm
   - Service discovery
   - Load balancing
   - Automatic scaling

4. **Reverse Proxy**: Route SNMP traffic through proxy
   - Single entry point
   - SSL termination
   - Rate limiting

## Configuration Files

### test_devices.json (10 devices)
- 5 Cable Modems: ports 30000-30004
- 3 Switches: ports 31000-31002
- 2 Routers: ports 32000-32001

### hundred_devices.json (100 devices)
- 50 Cable Modems: ports 30000-30049  
- 30 Cable Modems: ports 30050-30079
- 15 Switches: ports 31000-31014
- 5 Routers: ports 32000-32004

## Manual Testing Commands

Once the container is running, test with standard SNMP tools:

```bash
# Install SNMP tools (if not already installed)
# Ubuntu/Debian: sudo apt install snmp-utils
# RHEL/CentOS: sudo yum install net-snmp-utils  
# macOS: brew install net-snmp

# Basic GET request
snmpget -v2c -c public localhost:30000 1.3.6.1.2.1.1.1.0

# Walk the system tree
snmpwalk -v2c -c public localhost:30000 1.3.6.1.2.1.1

# GETBULK request  
snmpbulkget -v2c -c public localhost:30000 1.3.6.1.2.1.2.2.1

# Test different device types
snmpget -v2c -c public localhost:31000 1.3.6.1.2.1.1.5.0  # Switch
snmpget -v2c -c public localhost:32000 1.3.6.1.2.1.1.1.0  # Router
```

## Monitoring and Debugging

```bash
# View container logs
./test_container.sh logs

# Open container shell
./test_container.sh shell

# Check port usage on host
netstat -ln | grep :3000
# or
ss -ln | grep :3000

# Monitor container resources
podman stats snmp_sim_ex_test
```

## Common Issues and Solutions

### Port Conflicts
If you get port binding errors:
1. Use the offset strategy: `./test_container_hundred.sh offset start`
2. Use host networking: `./test_container_hundred.sh host start`
3. Check for conflicting services: `netstat -ln | grep :30000`

### Container Startup Slow
For hundred devices, startup takes longer:
- Allow 60+ seconds for full initialization
- Monitor logs: `./test_container_hundred.sh logs -f`
- Check health: `podman exec container_name /app/bin/snmp_sim_ex eval "SNMPSimEx.health_check()"`

### SNMP Timeouts
If SNMP requests timeout:
1. Verify container is running: `./test_container.sh status`
2. Check port mapping: `podman port container_name`
3. Test with longer timeout: `snmpget -t 5 -r 3 ...`
4. Check firewall settings

### Memory Usage
For large deployments:
- Monitor usage: `podman stats`
- Adjust limits in config: `max_memory_mb`
- Use multiple smaller containers instead of one large container

## Production Considerations

When moving from testing to production:

1. **Security**: Change default community strings
2. **Persistence**: Mount volumes for data/config
3. **Monitoring**: Enable Prometheus/Grafana integration
4. **Scaling**: Use container orchestration
5. **Networking**: Consider dedicated network segments
6. **Performance**: Tune worker pools and socket counts

## Examples for Different Scales

### Development (1-10 devices)
```bash
./test_container.sh start
```

### Testing (50-100 devices)
```bash  
./test_container_hundred.sh host start
```

### Production (1000+ devices)
```bash
# Split across multiple containers
podman run -d --name snmp_block1 --network host \
  -e SNMP_SIM_EX_PORT_RANGE_START=30000 \
  -e SNMP_SIM_EX_PORT_RANGE_END=39999 \
  snmp_sim_ex:prod

podman run -d --name snmp_block2 --network host \
  -e SNMP_SIM_EX_PORT_RANGE_START=40000 \
  -e SNMP_SIM_EX_PORT_RANGE_END=49999 \
  snmp_sim_ex:prod
```