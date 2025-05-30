#!/bin/bash

# SNMPSimEx Container Test Script
# This script sets up a containerized SNMPSimEx environment for manual testing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONTAINER_NAME="snmp_sim_ex_test"
IMAGE_NAME="snmp_sim_ex:test"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
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

# Function to cleanup existing container
cleanup_container() {
    print_status "Cleaning up existing container..."
    
    if podman ps -a --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        print_status "Stopping and removing existing container: ${CONTAINER_NAME}"
        podman stop "${CONTAINER_NAME}" 2>/dev/null || true
        podman rm "${CONTAINER_NAME}" 2>/dev/null || true
    fi
}

# Function to create test configuration
create_test_config() {
    print_status "Creating test configuration..."
    
    local config_dir="${PROJECT_DIR}/test_config"
    mkdir -p "${config_dir}"
    
    # Create a simple test configuration for 10 devices
    cat > "${config_dir}/test_devices.json" << 'EOF'
{
  "snmp_sim_ex": {
    "global_settings": {
      "max_devices": 50,
      "max_memory_mb": 256,
      "enable_telemetry": true,
      "enable_performance_monitoring": true,
      "host": "0.0.0.0",
      "community": "public",
      "worker_pool_size": 4,
      "socket_count": 2
    },
    "device_groups": [
      {
        "name": "test_cable_modems",
        "device_type": "cable_modem",
        "count": 5,
        "port_range": {
          "start": 30000,
          "end": 30004
        },
        "community": "public",
        "walk_file": "priv/walks/cable_modem.walk",
        "behaviors": ["realistic_counters", "time_patterns"]
      },
      {
        "name": "test_switches",
        "device_type": "switch", 
        "count": 3,
        "port_range": {
          "start": 31000,
          "end": 31002
        },
        "community": "public",
        "walk_file": "priv/walks/cable_modem.walk",
        "behaviors": ["realistic_counters"]
      },
      {
        "name": "test_routers",
        "device_type": "router",
        "count": 2,
        "port_range": {
          "start": 32000,
          "end": 32001
        },
        "community": "public",
        "walk_file": "priv/walks/cable_modem.walk",
        "behaviors": ["realistic_counters", "correlations"]
      }
    ],
    "monitoring": {
      "health_check": {
        "enabled": true,
        "port": 4000,
        "path": "/health"
      }
    }
  }
}
EOF

    print_success "Test configuration created at: ${config_dir}/test_devices.json"
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

# Function to run the container
run_container() {
    print_status "Starting SNMPSimEx container..."
    
    local config_dir="${PROJECT_DIR}/test_config"
    
    # For testing, we only map the ports we're actually using
    # This is much more manageable than mapping thousands of ports
    
    # Run the container
    podman run -d \
        --name "${CONTAINER_NAME}" \
        --hostname snmp-test \
        -p 30000:30000/udp \
        -p 30001:30001/udp \
        -p 30002:30002/udp \
        -p 30003:30003/udp \
        -p 30004:30004/udp \
        -p 31000:31000/udp \
        -p 31001:31001/udp \
        -p 31002:31002/udp \
        -p 32000:32000/udp \
        -p 32001:32001/udp \
        -p 4000:4000 \
        -v "${PROJECT_DIR}/priv:/app/priv:ro" \
        -v "${config_dir}:/app/test_config:ro" \
        -e MIX_ENV=prod \
        -e SNMP_SIM_EX_HOST=0.0.0.0 \
        -e SNMP_SIM_EX_LOG_LEVEL=info \
        "${IMAGE_NAME}"
    
    print_success "Container started: ${CONTAINER_NAME}"
}

# Function to wait for container to be ready
wait_for_ready() {
    print_status "Waiting for SNMPSimEx to be ready..."
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if podman exec "${CONTAINER_NAME}" /app/bin/snmp_sim_ex eval "SNMPSimEx.health_check()" 2>/dev/null; then
            print_success "SNMPSimEx is ready!"
            return 0
        fi
        
        print_status "Attempt ${attempt}/${max_attempts} - waiting..."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    print_error "SNMPSimEx failed to become ready within timeout"
    print_status "Container logs:"
    podman logs "${CONTAINER_NAME}" --tail 20
    return 1
}

# Function to show device information
show_device_info() {
    print_status "Test Environment:"
    echo "  - 5 Cable Modems: ports 30000-30004"
    echo "  - 3 Switches: ports 31000-31002"
    echo "  - 2 Routers: ports 32000-32001"
    echo "  - Management API: port 4000"
    echo "  - All devices use community string: public"
    echo
    print_status "Manual testing commands:"
    echo "  snmpget -v2c -c public localhost:30000 1.3.6.1.2.1.1.1.0"
    echo "  snmpwalk -v2c -c public localhost:30001 1.3.6.1.2.1.1"
    echo "  snmpbulkget -v2c -c public localhost:31000 1.3.6.1.2.1.2.2.1"
}

# Function to show container status
show_status() {
    print_status "Container Status:"
    echo
    podman ps -a --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo
    
    if podman ps --filter "name=${CONTAINER_NAME}" --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        print_status "Container is running. Logs (last 10 lines):"
        podman logs "${CONTAINER_NAME}" --tail 10
    fi
}

# Function to run SNMP tests
run_snmp_tests() {
    print_status "Running SNMP test queries..."
    echo
    
    local test_oids=(
        "1.3.6.1.2.1.1.1.0"  # sysDescr
        "1.3.6.1.2.1.1.3.0"  # sysUpTime  
        "1.3.6.1.2.1.1.5.0"  # sysName
        "1.3.6.1.2.1.2.1.0"  # ifNumber
    )
    
    local test_ports=(30000 30001 31000 32000)
    
    for port in "${test_ports[@]}"; do
        print_status "Testing device on port ${port}:"
        
        for oid in "${test_oids[@]}"; do
            printf "  %-20s -> " "${oid}"
            if command -v snmpget >/dev/null 2>&1; then
                result=$(snmpget -v2c -c public -t 2 -r 1 localhost:${port} "${oid}" 2>/dev/null || echo "FAILED")
                echo "${result}"
            else
                echo "snmpget not available (install net-snmp-utils)"
            fi
        done
        echo
    done
}

# Function to show usage
show_usage() {
    cat << EOF
SNMPSimEx Container Test Script

Usage: $0 [COMMAND]

Commands:
    start      - Build and start the container with test configuration
    stop       - Stop and remove the container  
    restart    - Restart the container
    status     - Show container status and logs
    test       - Run SNMP test queries
    logs       - Show container logs
    shell      - Open shell in running container
    cleanup    - Stop container and clean up
    help       - Show this usage information

Examples:
    $0 start                    # Start the test environment
    $0 test                     # Run SNMP queries against test devices
    $0 logs                     # View container logs
    $0 shell                    # Open container shell for debugging

Test Environment:
    - 5 Cable Modems: ports 30000-30004
    - 3 Switches: ports 31000-31002  
    - 2 Routers: ports 32000-32001
    - Management API: port 4000
    - All devices use community string: public

SNMP Test Commands:
    snmpget -v2c -c public localhost:30000 1.3.6.1.2.1.1.1.0
    snmpwalk -v2c -c public localhost:30001 1.3.6.1.2.1.1
    snmpbulkget -v2c -c public localhost:31000 1.3.6.1.2.1.2.2.1
EOF
}

# Main command handling
case "${1:-start}" in
    start)
        cleanup_container
        create_test_config
        build_image
        run_container
        print_success "Container started successfully!"
        print_status "The container may take a few minutes to fully initialize."
        print_status "You can check status with: $0 status"
        print_status "You can check logs with: $0 logs"
        echo
        show_device_info
        print_status "Try: $0 test (after container is fully ready)"
        ;;
        
    stop)
        print_status "Stopping container..."
        podman stop "${CONTAINER_NAME}" 2>/dev/null || true
        podman rm "${CONTAINER_NAME}" 2>/dev/null || true
        print_success "Container stopped and removed"
        ;;
        
    restart)
        print_status "Restarting container..."
        podman restart "${CONTAINER_NAME}"
        wait_for_ready
        show_status
        ;;
        
    status)
        show_status
        ;;
        
    test)
        run_snmp_tests
        ;;
        
    logs)
        podman logs "${CONTAINER_NAME}" "${@:2}"
        ;;
        
    shell)
        print_status "Opening shell in container..."
        podman exec -it "${CONTAINER_NAME}" /bin/sh
        ;;
        
    cleanup)
        cleanup_container
        print_status "Cleaning up test configuration..."
        rm -rf "${PROJECT_DIR}/test_config"
        print_success "Cleanup complete"
        ;;
        
    help|--help|-h)
        show_usage
        ;;
        
    *)
        print_error "Unknown command: $1"
        echo
        show_usage
        exit 1
        ;;
esac