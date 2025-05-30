#!/bin/bash

# SNMPSimEx Container Test Script - Hundred Devices Version
# This script demonstrates how to handle larger scale deployments

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONTAINER_NAME="snmp_sim_ex_hundred"
IMAGE_NAME="snmp_sim_ex:test"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

cleanup_container() {
    print_status "Cleaning up existing container..."
    
    if podman ps -a --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        print_status "Stopping and removing existing container: ${CONTAINER_NAME}"
        podman stop "${CONTAINER_NAME}" 2>/dev/null || true
        podman rm "${CONTAINER_NAME}" 2>/dev/null || true
    fi
}

create_hundred_devices_config() {
    print_status "Creating hundred devices configuration..."
    
    local config_dir="${PROJECT_DIR}/test_config_hundred"
    mkdir -p "${config_dir}"
    
    cp "${SCRIPT_DIR}/hundred_devices_config.json" "${config_dir}/hundred_devices.json"
    
    print_success "Hundred devices configuration created at: ${config_dir}/hundred_devices.json"
    print_status "Configuration includes:"
    print_status "  - 50 Cable Modems: ports 30000-30049"
    print_status "  - 30 Cable Modems: ports 30050-30079"  
    print_status "  - 15 Switches: ports 31000-31014"
    print_status "  - 5 Routers: ports 32000-32004"
    print_status "  Total: 100 devices"
}

# Function to build the container image
build_image() {
    print_status "Building container image..."
    
    cd "${PROJECT_DIR}"
    
    if ! podman build -f Dockerfile -t "${IMAGE_NAME}" .; then
        print_error "Failed to build container image"
        exit 1
    fi
    
    print_success "Container image built: ${IMAGE_NAME}"
}

# Strategy 1: Map port ranges (most efficient for testing)
run_container_port_ranges() {
    print_status "Starting container with PORT RANGE mapping strategy..."
    print_warning "This maps entire port ranges - efficient but uses many host ports"
    
    local config_dir="${PROJECT_DIR}/test_config_hundred"
    
    podman run -d \
        --name "${CONTAINER_NAME}" \
        --hostname snmp-hundred \
        -p 30000-30079:30000-30079/udp \
        -p 31000-31014:31000-31014/udp \
        -p 32000-32004:32000-32004/udp \
        -p 4000:4000 \
        -v "${PROJECT_DIR}/priv:/app/priv:ro" \
        -v "${config_dir}:/app/test_config:ro" \
        -e MIX_ENV=prod \
        -e SNMP_SIM_EX_HOST=0.0.0.0 \
        -e SNMP_SIM_EX_LOG_LEVEL=info \
        "${IMAGE_NAME}"
    
    print_success "Container started with port range mapping"
    print_status "Host ports 30000-30079, 31000-31014, 32000-32004 are mapped to container"
}

# Strategy 2: Use host networking (simplest for testing)
run_container_host_network() {
    print_status "Starting container with HOST NETWORK strategy..."
    print_warning "This uses host networking - simplest but less isolated"
    
    local config_dir="${PROJECT_DIR}/test_config_hundred"
    
    podman run -d \
        --name "${CONTAINER_NAME}" \
        --hostname snmp-hundred \
        --network host \
        -v "${PROJECT_DIR}/priv:/app/priv:ro" \
        -v "${config_dir}:/app/test_config:ro" \
        -e MIX_ENV=prod \
        -e SNMP_SIM_EX_HOST=0.0.0.0 \
        -e SNMP_SIM_EX_LOG_LEVEL=info \
        "${IMAGE_NAME}"
    
    print_success "Container started with host networking"
    print_status "All container ports are directly accessible on host"
}

# Strategy 3: Custom port offset (for avoiding conflicts)
run_container_port_offset() {
    print_status "Starting container with PORT OFFSET strategy..."
    print_status "This maps container ports to host ports with an offset"
    
    local config_dir="${PROJECT_DIR}/test_config_hundred"
    local offset=10000  # Offset to avoid conflicts
    
    # Generate port mappings with offset
    local port_mappings=()
    
    # Cable modems block 1: 30000-30049 -> 40000-40049
    port_mappings+=("-p $((30000 + offset))-$((30049 + offset)):30000-30049/udp")
    
    # Cable modems block 2: 30050-30079 -> 40050-40079  
    port_mappings+=("-p $((30050 + offset))-$((30079 + offset)):30050-30079/udp")
    
    # Switches: 31000-31014 -> 41000-41014
    port_mappings+=("-p $((31000 + offset))-$((31014 + offset)):31000-31014/udp")
    
    # Routers: 32000-32004 -> 42000-42004
    port_mappings+=("-p $((32000 + offset))-$((32004 + offset)):32000-32004/udp")
    
    # Management API
    port_mappings+=("-p $((4000 + offset)):4000")
    
    podman run -d \
        --name "${CONTAINER_NAME}" \
        --hostname snmp-hundred \
        "${port_mappings[@]}" \
        -v "${PROJECT_DIR}/priv:/app/priv:ro" \
        -v "${config_dir}:/app/test_config:ro" \
        -e MIX_ENV=prod \
        -e SNMP_SIM_EX_HOST=0.0.0.0 \
        -e SNMP_SIM_EX_LOG_LEVEL=info \
        "${IMAGE_NAME}"
    
    print_success "Container started with port offset mapping"
    print_status "Access devices on offset ports (host port = container port + ${offset})"
    print_status "Example: snmpget -v2c -c public localhost:$((30000 + offset)) 1.3.6.1.2.1.1.1.0"
}

wait_for_ready() {
    print_status "Waiting for SNMPSimEx to be ready..."
    
    local max_attempts=60  # Longer timeout for hundred devices
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if podman exec "${CONTAINER_NAME}" /app/bin/snmp_sim_ex eval "SNMPSimEx.health_check()" 2>/dev/null; then
            print_success "SNMPSimEx is ready!"
            return 0
        fi
        
        if [ $((attempt % 10)) -eq 0 ]; then
            print_status "Attempt ${attempt}/${max_attempts} - still starting up (hundred devices takes longer)..."
        fi
        sleep 2
        attempt=$((attempt + 1))
    done
    
    print_error "SNMPSimEx failed to become ready within timeout"
    return 1
}

show_device_info() {
    print_status "Device Information:"
    echo
    print_status "Cable Modems (80 total):"
    print_status "  Block 1: ports 30000-30049 (50 devices)"
    print_status "  Block 2: ports 30050-30079 (30 devices)"
    echo
    print_status "Switches: ports 31000-31014 (15 devices)"
    echo  
    print_status "Routers: ports 32000-32004 (5 devices)"
    echo
    print_status "Management API: port 4000"
    echo
}

run_sample_tests() {
    print_status "Running sample SNMP tests on hundred devices..."
    echo
    
    if ! command -v snmpget >/dev/null 2>&1; then
        print_warning "snmpget not available. Install net-snmp-utils to run tests."
        print_status "Example commands you can run once snmp tools are installed:"
        echo "  snmpget -v2c -c public localhost:30000 1.3.6.1.2.1.1.1.0"
        echo "  snmpwalk -v2c -c public localhost:30025 1.3.6.1.2.1.1"
        echo "  snmpget -v2c -c public localhost:31005 1.3.6.1.2.1.1.5.0"
        echo "  snmpget -v2c -c public localhost:32002 1.3.6.1.2.1.1.1.0"
        return
    fi
    
    local test_ports=(30000 30025 30050 30075 31000 31007 32000 32002)
    local test_oid="1.3.6.1.2.1.1.1.0"  # sysDescr
    
    for port in "${test_ports[@]}"; do
        printf "Port %-5s -> " "${port}"
        result=$(snmpget -v2c -c public -t 1 -r 1 localhost:${port} "${test_oid}" 2>/dev/null || echo "TIMEOUT/ERROR")
        echo "${result}"
    done
}

check_port_usage() {
    print_status "Checking host port usage..."
    
    if command -v netstat >/dev/null 2>&1; then
        echo "UDP ports in use by container:"
        netstat -ln | grep ":3[0-2][0-9][0-9][0-9] " | head -10
        echo "..."
        print_status "Use 'netstat -ln | grep udp' to see all UDP ports"
    elif command -v ss >/dev/null 2>&1; then
        echo "UDP ports in use by container:"
        ss -ln | grep ":3[0-2][0-9][0-9][0-9] " | head -10  
        echo "..."
        print_status "Use 'ss -ln' to see all listening ports"
    else
        print_warning "netstat/ss not available - cannot show port usage"
    fi
}

show_usage() {
    cat << EOF
SNMPSimEx Hundred Devices Container Test Script

Usage: $0 [STRATEGY] [COMMAND]

Strategies:
    ranges     - Map port ranges (efficient, uses many host ports)
    host       - Use host networking (simple, less isolation)  
    offset     - Map with port offset (avoids conflicts)

Commands:
    start      - Start container with hundred devices
    stop       - Stop and remove container
    build      - Build container image only
    status     - Show container status
    test       - Run sample SNMP tests
    info       - Show device port information
    ports      - Check port usage
    logs       - Show container logs
    shell      - Open container shell
    cleanup    - Full cleanup

Examples:
    $0 host start              # Start with host networking (simplest)
    $0 ranges start            # Start with port range mapping
    $0 offset start            # Start with port offset mapping
    $0 test                    # Test random devices
    $0 info                    # Show device layout

Port Mapping Strategies Explained:

1. HOST NETWORKING (--network host):
   - Simplest approach
   - Container uses host network directly
   - All ports available without mapping
   - Command: $0 host start

2. PORT RANGES (-p 30000-30079:30000-30079/udp):
   - Maps entire port ranges
   - Efficient for podman/docker
   - Uses many host ports
   - Command: $0 ranges start

3. PORT OFFSET (-p 40000-40079:30000-30079/udp):
   - Maps container ports to different host ports
   - Avoids conflicts with other services
   - Access via: localhost:(container_port + 10000)
   - Command: $0 offset start

For production deployments with hundreds of devices, consider:
- Using host networking for simplicity
- Using a reverse proxy/load balancer
- Running multiple containers with different port ranges
- Using container orchestration (Kubernetes, Docker Swarm)
EOF
}

# Main command handling
strategy="${1:-host}"
command="${2:-start}"

case "${strategy}" in
    ranges|host|offset)
        # Valid strategy, continue
        ;;
    start|stop|status|test|info|ports|logs|shell|cleanup|help)
        # Command without strategy - use default
        command="${strategy}"
        strategy="host"
        ;;
    *)
        print_error "Unknown strategy: ${strategy}"
        echo
        show_usage
        exit 1
        ;;
esac

case "${command}" in
    start)
        cleanup_container
        create_hundred_devices_config
        build_image
        
        case "${strategy}" in
            ranges)
                run_container_port_ranges
                ;;
            host)
                run_container_host_network
                ;;
            offset)
                run_container_port_offset
                ;;
        esac
        
        wait_for_ready
        show_device_info
        print_success "Hundred devices environment ready!"
        print_status "Try: $0 test"
        ;;
        
    stop)
        podman stop "${CONTAINER_NAME}" 2>/dev/null || true
        podman rm "${CONTAINER_NAME}" 2>/dev/null || true
        print_success "Container stopped"
        ;;
        
    build)
        build_image
        ;;
        
    status)
        podman ps -a --filter "name=${CONTAINER_NAME}"
        ;;
        
    test)
        run_sample_tests
        ;;
        
    info)
        show_device_info
        ;;
        
    ports)
        check_port_usage
        ;;
        
    logs)
        podman logs "${CONTAINER_NAME}" "${@:3}"
        ;;
        
    shell)
        podman exec -it "${CONTAINER_NAME}" /bin/sh
        ;;
        
    cleanup)
        cleanup_container
        rm -rf "${PROJECT_DIR}/test_config_hundred"
        print_success "Cleanup complete"
        ;;
        
    help)
        show_usage
        ;;
        
    *)
        print_error "Unknown command: ${command}"
        show_usage
        exit 1
        ;;
esac