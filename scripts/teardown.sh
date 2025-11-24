#!/usr/bin/env bash
set -euo pipefail

# Teardown streaming data architecture patterns

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODE="${1:-all}"
REMOVE_VOLUMES="${2:-false}"

# Color output
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${YELLOW}[TEARDOWN]${NC} $*"; }
log_warn() { echo -e "${RED}[WARNING]${NC} $*"; }

show_usage() {
  cat <<EOF
Usage: $0 [MODE] [--volumes]

Teardown modes:
  all                   Stop all components (default)
  infra                 Remove only infrastructure (networks)
  mysql                 Stop only MySQL source
  flink-cdc             Stop Flink CDC Direct pattern
  debezium              Stop Debezium+Kafka+Flink pattern
  iceberg               Stop Iceberg+MinIO destination
  starrocks             Stop StarRocks destination
  full-flink-cdc        Stop full Flink CDC stack
  full-debezium         Stop full Debezium stack

Options:
  --volumes             Remove volumes (deletes all data!)

Examples:
  $0                    # Stop everything
  $0 all --volumes      # Stop everything and delete data
  $0 mysql              # Stop only MySQL
EOF
}

teardown_component() {
  local name="$1"
  local compose_file="$2"

  if [ ! -f "$compose_file" ]; then
    log_info "Compose file not found: $compose_file (skipping)"
    return 0
  fi

  log_info "Stopping $name..."
  if [ "$REMOVE_VOLUMES" = "true" ]; then
    docker compose -f "$compose_file" down -v
    log_warn "$name stopped and volumes removed"
  else
    docker compose -f "$compose_file" down
    log_info "$name stopped"
  fi
}

teardown_infra() {
  bash ./infra/remove_networks.sh
}

teardown_mysql() {
  teardown_component "MySQL Source" "./01-sources/mysql/compose.yaml"
}

teardown_flink_cdc() {
  teardown_component "Flink CDC Direct" "./02-cdc-patterns/flink-cdc-direct/compose-flink-cdc.yaml"
}

teardown_debezium() {
  teardown_component "Debezium+Kafka+Flink" "./02-cdc-patterns/debezium-kafka-flink/compose-debezium-kafka-flink.yaml"
}

teardown_iceberg() {
  teardown_component "Iceberg+MinIO" "./03-destinations/iceberg-minio/compose.yaml"
}

teardown_starrocks() {
  teardown_component "StarRocks" "./03-destinations/starrocks/compose.yaml"
}

teardown_all() {
  log_info "Stopping all components..."
  teardown_starrocks
  teardown_iceberg
  teardown_debezium
  teardown_flink_cdc
  teardown_mysql
  teardown_infra
  log_info "All components stopped"
}

teardown_full_flink_cdc() {
  teardown_starrocks
  teardown_iceberg
  teardown_flink_cdc
  teardown_mysql
  teardown_infra
}

teardown_full_debezium() {
  teardown_starrocks
  teardown_iceberg
  teardown_debezium
  teardown_mysql
  teardown_infra
}

# Parse arguments
if [ "${2:-}" = "--volumes" ]; then
  REMOVE_VOLUMES="true"
  log_warn "Volume removal enabled - all data will be deleted!"
fi

# Route to appropriate teardown
case "$MODE" in
  all)
    teardown_all
    ;;
  infra)
    teardown_infra
    ;;
  mysql)
    teardown_mysql
    ;;
  flink-cdc)
    teardown_flink_cdc
    ;;
  debezium)
    teardown_debezium
    ;;
  iceberg)
    teardown_iceberg
    ;;
  starrocks)
    teardown_starrocks
    ;;
  full-flink-cdc)
    teardown_full_flink_cdc
    ;;
  full-debezium)
    teardown_full_debezium
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
log_info "Teardown complete!"
if [ "$REMOVE_VOLUMES" = "true" ]; then
  log_warn "All data has been removed"
else
  log_info "Data volumes preserved. Use '$0 $MODE --volumes' to remove data"
fi
