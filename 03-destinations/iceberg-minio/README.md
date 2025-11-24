# Iceberg + MinIO Destination

## Overview

Apache Iceberg is an open table format for large analytic datasets, providing:

- **ACID transactions** with snapshot isolation
- **Time travel** and rollback capabilities
- **Schema evolution** without rewriting data
- **Hidden partitioning** for automatic data organization
- **Multi-engine support** (Flink, Spark, Trino, StarRocks, etc.)

MinIO provides S3-compatible object storage for Iceberg data files.

## Architecture

```
Iceberg Table Format
├── REST Catalog (metadata management)
├── MinIO (S3-compatible data storage)
└── Compute Engines (Flink, StarRocks, Spark, etc.)
```

## Components

### Iceberg REST Catalog

- **Port**: `8181`
- **Purpose**: Centralized metadata management for Iceberg tables
- **API**: RESTful HTTP API for table operations
- **Warehouse**: `s3://warehouse/`

### MinIO Object Storage

- **Ports**:
  - `9000`: S3 API endpoint
  - `9001`: Web console
- **Web Console**: http://localhost:9001
- **Credentials**: `admin` / `password` (configurable via env vars)
- **Bucket**: `warehouse` (auto-created by `mc` container)

### MinIO Client (mc)

- **Purpose**: Initializes MinIO buckets and policies
- **Auto-configuration**: Creates `warehouse` bucket on startup

## Deployment

### Prerequisites

1. Network must exist:
   ```bash
   docker compose -f infra/networks.yaml up -d
   ```

### Start Iceberg + MinIO

```bash
docker compose -f 03-destinations/iceberg-minio/compose.yaml \
  --env-file env/common.env up -d
```

### Verify Services

```bash
# Check service health
docker compose -f 03-destinations/iceberg-minio/compose.yaml ps

# Access MinIO console
open http://localhost:9001
# Login: admin / password

# Check Iceberg REST catalog
curl http://localhost:8181/v1/config
```

## Using Iceberg Tables

### From Flink CDC

See example: [cdc-to-iceberg.sql](../../02-cdc-patterns/flink-cdc-direct/jobs/cdc-to-iceberg.sql)

```sql
-- In Flink SQL Client
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

-- Create Iceberg table with upsert support
CREATE TABLE cdc_data.users (
  id INT,
  name STRING,
  email STRING,
  created_at TIMESTAMP(3),
  updated_at TIMESTAMP(3),
  PRIMARY KEY (id) NOT ENFORCED
) WITH (
  'format-version' = '2',
  'write.upsert.enabled' = 'true',
  'write.format.default' = 'parquet'
);

-- Stream CDC data to Iceberg
INSERT INTO iceberg_catalog.cdc_data.users
SELECT * FROM default_catalog.default_database.mysql_cdc_source;
```

### From StarRocks

```sql
-- Connect to StarRocks
mysql -h 127.0.0.1 -P 9030 -uroot

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

-- Query Iceberg tables
SET CATALOG iceberg_catalog;
SELECT * FROM cdc_data.users LIMIT 10;
```

### Direct S3 Access

```bash
# Using MinIO client
docker exec -it mc mc ls minio/warehouse/

# Using AWS CLI (if installed)
aws --endpoint-url http://localhost:9000 \
  s3 ls s3://warehouse/ \
  --profile minio
```

## Iceberg Features

### Time Travel

```sql
-- Query table as of specific timestamp
SELECT * FROM cdc_data.users
FOR SYSTEM_TIME AS OF TIMESTAMP '2025-11-24 10:00:00';

-- Query specific snapshot
SELECT * FROM cdc_data.users
FOR SYSTEM_VERSION AS OF 1234567890;

-- View snapshot history
SELECT * FROM cdc_data.users.snapshots;
```

### Schema Evolution

```sql
-- Add column (doesn't rewrite data!)
ALTER TABLE cdc_data.users ADD COLUMN phone STRING;

-- Rename column
ALTER TABLE cdc_data.users RENAME COLUMN name TO full_name;

-- Drop column
ALTER TABLE cdc_data.users DROP COLUMN phone;

-- View schema history
SELECT * FROM cdc_data.users.history;
```

### Partition Evolution

```sql
-- Create partitioned table
CREATE TABLE cdc_data.events (
  event_id STRING,
  user_id INT,
  event_type STRING,
  event_time TIMESTAMP(3)
) PARTITIONED BY (days(event_time));

-- Change partitioning (without rewriting data!)
ALTER TABLE cdc_data.events
SET PARTITION SPEC (hours(event_time));
```

### Metadata Queries

```sql
-- View table snapshots
SELECT * FROM cdc_data.users.snapshots;

-- View table history
SELECT * FROM cdc_data.users.history;

-- View table files
SELECT * FROM cdc_data.users.files;

-- View table manifests
SELECT * FROM cdc_data.users.manifests;
```

## MinIO Administration

### Web Console

Navigate to http://localhost:9001:

- **Buckets**: Create/delete buckets
- **Objects**: Browse data files
- **Access Keys**: Manage credentials
- **Monitoring**: View usage metrics

### CLI Operations

```bash
# List buckets
docker exec -it mc mc ls minio/

# List objects in warehouse
docker exec -it mc mc ls minio/warehouse/

# Create new bucket
docker exec -it mc mc mb minio/my-bucket

# Set public policy
docker exec -it mc mc policy set public minio/my-bucket

# Copy file to MinIO
docker exec -it mc mc cp /path/to/file minio/warehouse/data/
```

## Data Persistence

MinIO data is stored in a Docker volume:

```yaml
volumes:
  minio_data:
    driver: local
```

To reset storage:

```bash
docker compose -f 03-destinations/iceberg-minio/compose.yaml down -v
```

⚠️ **Warning**: This deletes all Iceberg data permanently!

## Integration Patterns

### Pattern 1: Flink CDC → Iceberg → StarRocks

```
MySQL → Flink CDC → Iceberg (data lake)
                         ↓
                   StarRocks (query engine)
```

**Use case**: Decouple storage from compute, query with multiple engines

### Pattern 2: Flink CDC → Iceberg Only

```
MySQL → Flink CDC → Iceberg (data lake)
```

**Use case**: Long-term storage, batch analytics, ad-hoc queries

### Pattern 3: Hybrid (Native + Iceberg)

```
MySQL → Flink CDC → StarRocks Native (hot data)
                  ↘ Iceberg (cold data)
```

**Use case**: Fast queries on recent data, archival of historical data

## Performance Tuning

### MinIO

```yaml
environment:
  MINIO_ROOT_USER: admin
  MINIO_ROOT_PASSWORD: strongpassword
  # Performance settings
  MINIO_SERVER_URL: http://minio:9000
  MINIO_BROWSER_REDIRECT_URL: http://localhost:9001
```

### Iceberg Write Settings

```sql
CREATE TABLE ... WITH (
  'write.format.default' = 'parquet',      -- Columnar format
  'write.parquet.compression-codec' = 'snappy',  -- Fast compression
  'write.target-file-size-bytes' = '536870912',  -- 512MB files
  'write.metadata.delete-after-commit.enabled' = 'true',
  'write.metadata.previous-versions-max' = '100'  -- Keep 100 snapshots
);
```

### Compaction

```sql
-- Compact small files
CALL iceberg_catalog.system.rewrite_data_files(
  table => 'cdc_data.users',
  strategy => 'binpack',
  options => map('min-input-files', '10')
);

-- Remove old snapshots
CALL iceberg_catalog.system.expire_snapshots(
  table => 'cdc_data.users',
  older_than => TIMESTAMP '2025-11-01 00:00:00',
  retain_last => 10
);
```

## Monitoring

### MinIO Metrics

```bash
# Prometheus metrics
curl http://localhost:9000/minio/v2/metrics/cluster
```

### Iceberg Catalog

```bash
# List namespaces
curl http://localhost:8181/v1/namespaces

# List tables
curl http://localhost:8181/v1/namespaces/cdc_data/tables
```

### Storage Usage

```bash
# Check bucket size
docker exec -it mc mc du minio/warehouse/
```

## Troubleshooting

### Cannot Connect to MinIO from Flink

```bash
# Check network connectivity
docker exec -it flink-jobmanager ping minio

# Verify MinIO is healthy
docker exec -it minio curl http://localhost:9000/minio/health/live
```

Common fixes:
1. Ensure both containers are on `iceberg_net`
2. Use `http://minio:9000` (not localhost) from containers
3. Set `s3.path-style-access = true` for MinIO compatibility

### Iceberg REST Catalog Not Responding

```bash
# Check catalog logs
docker logs iceberg-rest

# Test endpoint
curl http://localhost:8181/v1/config
```

### Bucket Not Found

```bash
# List buckets
docker exec -it mc mc ls minio/

# Recreate warehouse bucket
docker exec -it mc mc mb minio/warehouse
docker exec -it mc mc policy set public minio/warehouse
```

### S3 Access Denied

Verify credentials match in:
1. `env/common.env`: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`
2. Flink SQL: `s3.access-key-id`, `s3.secret-access-key`
3. StarRocks catalog: `aws.s3.access_key`, `aws.s3.secret_key`

## Comparison: Iceberg vs StarRocks Native

| Feature | Iceberg Tables | StarRocks Native |
|---------|----------------|------------------|
| Query Performance | Slower | ⚡ Faster |
| Write Performance | Slower | ⚡ Faster |
| Storage Format | Open (Parquet) | Proprietary |
| Multi-Engine | ✅ Flink, Spark, Trino, StarRocks | ❌ StarRocks only |
| Time Travel | ✅ Yes | ❌ No |
| Schema Evolution | ✅ Non-breaking | ⚠️ Limited |
| ACID Transactions | ✅ Yes | ✅ Yes |
| Use Case | Data Lake, long-term storage | Real-time analytics |

## Next Steps

1. Configure CDC pipeline:
   - [Flink CDC Direct](../../02-cdc-patterns/flink-cdc-direct/)
   - [Debezium+Kafka+Flink](../../02-cdc-patterns/debezium-kafka-flink/)

2. Set up query engine:
   - [StarRocks](../../03-destinations/starrocks/)

3. Review full-stack examples:
   - [End-to-End Pipelines](../../04-full-stacks/)

## References

- [Apache Iceberg Documentation](https://iceberg.apache.org/)
- [Iceberg REST Catalog](https://iceberg.apache.org/docs/latest/rest-catalog/)
- [MinIO Documentation](https://min.io/docs/minio/linux/index.html)
- [Flink Iceberg Connector](https://iceberg.apache.org/docs/latest/flink/)
- [StarRocks Iceberg Catalog](https://docs.starrocks.io/docs/data_source/catalog/iceberg_catalog/)
