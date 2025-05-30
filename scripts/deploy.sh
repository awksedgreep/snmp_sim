#!/bin/bash
# SNMPSimEx Deployment Script
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
IMAGE_NAME="snmp_sim_ex"
CONTAINER_NAME="snmp_simulator"
DEFAULT_TAG="latest"
DEFAULT_ENV="production"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] COMMAND

COMMANDS:
    build       Build the Docker image
    deploy      Deploy the application
    start       Start the application
    stop        Stop the application
    restart     Restart the application
    status      Show application status
    logs        Show application logs
    cleanup     Clean up old images and containers
    health      Check application health

OPTIONS:
    -t, --tag TAG       Docker image tag (default: latest)
    -e, --env ENV       Environment (dev|staging|production) (default: production)
    -h, --help          Show this help message

EXAMPLES:
    $0 build --tag v1.0.0
    $0 deploy --env production
    $0 start
    $0 logs --follow
EOF
}

build_image() {
    local tag=${1:-$DEFAULT_TAG}
    
    log_info "Building Docker image with tag: $tag"
    
    if docker build -t "${IMAGE_NAME}:${tag}" .; then
        log_success "Docker image built successfully: ${IMAGE_NAME}:${tag}"
    else
        log_error "Failed to build Docker image"
        exit 1
    fi
}

deploy_application() {
    local env=${1:-$DEFAULT_ENV}
    local tag=${2:-$DEFAULT_TAG}
    
    log_info "Deploying SNMPSimEx (env: $env, tag: $tag)"
    
    # Stop existing container if running
    if docker ps -q -f name=$CONTAINER_NAME | grep -q .; then
        log_info "Stopping existing container"
        docker stop $CONTAINER_NAME
        docker rm $CONTAINER_NAME
    fi
    
    # Select appropriate compose file
    local compose_file="docker-compose.yml"
    case $env in
        dev|development)
            compose_file="docker-compose.dev.yml"
            ;;
        staging)
            compose_file="docker-compose.staging.yml"
            ;;
        production)
            compose_file="docker-compose.yml"
            ;;
    esac
    
    if [[ ! -f "$compose_file" ]]; then
        log_error "Compose file not found: $compose_file"
        exit 1
    fi
    
    # Deploy with docker-compose
    export SNMP_IMAGE_TAG=$tag
    docker-compose -f $compose_file up -d
    
    log_success "Application deployed successfully"
    
    # Wait for health check
    log_info "Waiting for application to be healthy..."
    local retries=30
    while [[ $retries -gt 0 ]]; do
        if docker exec $CONTAINER_NAME /app/bin/snmp_sim_ex eval "SNMPSimEx.health_check()" 2>/dev/null; then
            log_success "Application is healthy and ready"
            return 0
        fi
        ((retries--))
        sleep 2
    done
    
    log_warning "Health check timeout - application may not be fully ready"
}

start_application() {
    log_info "Starting SNMPSimEx application"
    docker-compose up -d
    log_success "Application started"
}

stop_application() {
    log_info "Stopping SNMPSimEx application"
    docker-compose down
    log_success "Application stopped"
}

restart_application() {
    log_info "Restarting SNMPSimEx application"
    docker-compose restart
    log_success "Application restarted"
}

show_status() {
    log_info "Application Status:"
    docker-compose ps
    
    if docker ps -q -f name=$CONTAINER_NAME | grep -q .; then
        echo
        log_info "Container Details:"
        docker inspect $CONTAINER_NAME --format='{{.State.Status}}: {{.State.Health.Status}}'
        
        echo
        log_info "Resource Usage:"
        docker stats $CONTAINER_NAME --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"
    fi
}

show_logs() {
    local follow=${1:-false}
    
    if [[ "$follow" == "true" ]]; then
        docker-compose logs -f
    else
        docker-compose logs --tail=100
    fi
}

cleanup() {
    log_info "Cleaning up old Docker images and containers"
    
    # Remove stopped containers
    docker container prune -f
    
    # Remove old images (keep last 3 versions)
    docker images "${IMAGE_NAME}" --format "table {{.Repository}}:{{.Tag}}\t{{.ID}}" | \
        tail -n +2 | sort -k1,1 -k2,2V | head -n -3 | \
        awk '{print $2}' | xargs -r docker rmi
    
    # Remove dangling images
    docker image prune -f
    
    log_success "Cleanup completed"
}

check_health() {
    log_info "Checking application health"
    
    if ! docker ps -q -f name=$CONTAINER_NAME | grep -q .; then
        log_error "Container is not running"
        return 1
    fi
    
    if docker exec $CONTAINER_NAME /app/bin/snmp_sim_ex eval "SNMPSimEx.health_check()"; then
        log_success "Application is healthy"
        
        # Show basic metrics
        log_info "Application Metrics:"
        docker exec $CONTAINER_NAME /app/bin/snmp_sim_ex eval "SNMPSimEx.Performance.PerformanceMonitor.get_current_metrics()" 2>/dev/null || true
    else
        log_error "Application health check failed"
        return 1
    fi
}

# Parse command line arguments
COMMAND=""
TAG="$DEFAULT_TAG"
ENV="$DEFAULT_ENV"
FOLLOW_LOGS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--tag)
            TAG="$2"
            shift 2
            ;;
        -e|--env)
            ENV="$2"
            shift 2
            ;;
        -f|--follow)
            FOLLOW_LOGS=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        build|deploy|start|stop|restart|status|logs|cleanup|health)
            COMMAND="$1"
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate command
if [[ -z "$COMMAND" ]]; then
    log_error "No command specified"
    show_usage
    exit 1
fi

# Execute command
case $COMMAND in
    build)
        build_image "$TAG"
        ;;
    deploy)
        build_image "$TAG"
        deploy_application "$ENV" "$TAG"
        ;;
    start)
        start_application
        ;;
    stop)
        stop_application
        ;;
    restart)
        restart_application
        ;;
    status)
        show_status
        ;;
    logs)
        show_logs "$FOLLOW_LOGS"
        ;;
    cleanup)
        cleanup
        ;;
    health)
        check_health
        ;;
    *)
        log_error "Unknown command: $COMMAND"
        show_usage
        exit 1
        ;;
esac