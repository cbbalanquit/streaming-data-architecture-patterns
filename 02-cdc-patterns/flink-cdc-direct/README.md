# Flink CDC Direct Pattern

## Overview

This CDC pattern uses **Flink CDC connectors** to directly capture changes from MySQL without an intermediary message broker. This architecture is ideal for:

- Low-latency streaming pipelines
- Point-to-point data synchronization
- Simplified operational overhead
- Resource-constrained environments

## Architecture

```
MySQL (Binary Log)
    ↓
Flink CDC Connector (direct read)
    ↓
Flink Stream Processing
    ↓
Destinations (Iceberg, StarRocks, etc.)
```

## Components

### Flink SQL Client

- **Purpose**: Interactive SQL interface for ad-hoc queries and job submission
- **Access**: `docker exec -it sql-client bash`

### Flink JobManager

- **Port**: `8082`
- **URL**: http://localhost:8082
- **Purpose**: Cluster coordinator and web UI

### Flink TaskManager

- **Task Slots**: 2 per task manager
- **Purpose**: Executes Flink jobs

### Pre-installed JARs

The `lib/` directory contains required connectors:

```
lib/
├── flink-shaded-hadoop-2-uber-2.7.5-10.0.jar       # Hadoop filesystem support
├── flink-sql-connector-mysql-cdc-3.5.0.jar         # MySQL CDC source
└── iceberg-flink-runtime-1.16-1.3.1.jar            # Iceberg table format support
```

## When to Use This Pattern

✅ **Use when you need:**
- End-to-end latency < 1 second
- Simple source → transform → sink pipelines
- Lower infrastructure complexity
- Fewer moving parts to maintain
- Direct control over checkpointing and exactly-once semantics

❌ **Avoid when:**
- Multiple consumers need the same CDC stream
- Event replay from historical data is required
- You need to decouple producers from consumers
- Schema evolution requires a central registry

## Deployment

### Prerequisites

1. Networks must exist:
   ```bash
   docker compose -f infra/networks.yaml up -d
   ```

2. MySQL source must be running:
   ```bash
   docker compose -f 01-sources/mysql/compose.yaml --env-file env/common.env up -d
   ```

3. Download required JARs (if not present):
   ```bash
   cd 02-cdc-patterns/flink-cdc-direct/lib

   # Flink MySQL CDC Connector
   wget https://repo1.maven.org/maven2/org/apache/flink/flink-sql-connector-mysql-cdc/3.5.0/flink-sql-connector-mysql-cdc-3.5.0.jar

   # Iceberg Flink Runtime
   wget https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-flink-runtime-1.16/1.3.1/iceberg-flink-runtime-1.16-1.3.1.jar

   # Hadoop Dependencies
   wget https://repo.maven.apache.org/maven2/org/apache/flink/flink-shaded-hadoop-2-uber/2.7.5-10.0/flink-shaded-hadoop-2-uber-2.7.5-10.0.jar
   ```

### Start the CDC Pattern

```bash
docker compose -f 02-cdc-patterns/flink-cdc-direct/compose-flink-cdc.yaml \
  --env-file env/common.env up -d
```

### Verify Services

```bash
# Check all services are running
docker compose -f 02-cdc-patterns/flink-cdc-direct/compose-flink-cdc.yaml ps

# Access Flink Web UI
open http://localhost:8082

# Connect to SQL client
docker exec -it sql-client bash
sql-client.sh
```

## Using Flink CDC

### Example 1: Stream MySQL Table to Console

Connect to the SQL client:

```bash
docker exec -it sql-client bash -c "sql-client.sh"
```

Create a CDC source table:

```sql
-- Create a table that reads directly from MySQL
CREATE TABLE users (
  id INT PRIMARY KEY NOT ENFORCED,
  name STRING,
  email STRING,
  created_at TIMESTAMP(3),
  updated_at TIMESTAMP(3)
) WITH (
  'connector' = 'mysql-cdc',
  'hostname' = 'mysql',
  'port' = '3306',
  'username' = 'myuser',
  'password' = 'mypassword',
  'database-name' = 'mydatabase',
  'table-name' = 'users',
  'server-time-zone' = 'UTC'
);

-- Query the CDC stream
SELECT * FROM users;
```

### Example 2: Stream to Iceberg Table

```sql
-- Create CDC source
CREATE TABLE mysql_orders (
  order_id INT PRIMARY KEY NOT ENFORCED,
  customer_id INT,
  amount DECIMAL(10, 2),
  order_date TIMESTAMP(3)
) WITH (
  'connector' = 'mysql-cdc',
  'hostname' = 'mysql',
  'port' = '3306',
  'username' = 'myuser',
  'password' = 'mypassword',
  'database-name' = 'mydatabase',
  'table-name' = 'orders'
);

-- Create Iceberg sink
CREATE CATALOG iceberg_catalog WITH (
  'type' = 'iceberg',
  'catalog-type' = 'rest',
  'uri' = 'http://iceberg-rest:8181',
  'warehouse' = 's3://warehouse/',
  'io-impl' = 'org.apache.iceberg.aws.s3.S3FileIO',
  's3.endpoint' = 'http://minio:9000',
  's3.access-key-id' = 'admin',
  's3.secret-access-key' = 'password',
  's3.path-style-access' = 'true'
);

USE CATALOG iceberg_catalog;

CREATE DATABASE IF NOT EXISTS cdc_data;

-- Create Iceberg table
CREATE TABLE cdc_data.orders (
  order_id INT,
  customer_id INT,
  amount DECIMAL(10, 2),
  order_date TIMESTAMP(3),
  PRIMARY KEY (order_id) NOT ENFORCED
) WITH (
  'format-version' = '2',
  'write.upsert.enabled' = 'true'
);

-- Stream MySQL CDC to Iceberg
INSERT INTO iceberg_catalog.cdc_data.orders
SELECT * FROM default_catalog.default_database.mysql_orders;
```

### Example 3: Aggregation with Windowing

```sql
-- Calculate hourly order totals
CREATE TABLE hourly_sales (
  window_start TIMESTAMP(3),
  window_end TIMESTAMP(3),
  total_orders BIGINT,
  total_amount DECIMAL(10, 2),
  PRIMARY KEY (window_start) NOT ENFORCED
) WITH (
  'connector' = 'jdbc',
  'url' = 'jdbc:mysql://mysql:3306/analytics',
  'table-name' = 'hourly_sales',
  'username' = 'myuser',
  'password' = 'mypassword'
);

-- Aggregate CDC stream into hourly windows
INSERT INTO hourly_sales
SELECT
  TUMBLE_START(order_date, INTERVAL '1' HOUR) as window_start,
  TUMBLE_END(order_date, INTERVAL '1' HOUR) as window_end,
  COUNT(*) as total_orders,
  SUM(amount) as total_amount
FROM mysql_orders
GROUP BY TUMBLE(order_date, INTERVAL '1' HOUR);
```

## Job Examples

Pre-built SQL job examples are available in [`jobs/`](jobs/):

```
jobs/
├── cdc-to-console.sql           # Basic CDC streaming
├── cdc-to-iceberg.sql           # Write to Iceberg table
└── cdc-to-starrocks.sql         # Write to StarRocks native table
```

### Submit a Job

```bash
# Via SQL client (interactive)
docker exec -it sql-client bash -c "sql-client.sh < /opt/flink/jobs/cdc-to-iceberg.sql"

# Or connect to SQL client and paste the SQL
docker exec -it sql-client bash -c "sql-client.sh"
```

## Monitoring

### Flink Dashboard

Navigate to http://localhost:8082 to monitor:
- Running jobs
- Checkpoint statistics
- Task manager metrics
- Job parallelism

### Check CDC Progress

```sql
-- In Flink SQL Client
SHOW JOBS;

-- Get job details
DESCRIBE JOB '<job-id>';
```

### View Logs

```bash
# JobManager logs
docker logs flink-jobmanager

# TaskManager logs
docker logs flink-taskmanager

# SQL Client logs
docker logs sql-client
```

## Troubleshooting

### Connection to MySQL Failed

```sql
-- Verify MySQL is reachable from Flink
-- In SQL client:
SHOW DATABASES;
```

Common fixes:
1. Check `cdc_network` exists and both containers are connected
2. Verify MySQL credentials in SQL DDL
3. Ensure MySQL binary logging is enabled

### Binary Log Not Available

```bash
# Check MySQL binary log configuration
docker exec -it mysql mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "SHOW VARIABLES LIKE 'log_bin';"
```

Should return `ON`. If not, see [MySQL configuration](../../01-sources/mysql/README.md#binary-log-settings).

### Missing Connector JARs

```bash
# List JARs in Flink
docker exec -it jobmanager ls -lh /opt/flink/lib/

# Ensure mysql-cdc JAR is present
docker exec -it jobmanager ls -lh /opt/flink/lib/ | grep mysql-cdc
```

### Iceberg Write Failures

Common issues:
1. MinIO not accessible: Check `iceberg_net` network
2. S3 credentials incorrect: Verify `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`
3. Bucket doesn't exist: Run MinIO client setup (see [Iceberg destination](../../03-destinations/iceberg-minio/))

## Performance Tuning

### Parallelism

```yaml
# In compose.yaml
environment:
  FLINK_PROPERTIES: |
    parallelism.default: 2
    taskmanager.numberOfTaskSlots: 2
```

### Checkpoint Configuration

```sql
-- In Flink SQL
SET execution.checkpointing.interval = 60000;  -- 60 seconds
SET execution.checkpointing.mode = EXACTLY_ONCE;
SET state.backend = rocksdb;
SET state.checkpoints.dir = s3://warehouse/checkpoints;
```

### Memory Settings

```yaml
environment:
  JOB_MANAGER_MEMORY: "1024m"
  TASK_MANAGER_MEMORY: "2048m"
```

## Comparison with Debezium+Kafka Pattern

| Feature | Flink CDC Direct | Debezium+Kafka+Flink |
|---------|------------------|----------------------|
| Latency | ~100-500ms | ~1-3 seconds |
| Multiple Consumers | ❌ Requires job duplication | ✅ Kafka provides fan-out |
| Event Replay | ❌ No | ✅ Yes (from Kafka retention) |
| Complexity | Low | High |
| Resource Usage | Low | High |
| Operational Overhead | Lower | Higher |
| Exactly-Once | ✅ Native Flink | ✅ Flink + Kafka transactions |

## Next Steps

1. Configure destinations:
   - [Iceberg + MinIO](../../03-destinations/iceberg-minio/)
   - [StarRocks](../../03-destinations/starrocks/)

2. Review full-stack examples:
   - [End-to-End Pipeline](../../04-full-stacks/)

3. Advanced job examples:
   - See [`jobs/`](jobs/) directory

## References

- [Flink CDC Connectors](https://nightlies.apache.org/flink/flink-cdc-docs-master/)
- [Flink MySQL CDC Connector](https://nightlies.apache.org/flink/flink-cdc-docs-master/docs/connectors/flink-sources/mysql-cdc/)
- [Apache Iceberg Flink Integration](https://iceberg.apache.org/docs/latest/flink/)
- [Flink SQL Client](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sqlclient/)
