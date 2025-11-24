# MySQL Source Database

## Overview

MySQL 8.0 configured as a CDC source with binary log replication enabled. This database serves as the transactional source for streaming data pipelines.

## Configuration

### Binary Log Settings

The MySQL instance is pre-configured for Change Data Capture (CDC) via [`mysql-config/binlog.cnf`](mysql-config/binlog.cnf):

```ini
log_bin = mysql-bin              # Enable binary logging
binlog_format = ROW              # Row-based replication (required for CDC)
gtid_mode = ON                   # Global Transaction IDs for consistent replication
enforce_gtid_consistency = ON    # Enforce GTID consistency
binlog_expire_logs_seconds = 604800  # 7-day retention
max_binlog_size = 100M           # Rotate logs at 100MB
sync_binlog = 1                  # Durability setting (flush to disk)
```

### Why These Settings Matter

- **`binlog_format = ROW`**: Captures full row changes (before/after values), essential for CDC tools like Debezium and Flink CDC
- **`gtid_mode = ON`**: Enables idempotent replication and simplifies failover scenarios
- **7-day retention**: Balances storage costs with recovery window requirements

## Ports

- **3306**: MySQL protocol (mapped to host)

## Credentials

Configured via environment variables (see [`env/common.env`](../../env/common.env)):

```bash
MYSQL_ROOT_PASSWORD=rootpassword
MYSQL_USER=myuser
MYSQL_PASSWORD=mypassword
MYSQL_DATABASE=mydatabase
```

## Initial Data

Database initialization scripts are located in [`init-scripts/`](init-scripts/):

```
dump-active-202511240953.sql
dump-export-202511241400.sql
dump-export-msa-202511241345.sql
dump-webservice-202511241207.sql
```

These scripts run automatically on first container startup via Docker's entrypoint mechanism.

## Usage

### Standalone Deployment

```bash
# Create network first
docker network create cdc_network

# Start MySQL
docker compose -f 01-sources/mysql/compose.yaml --env-file env/common.env up -d

# Check health
docker compose -f 01-sources/mysql/compose.yaml ps
```

### Connect to MySQL

```bash
# Via docker exec
docker exec -it mysql mysql -uroot -p${MYSQL_ROOT_PASSWORD}

# Via local MySQL client
mysql -h 127.0.0.1 -P 3306 -u ${MYSQL_USER} -p
```

### Verify CDC Configuration

```sql
-- Check binary log status
SHOW MASTER STATUS;

-- Verify GTID mode
SHOW VARIABLES LIKE 'gtid_mode';

-- Check binary log format
SHOW VARIABLES LIKE 'binlog_format';

-- List binary logs
SHOW BINARY LOGS;
```

## Health Check

The container includes an automated health check:

```yaml
healthcheck:
  test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-uroot", "-p${MYSQL_ROOT_PASSWORD}"]
  interval: 10s
  timeout: 5s
  retries: 5
```

## Networking

- **Network**: `cdc_network` (external)
- **Hostname**: `mysql`

CDC services in [02-cdc-patterns/](../../02-cdc-patterns/) can connect to this instance via `mysql:3306`.

## Data Persistence

MySQL data is stored in a named volume:

```yaml
volumes:
  mysql_data:
    driver: local
```

To reset the database:

```bash
docker compose -f 01-sources/mysql/compose.yaml down -v
```

⚠️ **Warning**: The `-v` flag deletes all data permanently.

## CDC Compatibility

This MySQL configuration is tested with:

- **Debezium MySQL Connector**: Requires `binlog_format=ROW` and GTID mode
- **Flink CDC MySQL Connector**: Requires `binlog_format=ROW`
- **Kafka Connect**: Compatible with standard JDBC source connectors

## Troubleshooting

### Binary Logs Not Enabled

```sql
-- Check if binary logging is active
SELECT @@log_bin;
-- Should return 1
```

### Binary Log Position Not Advancing

```sql
-- Generate some activity
INSERT INTO test_table VALUES (1, 'test');

-- Check if binlog position changed
SHOW MASTER STATUS;
```

### Disk Space Issues

Binary logs can grow quickly. Monitor usage:

```bash
docker exec mysql du -sh /var/lib/mysql/mysql-bin.*
```

Purge old logs manually:

```sql
PURGE BINARY LOGS BEFORE DATE_SUB(NOW(), INTERVAL 3 DAY);
```

## Next Steps

After MySQL is running, choose a CDC pattern:

- [Debezium + Kafka + Flink](../../02-cdc-patterns/debezium-kafka-flink/) - For complex event processing
- [Flink CDC Direct](../../02-cdc-patterns/flink-cdc-direct/) - For low-latency streaming

## References

- [MySQL Binary Log Reference](https://dev.mysql.com/doc/refman/8.0/en/binary-log.html)
- [Debezium MySQL Connector](https://debezium.io/documentation/reference/stable/connectors/mysql.html)
- [Flink CDC MySQL](https://nightlies.apache.org/flink/flink-cdc-docs-master/docs/connectors/flink-sources/mysql-cdc/)
