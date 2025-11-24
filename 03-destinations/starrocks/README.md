# StarRocks Destination

## Overview

StarRocks is a high-performance OLAP database designed for real-time analytics. It provides:

- **Sub-second query latency** on massive datasets
- **Native tables** for fastest performance
- **Iceberg external tables** for data lake integration
- **Materialized views** for pre-aggregated analytics
- **MySQL protocol compatibility** for easy integration

## Architecture

```
StarRocks Cluster
├── FrontEnd (FE) - Coordinator & SQL Engine
└── BackEnd (BE) - Data Storage & Query Execution
```

## Components

### StarRocks FrontEnd (FE)

- **Ports**:
  - `8030`: HTTP Web UI and API
  - `9020`: Thrift RPC (internal)
  - `9030`: MySQL protocol (SQL client connections)
- **Purpose**: Cluster coordinator, query optimizer, metadata manager
- **Web UI**: http://localhost:8030

### StarRocks BackEnd (BE)

- **Port**: `8040` - HTTP API for monitoring
- **Purpose**: Data storage, query execution, aggregation
- **Auto-registration**: Automatically registers with FE on startup

## Deployment

### Prerequisites

1. Network must exist:
   ```bash
   docker compose -f infra/networks.yaml up -d
   ```

### Start StarRocks

```bash
docker compose -f 03-destinations/starrocks/compose.yaml \
  --env-file env/common.env up -d
```

### Verify Health

```bash
# Check service status
docker compose -f 03-destinations/starrocks/compose.yaml ps

# Connect to FE
docker exec -it starrocks-fe mysql -h 127.0.0.1 -P 9030 -uroot

# Check FE status
docker exec -it starrocks-fe mysql -h 127.0.0.1 -P 9030 -uroot -e "SHOW FRONTENDS\G"

# Check BE status
docker exec -it starrocks-fe mysql -h 127.0.0.1 -P 9030 -uroot -e "SHOW BACKENDS\G"
```

Expected output:
- FE `Alive: true`
- BE `Alive: true`

## Usage

### Connect via MySQL Client

```bash
# From host machine
mysql -h 127.0.0.1 -P 9030 -uroot

# From Docker network
docker run --rm --network iceberg_net mysql:8.0 \
  mysql -h starrocks-fe -P 9030 -uroot
```

### Create Database and Table

```sql
-- Create database
CREATE DATABASE IF NOT EXISTS analytics;
USE analytics;

-- Create Primary Key table (for real-time upserts)
CREATE TABLE users (
  id INT NOT NULL,
  name VARCHAR(100),
  email VARCHAR(255),
  created_at DATETIME,
  updated_at DATETIME
) PRIMARY KEY (id)
DISTRIBUTED BY HASH(id) BUCKETS 10;

-- Insert sample data
INSERT INTO users VALUES
  (1, 'Alice', 'alice@example.com', NOW(), NOW()),
  (2, 'Bob', 'bob@example.com', NOW(), NOW());

-- Query
SELECT * FROM users;
```

### Table Types in StarRocks

#### 1. Primary Key Table (Recommended for CDC)

```sql
CREATE TABLE orders (
  order_id BIGINT NOT NULL,
  customer_id INT,
  amount DECIMAL(10, 2),
  order_date DATETIME,
  PRIMARY KEY (order_id)
) DISTRIBUTED BY HASH(order_id) BUCKETS 10
PROPERTIES (
  "replication_num" = "1"
);
```

**Use case**: Real-time upserts from CDC streams

#### 2. Duplicate Key Table

```sql
CREATE TABLE events (
  event_id STRING,
  user_id INT,
  event_type STRING,
  event_time DATETIME
) DUPLICATE KEY (event_id)
DISTRIBUTED BY HASH(event_id) BUCKETS 10;
```

**Use case**: Append-only event logs

#### 3. Aggregate Key Table

```sql
CREATE TABLE metrics (
  metric_date DATE,
  metric_name STRING,
  total_count BIGINT SUM,
  avg_value DOUBLE AVG
) AGGREGATE KEY (metric_date, metric_name)
DISTRIBUTED BY HASH(metric_date) BUCKETS 10;
```

**Use case**: Pre-aggregated metrics

### External Iceberg Tables

StarRocks can query Iceberg tables stored in MinIO:

```sql
-- Create Iceberg catalog
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

-- Switch to Iceberg catalog
SET CATALOG iceberg_catalog;

-- Query Iceberg tables
SELECT * FROM cdc_data.users LIMIT 10;

-- Join native and Iceberg tables
SELECT
  n.order_id,
  n.amount,
  i.user_name
FROM default_catalog.analytics.orders n
JOIN iceberg_catalog.cdc_data.users i
  ON n.customer_id = i.id;
```

## Integration with CDC Patterns

### From Flink CDC Direct

See example: [cdc-to-starrocks.sql](../../02-cdc-patterns/flink-cdc-direct/jobs/cdc-to-starrocks.sql)

```sql
-- In Flink SQL Client
CREATE TABLE starrocks_sink (
  id INT,
  name STRING,
  email STRING,
  PRIMARY KEY (id) NOT ENFORCED
) WITH (
  'connector' = 'jdbc',
  'url' = 'jdbc:mysql://starrocks-fe:9030/analytics',
  'table-name' = 'users',
  'username' = 'root',
  'password' = ''
);

-- Stream CDC to StarRocks
INSERT INTO starrocks_sink SELECT * FROM mysql_cdc_source;
```

### From Debezium+Kafka

Use Flink as a bridge:
1. Read from Kafka topics (Debezium format)
2. Transform as needed
3. Write to StarRocks via JDBC connector

## Performance Features

### Data Cache

BackEnd is configured with data caching enabled:

```properties
block_cache_enable = true
block_cache_mem_size = 536870912   # 512MB memory cache
block_cache_disk_size = 1073741824 # 1GB disk cache
```

### Query Optimization

```sql
-- Enable CBO (Cost-Based Optimizer)
SET enable_cbo = true;

-- Use materialized views for fast aggregations
CREATE MATERIALIZED VIEW daily_sales AS
SELECT
  DATE(order_date) as sale_date,
  COUNT(*) as order_count,
  SUM(amount) as total_amount
FROM orders
GROUP BY DATE(order_date);

-- Query automatically uses the MV
SELECT * FROM daily_sales WHERE sale_date = '2025-11-24';
```

## Monitoring

### Web UI

Navigate to http://localhost:8030 for:
- Cluster status
- Query execution plans
- Backend metrics
- Table statistics

### SQL Commands

```sql
-- Show cluster information
SHOW FRONTENDS;
SHOW BACKENDS;

-- Show running queries
SHOW PROCESSLIST;

-- Table statistics
SHOW DATA;
SHOW PARTITIONS FROM analytics.users;

-- Query profile (after running a query)
SHOW PROFILELIST;
```

### Metrics Endpoint

```bash
# FE metrics
curl http://localhost:8030/metrics

# BE metrics
curl http://localhost:8040/metrics
```

## Troubleshooting

### Backend Not Registered

```sql
-- Check BE status
SHOW BACKENDS\G

-- Manually add BE (if auto-registration failed)
ALTER SYSTEM ADD BACKEND "starrocks-be:9050";
```

### High Query Latency

```sql
-- Check table statistics
ANALYZE TABLE analytics.users;

-- Check query profile
EXPLAIN SELECT * FROM users WHERE id = 1;
```

### Connection Refused

```bash
# Check FE is listening
docker exec -it starrocks-fe netstat -tlnp | grep 9030

# Check healthcheck status
docker inspect starrocks-fe | jq '.[0].State.Health'
```

## Performance Comparison: Native vs Iceberg

From repository learnings:

| Metric | Native Tables | Iceberg Tables |
|--------|---------------|----------------|
| Query Latency | ⚡ Faster | Slower |
| Write Performance | ⚡ Faster | Slower |
| Storage Format | Proprietary | Open (Parquet) |
| Tool Integration | Limited | ✅ Wide (Spark, Flink, Trino) |
| ACID Transactions | ✅ Yes | ✅ Yes |
| Time Travel | ❌ No | ✅ Yes |

**Recommendation**:
- **Use Native Tables** for high-performance serving layer
- **Use Iceberg Tables** for data lake integration and multi-engine access

## Next Steps

1. Set up CDC pipeline:
   - [Flink CDC Direct](../../02-cdc-patterns/flink-cdc-direct/)
   - [Debezium+Kafka+Flink](../../02-cdc-patterns/debezium-kafka-flink/)

2. Configure Iceberg integration:
   - [Iceberg + MinIO](../../03-destinations/iceberg-minio/)

3. Review full-stack examples:
   - [End-to-End Pipelines](../../04-full-stacks/)

## References

- [StarRocks Documentation](https://docs.starrocks.io/)
- [StarRocks Table Types](https://docs.starrocks.io/docs/table_design/table_types/primary_key_table/)
- [StarRocks Iceberg Catalog](https://docs.starrocks.io/docs/data_source/catalog/iceberg_catalog/)
- [StarRocks MySQL Protocol](https://docs.starrocks.io/docs/administration/management/FE_configuration/#mysql)
