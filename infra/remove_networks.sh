#!/usr/bin/env bash
set -euo pipefail

# Remove Docker networks for streaming data architecture

YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${YELLOW}[INFO]${NC} $*"; }
log_warn() { echo -e "${RED}[WARN]${NC} $*"; }

# Define networks to remove
NETWORKS=(
  "cdc_network"
  "iceberg_net"
)

log_info "Removing Docker networks..."

for name in "${NETWORKS[@]}"; do
  if docker network inspect "$name" >/dev/null 2>&1; then
    if docker network rm "$name" 2>/dev/null; then
      log_info "Removed network: $name"
    else
      log_warn "Cannot remove network: $name (still in use by containers)"
      echo "  → Stop containers using this network first"
    fi
  else
    log_info "Network does not exist: $name"
  fi
done

echo
log_info "Network cleanup complete"
