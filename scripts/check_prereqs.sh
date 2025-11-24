#!/usr/bin/env bash
set -euo pipefail

# Check prerequisites for running the stack

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_success() { echo -e "${GREEN}✓${NC} $*"; }
log_error() { echo -e "${RED}✗${NC} $*"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $*"; }

echo "Checking prerequisites..."
echo

errors=0

# Check Docker
if command -v docker &> /dev/null; then
    docker_version=$(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    log_success "Docker found: $docker_version"

    # Check if Docker daemon is running
    if docker ps &> /dev/null; then
        log_success "Docker daemon is running"
    else
        log_error "Docker daemon is not running"
        echo "  → Start Docker daemon and try again"
        ((errors++))
    fi
else
    log_error "Docker not found"
    echo "  → Install Docker from https://docs.docker.com/get-docker/"
    ((errors++))
fi

# Check Docker Compose
if docker compose version &> /dev/null; then
    compose_version=$(docker compose version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    log_success "Docker Compose (plugin) found: $compose_version"
elif command -v docker-compose &> /dev/null; then
    compose_version=$(docker-compose --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    log_warn "Using legacy docker-compose: $compose_version"
    log_warn "Consider upgrading to Docker Compose v2 (docker compose)"
else
    log_error "Docker Compose not found"
    echo "  → Install Docker Compose v2"
    ((errors++))
fi

# Check minimum system resources
echo
echo "System Resources:"

# Check available memory
if command -v free &> /dev/null; then
    total_mem_gb=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$total_mem_gb" -ge 8 ]; then
        log_success "Available RAM: ${total_mem_gb}GB (recommended: 8GB+)"
    else
        log_warn "Available RAM: ${total_mem_gb}GB (recommended: 8GB+)"
        echo "  → Some components may run slowly with less than 8GB RAM"
    fi
else
    log_warn "Cannot detect available RAM (free command not found)"
fi

# Check disk space
available_disk=$(df -BG . | awk 'NR==2 {print $4}' | tr -d 'G')
if [ "$available_disk" -ge 20 ]; then
    log_success "Available disk space: ${available_disk}GB (recommended: 20GB+)"
else
    log_warn "Available disk space: ${available_disk}GB (recommended: 20GB+)"
    echo "  → Consider freeing up disk space for Docker volumes"
fi

# Check environment file
echo
echo "Configuration:"

if [ -f "./env/common.env" ]; then
    log_success "Environment file exists: ./env/common.env"
else
    log_warn "Environment file not found: ./env/common.env"
    if [ -f "./env/common.env.example" ]; then
        echo "  → Run: cp env/common.env.example env/common.env"
    fi
fi

# Check ports availability
echo
echo "Port Availability:"

check_port() {
    local port=$1
    local service=$2
    if ! netstat -tuln 2>/dev/null | grep -q ":${port} " && ! ss -tuln 2>/dev/null | grep -q ":${port} "; then
        log_success "Port $port available ($service)"
    else
        log_warn "Port $port may be in use ($service)"
        echo "  → Stop service using port $port or expect conflicts"
    fi
}

check_port 3306 "MySQL"
check_port 8080 "Kafka UI"
check_port 8081 "Flink (Debezium)"
check_port 8082 "Flink (CDC Direct)"
check_port 8083 "Debezium API"
check_port 9000 "MinIO API"
check_port 9001 "MinIO Console"
check_port 9030 "StarRocks"
check_port 8181 "Iceberg REST"

# Summary
echo
echo "================================================"
if [ $errors -eq 0 ]; then
    log_success "All prerequisites met!"
    echo
    echo "Next steps:"
    echo "  1. Configure environment: vim env/common.env"
    echo "  2. Deploy a stack: make full-flink-cdc"
    echo "  3. Check status: make status"
    exit 0
else
    log_error "Found $errors error(s)"
    echo
    echo "Please fix the errors above and try again."
    exit 1
fi
