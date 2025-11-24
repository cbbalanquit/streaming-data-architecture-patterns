# Full Stack: MySQL → Flink CDC Direct → Iceberg + StarRocks

## Architecture

```
┌──────────────────┐
│      MySQL       │  Binary Log (CDC enabled)
│    (Source DB)   │  Port: 3306
└────────┬─────────┘
         │
         │ BinLog Stream
         v
┌──────────────────┐
│   Flink Cluster  │  Direct CDC Connector
│  (CDC + Process) │  Web UI: 8082
│  - JobManager    │
│  - TaskManager   │
│  - SQL Client    │
└────────┬─────────┘
         │
         ├──────────────────────────┐
         v                          v
┌──────────────────┐       ┌──────────────────┐
│     Iceberg      │       │    StarRocks     │
│   + MinIO S3     │       │   Native Tables  │
│                  │       │                  │
│ - REST Catalog   │       │ - FrontEnd (FE)  │
│   Port: 8181     │       │   MySQL: 9030    │
│ - MinIO          │       │   Web: 8030      │
│   API: 9000      │       │ - BackEnd (BE)   │
│   Console: 9001  │       │   API: 8040      │
└──────────────────┘       └──────────────────┘
         │
         └──────> StarRocks can query Iceberg via External Catalog
```

## Components

| Service | Purpose | Port(s) | UI/Access |
|---------|---------|---------|-----------|
| **mysql** | Source database | 3306 | `mysql -h 127.0.0.1 -P 3306` |
| **sql-client** | Flink SQL interface | - | `docker exec -it sql-client bash` |
| **jobmanager** | Flink coordinator | 8082 | http://localhost:8082 |
| **taskmanager** | Flink executor | - | - |
| **iceberg-rest** | Iceberg catalog | 8181 | REST API |
| **minio** | S3 storage | 9000, 9001 | http://localhost:9001 |
| **starrocks-fe** | Query coordinator | 8030, 9030 | `mysql -h 127.0.0.1 -P 9030` |
| **starrocks-be** | Query executor | 8040 | - |

## Use Cases

✅ **Best for:**
- Real-time data lake ingestion (< 1 second latency)
- Hybrid storage strategy (hot data in StarRocks, cold in Iceberg)
- Multi-engine analytics (query same data with Flink, StarRocks, Spark)
- Simplified operations (fewer moving parts than Kafka-based)

❌ **Not ideal for:**
- Multiple independent consumers of CDC stream
- Event replay requirements
- Very complex stream processing with multiple stages

## Prerequisites

- Docker and Docker Compose v2+
- 8GB+ RAM recommended
- Networks created: `docker compose -f ../../infra/networks.yaml up -d`

## Deployment

### 1. Create Networks

```bash
docker compose -f ../../infra/networks.yaml up -d
```

### 2. Start the Full Stack

```bash
# From this directory
docker compose --env-file ../../env/common.env up -d
```

### 3. Verify All Services

```bash
docker compose ps
```

Expected: All services should show `healthy` or `running` status.

### 4. Check Logs

```bash
# Watch all logs
docker compose logs -f

# Check specific services
docker logs -f jobmanager
docker logs -f starrocks-fe
docker logs -f mysql
```

## Example Workflow

### Step 1: Prepare MySQL Data

```bash
# Connect to MySQL
docker exec -it mysql mysql -uroot -p${MYSQL_ROOT_PASSWORD}
```

```sql
-- Create test database and table
CREATE DATABASE IF NOT EXISTS testdb;
USE testdb;

CREATE TABLE users (
  id INT PRIMARY KEY AUTO_INCREMENT,
  name VARCHAR(100),
  email VARCHAR(255),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Insert sample data
INSERT INTO users (name, email) VALUES
  ('Alice', 'alice@example.com'),
  ('Bob', 'bob@example.com'),
  ('Charlie', 'charlie@example.com');
```

### Step 2: Create CDC Stream in Flink

```bash
# Connect to Flink SQL Client
docker exec -it sql-client bash -c "sql-client.sh"
```

```sql
-- Create MySQL CDC source
CREATE TABLE mysql_users (
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
  'database-name' = 'testdb',
  'table-name' = 'users'
);

-- Test: View CDC stream
SELECT * FROM mysql_users;
```

### Step 3: Write to Iceberg

```sql
-- Create Iceberg catalog
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
CREATE DATABASE IF NOT EXISTS lakehouse;

-- Create Iceberg table
CREATE TABLE lakehouse.users (
  id INT,
  name STRING,
  email STRING,
  created_at TIMESTAMP(3),
  updated_at TIMESTAMP(3),
  PRIMARY KEY (id) NOT ENFORCED
) WITH (
  'format-version' = '2',
  'write.upsert.enabled' = 'true'
);

-- Stream CDC to Iceberg
INSERT INTO iceberg_catalog.lakehouse.users
SELECT * FROM default_catalog.default_database.mysql_users;
```

### Step 4: Write to StarRocks Native Table

First, create the table in StarRocks:

```bash
# Connect to StarRocks
docker exec -it starrocks-fe mysql -h 127.0.0.1 -P 9030 -uroot
```

```sql
CREATE DATABASE IF NOT EXISTS analytics;
USE analytics;

CREATE TABLE users (
  id INT NOT NULL,
  name VARCHAR(100),
  email VARCHAR(255),
  created_at DATETIME,
  updated_at DATETIME
) PRIMARY KEY (id)
DISTRIBUTED BY HASH(id) BUCKETS 10;
```

Back in Flink SQL Client:

```sql
-- Create StarRocks sink
USE CATALOG default_catalog;

CREATE TABLE starrocks_users (
  id INT,
  name STRING,
  email STRING,
  created_at TIMESTAMP(3),
  updated_at TIMESTAMP(3),
  PRIMARY KEY (id) NOT ENFORCED
) WITH (
  'connector' = 'jdbc',
  'url' = 'jdbc:mysql://starrocks-fe:9030/analytics',
  'table-name' = 'users',
  'username' = 'root',
  'password' = ''
);

-- Stream CDC to StarRocks
INSERT INTO starrocks_users
SELECT * FROM mysql_users;
```

### Step 5: Query from StarRocks (Both Native and Iceberg)

```sql
-- In StarRocks MySQL client
USE analytics;

-- Query native table (fastest)
SELECT * FROM users;

-- Create external Iceberg catalog
CREATE EXTERNAL CATALOG iceberg_catalog
PROPERTIES (
  "type" = "iceberg",
  "iceberg.catalog.type" = "rest",
  "iceberg.catalog.uri" = "http://iceberg-rest:8181",
  "iceberg.catalog.warehouse" = "s3://warehouse/",
  "aws.s3.endpoint" = "http://minio:9000",
  "aws.s3.access_key" = "admin",
  "aws.s3.secret_key" = "password",
  "aws.s3.enable_path_style_access" = "true"
);

-- Query Iceberg table
SET CATALOG iceberg_catalog;
SELECT * FROM lakehouse.users;

-- Join native and Iceberg tables
SELECT
  n.id,
  n.name AS native_name,
  i.name AS iceberg_name,
  n.updated_at AS native_update,
  i.updated_at AS iceberg_update
FROM default_catalog.analytics.users n
JOIN iceberg_catalog.lakehouse.users i ON n.id = i.id;
```

### Step 6: Test Real-time Updates

```bash
# In MySQL
docker exec -it mysql mysql -uroot -p${MYSQL_ROOT_PASSWORD} testdb
```

```sql
-- Insert new record
INSERT INTO users (name, email) VALUES ('David', 'david@example.com');

-- Update existing record
UPDATE users SET email = 'alice.new@example.com' WHERE id = 1;

-- Delete record
DELETE FROM users WHERE id = 3;
```

Verify changes appear in:
- Flink CDC stream (near real-time)
- Iceberg table (via Flink job)
- StarRocks native table (via Flink job)

## Monitoring

### Flink Dashboard

http://localhost:8082
- Running jobs
- Task metrics
- Checkpoint statistics

### StarRocks Web UI

http://localhost:8030
- Cluster status
- Query execution plans
- Backend metrics

### MinIO Console

http://localhost:9001 (admin / password)
- Storage usage
- Browse data files
- Access key management

## Troubleshooting

### Flink Job Fails to Start

```bash
# Check Flink logs
docker logs jobmanager
docker logs taskmanager

# Common issues:
# 1. Missing JAR files in lib/
# 2. Network connectivity (check cdc_network and iceberg_net)
# 3. MySQL binary log not enabled
```

### Cannot Write to Iceberg

```bash
# Test MinIO connection
docker exec -it jobmanager ping minio

# Verify bucket exists
docker exec -it mc mc ls minio/warehouse/

# Check Iceberg REST catalog
curl http://localhost:8181/v1/config
```

### StarRocks Backend Not Registered

```sql
-- In StarRocks
SHOW BACKENDS\G

-- If not alive, manually add
ALTER SYSTEM ADD BACKEND "starrocks-be:9050";
```

## Performance Tuning

### Flink Checkpoint Configuration

```sql
-- In Flink SQL Client
SET execution.checkpointing.interval = 60000;  -- 1 minute
SET execution.checkpointing.mode = EXACTLY_ONCE;
SET state.backend = rocksdb;
```

### Iceberg Write Optimization

```sql
CREATE TABLE ... WITH (
  'write.format.default' = 'parquet',
  'write.parquet.compression-codec' = 'snappy',
  'write.target-file-size-bytes' = '536870912'  -- 512MB
);
```

### StarRocks Native Table Tuning

```sql
-- Enable data cache
ALTER SYSTEM SET block_cache_enable = true;

-- Analyze table for better query plans
ANALYZE TABLE analytics.users;
```

## Teardown

```bash
# Stop all services
docker compose down

# Remove all data (CAUTION!)
docker compose down -v
```

## Next Steps

- Explore [pre-built jobs](../../02-cdc-patterns/flink-cdc-direct/jobs/)
- Compare with [Debezium+Kafka stack](../debezium-to-iceberg-starrocks/)
- Review [component documentation](../../)

## References

- [Flink CDC Connectors](https://nightlies.apache.org/flink/flink-cdc-docs-master/)
- [Apache Iceberg](https://iceberg.apache.org/)
- [StarRocks Documentation](https://docs.starrocks.io/)
