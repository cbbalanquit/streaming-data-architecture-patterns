#!/usr/bin/env bash
set -euo pipefail

# Prepare MySQL dump files with proper database statements and sequence

INIT_SCRIPTS_DIR="./01-sources/mysql/init-scripts"
BACKUP_DIR="./01-sources/mysql/init-scripts.original"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

echo "Preparing MySQL dump files with proper database statements..."
echo

# Check if init-scripts directory exists
if [ ! -d "$INIT_SCRIPTS_DIR" ]; then
    log_warn "Init scripts directory not found: $INIT_SCRIPTS_DIR"
    exit 1
fi

# Backup original dumps if not already backed up
if [ ! -d "$BACKUP_DIR" ]; then
    log_info "Creating backup of original dumps..."
    cp -r "$INIT_SCRIPTS_DIR" "$BACKUP_DIR"
    log_success "Backup created at: $BACKUP_DIR"
else
    log_info "Backup already exists at: $BACKUP_DIR"
fi

echo

# Define the dump files with their target databases and sequence
declare -A DUMPS=(
    ["1-dump-active.sql"]="active:dump-active-202511240953.sql"
    ["2-dump-webservice.sql"]="webservice:dump-webservice-202511241207.sql"
    ["3-dump-export-msa.sql"]="export:dump-export-msa-202511241345.sql"
    ["4-dump-export.sql"]="export:dump-export-202511241400.sql"
)

# Process each dump file
for new_name in $(echo "${!DUMPS[@]}" | tr ' ' '\n' | sort); do
    IFS=':' read -r db_name orig_file <<< "${DUMPS[$new_name]}"

    orig_path="$BACKUP_DIR/$orig_file"
    new_path="$INIT_SCRIPTS_DIR/$new_name"

    if [ ! -f "$orig_path" ]; then
        log_warn "Original file not found: $orig_path (skipping)"
        continue
    fi

    log_info "Processing: $orig_file → $new_name (database: $db_name)"

    # Create new dump with database statements
    {
        echo "-- Wrapped by prepare_mysql_dumps.sh"
        echo "-- Original file: $orig_file"
        echo "-- Target database: $db_name"
        echo ""
        echo "CREATE DATABASE IF NOT EXISTS \`$db_name\`;"
        echo "USE \`$db_name\`;"
        echo ""
        cat "$orig_path"
    } > "$new_path"

    # Get file sizes
    orig_size=$(du -h "$orig_path" | cut -f1)
    new_size=$(du -h "$new_path" | cut -f1)

    log_success "Created: $new_name ($new_size, original: $orig_size)"
done

echo

# Remove old files from init-scripts (keep only the new sequenced ones)
log_info "Cleaning up old dump files from init-scripts..."
for old_file in "$INIT_SCRIPTS_DIR"/dump-*.sql; do
    if [ -f "$old_file" ]; then
        rm "$old_file"
        log_info "Removed: $(basename "$old_file")"
    fi
done

echo
log_success "All dump files prepared!"
echo

echo "New initialization sequence:"
ls -1 "$INIT_SCRIPTS_DIR"/*.sql | while read -r file; do
    db_name=$(grep "^USE " "$file" | head -1 | sed "s/USE \`\(.*\)\`;/\1/")
    size=$(du -h "$file" | cut -f1)
    echo "  $(basename "$file") → database: $db_name ($size)"
done

echo
echo "Next steps:"
echo "  1. Stop MySQL: make down-mysql --volumes"
echo "  2. Restart MySQL: make mysql"
echo "  3. Wait for initialization to complete"
echo "  4. Check databases: docker exec mysql-mysql-1 mysql -uroot -p -e 'SHOW DATABASES;'"
