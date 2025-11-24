#!/usr/bin/env bash
set -euo pipefail

# Deploy streaming data architecture patterns
# Supports deploying individual components or full stacks

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Default: deploy everything
MODE="${1:-all}"
ENV_FILE="./env/common.env"

# Color output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

show_usage() {
  cat <<EOF
Usage: $0 [MODE]

Deployment modes:
  all                   Deploy all components (default)
  infra                 Deploy only infrastructure (networks)
  mysql                 Deploy only MySQL source
  flink-cdc             Deploy Flink CDC Direct pattern
  debezium              Deploy Debezium+Kafka+Flink pattern
  iceberg               Deploy Iceberg+MinIO destination
  starrocks             Deploy StarRocks destination
  full-flink-cdc        Deploy full stack: MySQL→Flink CDC→Iceberg+StarRocks
  full-debezium         Deploy full stack: MySQL→Debezium→Kafka→Flink→Iceberg+StarRocks

Examples:
  $0                    # Deploy everything
  $0 infra              # Just create networks
  $0 mysql              # Just start MySQL
  $0 full-flink-cdc     # Deploy complete Flink CDC stack

Environment:
  Reads configuration from: $ENV_FILE
EOF
}

deploy_component() {
  local name="$1"
  local compose_file="$2"

  if [ ! -f "$compose_file" ]; then
    log_warn "Compose file not found: $compose_file (skipping)"
    return 0
  fi

  log_info "Deploying $name..."
  docker compose -f "$compose_file" --env-file "$ENV_FILE" up -d
  log_success "$name deployed"
}

deploy_infra() {
  bash ./infra/create_networks.sh
}

deploy_mysql() {
  deploy_infra
  deploy_component "MySQL Source" "./01-sources/mysql/compose.yaml"
}

deploy_flink_cdc() {
  deploy_infra
  deploy_component "Flink CDC Direct" "./02-cdc-patterns/flink-cdc-direct/compose-flink-cdc.yaml"
}

deploy_debezium() {
  deploy_infra
  deploy_component "Debezium+Kafka+Flink" "./02-cdc-patterns/debezium-kafka-flink/compose-debezium-kafka-flink.yaml"
}

deploy_iceberg() {
  deploy_infra
  deploy_component "Iceberg+MinIO" "./03-destinations/iceberg-minio/compose.yaml"
}

deploy_starrocks() {
  deploy_infra
  deploy_component "StarRocks" "./03-destinations/starrocks/compose.yaml"
}

deploy_all() {
  log_info "Deploying all components..."
  deploy_infra
  deploy_mysql
  deploy_flink_cdc
  deploy_debezium
  deploy_iceberg
  deploy_starrocks
  log_success "All components deployed"
}

deploy_full_flink_cdc() {
  log_info "Deploying full Flink CDC stack..."
  deploy_infra
  deploy_mysql
  deploy_flink_cdc
  deploy_iceberg
  deploy_starrocks
  log_success "Full Flink CDC stack deployed"
}

deploy_full_debezium() {
  log_info "Deploying full Debezium stack..."
  deploy_infra
  deploy_mysql
  deploy_debezium
  deploy_iceberg
  deploy_starrocks
  log_success "Full Debezium stack deployed"
}

# Check prerequisites
if ! command -v docker &> /dev/null; then
  echo "ERROR: docker not found. Please install Docker first."
  exit 1
fi

if ! docker compose version &> /dev/null; then
  echo "ERROR: docker compose not found. Please install Docker Compose v2+"
  exit 1
fi

# Check env file
if [ ! -f "$ENV_FILE" ]; then
  log_warn "Environment file not found: $ENV_FILE"
  log_info "Creating from template..."
  if [ -f "./env/common.env.example" ]; then
    cp "./env/common.env.example" "$ENV_FILE"
    log_success "Created $ENV_FILE from template"
  else
    log_warn "No template found. Using environment defaults."
  fi
fi

# Route to appropriate deployment
case "$MODE" in
  all)
    deploy_all
    ;;
  infra)
    deploy_infra
    ;;
  mysql)
    deploy_mysql
    ;;
  flink-cdc)
    deploy_flink_cdc
    ;;
  debezium)
    deploy_debezium
    ;;
  iceberg)
    deploy_iceberg
    ;;
  starrocks)
    deploy_starrocks
    ;;
  full-flink-cdc)
    deploy_full_flink_cdc
    ;;
  full-debezium)
    deploy_full_debezium
    ;;
  help|--help|-h)
    show_usage
    exit 0
    ;;
  *)
    echo "ERROR: Unknown mode: $MODE"
    show_usage
    exit 1
    ;;
esac

echo
log_success "Deployment complete!"
log_info "View services: docker compose ps"
log_info "View logs: docker compose logs -f"
log_info "Access UIs:"
echo "  - Flink (CDC Direct): http://localhost:8082"
echo "  - Flink (Debezium): http://localhost:8081"
echo "  - Kafka UI: http://localhost:8080"
echo "  - StarRocks FE: http://localhost:8030"
echo "  - MinIO Console: http://localhost:9001"
echo "  - MySQL: mysql -h 127.0.0.1 -P 3306 -u\${MYSQL_USER} -p"
