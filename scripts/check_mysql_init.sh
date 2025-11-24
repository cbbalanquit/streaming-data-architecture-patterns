#!/usr/bin/env bash
set -euo pipefail

# Check MySQL initialization status

CONTAINER_NAME="mysql-mysql-1"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "Checking MySQL initialization status..."
echo

# Check if container exists and is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "❌ MySQL container not running"
    echo "Start it with: make mysql"
    exit 1
fi

echo -e "${GREEN}✓${NC} MySQL container is running"
echo

# Get all init scripts
echo "Init scripts to process:"
if [ -d "./01-sources/mysql/init-scripts" ]; then
    ls -lh ./01-sources/mysql/init-scripts/*.sql 2>/dev/null | awk '{print "  - " $9 " (" $5 ")"}'
else
    echo "  No init-scripts directory found"
fi
echo

# Check which scripts have been processed
echo "Progress:"
INIT_LOGS=$(docker logs "$CONTAINER_NAME" 2>&1 | grep "Entrypoint.*running.*\.sql" || true)

if [ -n "$INIT_LOGS" ]; then
    echo "$INIT_LOGS" | while read -r line; do
        script_name=$(echo "$line" | sed -E 's/.*running (.*\.sql).*/\1/' | xargs basename)
        timestamp=$(echo "$line" | awk '{print $1, $2}')
        echo -e "  ${GREEN}✓${NC} $script_name (started at $timestamp)"
    done
else
    echo "  No scripts processed yet"
fi
echo

# Check current script
CURRENT_SCRIPT=$(docker logs "$CONTAINER_NAME" 2>&1 | grep "Entrypoint.*running" | tail -1 | sed -E 's/.*running (.*\.sql).*/\1/' | xargs basename || echo "unknown")
if [ "$CURRENT_SCRIPT" != "unknown" ]; then
    echo -e "${YELLOW}⏳ Currently processing:${NC} $CURRENT_SCRIPT"

    # Estimate time based on file size (very rough)
    SCRIPT_PATH="./01-sources/mysql/init-scripts/$CURRENT_SCRIPT"
    if [ -f "$SCRIPT_PATH" ]; then
        SIZE=$(ls -lh "$SCRIPT_PATH" | awk '{print $5}')
        echo "   Size: $SIZE"
    fi
    echo
fi

# Check if initialization is complete
if docker logs "$CONTAINER_NAME" 2>&1 | grep -q "MySQL init process done"; then
    echo -e "${GREEN}✓ Initialization COMPLETE!${NC}"
    echo
    echo "MySQL is ready for connections:"
    echo "  - DBeaver: localhost:3306"
    echo "  - Docker exec: docker exec -it $CONTAINER_NAME mysql -uappuser -papppassword"
    echo "  - Host client: mysql -h 127.0.0.1 -P 3306 -uappuser -papppassword"
    exit 0
else
    echo -e "${YELLOW}⏳ Initialization still in progress...${NC}"
    echo
    echo "Monitor progress with:"
    echo "  - Live logs: docker logs -f $CONTAINER_NAME"
    echo "  - Check again: bash scripts/check_mysql_init.sh"
    echo "  - Watch for 'MySQL init process done' message"
    exit 0
fi
