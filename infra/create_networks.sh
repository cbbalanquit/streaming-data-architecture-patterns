#!/usr/bin/env bash
set -euo pipefail

# Create Docker networks for streaming data architecture

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }

# Define networks
NETWORKS=(
  "cdc_network:bridge:Network for CDC pipeline (MySQL, Flink, Kafka, Debezium)"
  "iceberg_net:bridge:Network for data lake (Iceberg, MinIO, StarRocks)"
)

log_info "Creating Docker networks..."

for network_spec in "${NETWORKS[@]}"; do
  IFS=':' read -r name driver description <<< "$network_spec"

  if docker network inspect "$name" >/dev/null 2>&1; then
    log_info "Network already exists: $name"
  else
    docker network create --driver "$driver" "$name"
    log_success "Created network: $name ($description)"
  fi
done

echo
log_success "All networks ready!"
echo
echo "Networks:"
docker network ls | grep -E "cdc_network|iceberg_net" || true
