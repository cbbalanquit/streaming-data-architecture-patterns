# Debezium + Kafka + Flink CDC Pattern

## Overview

This CDC pattern uses **Debezium** to capture MySQL changes, **Kafka** as the event streaming platform, and **Flink** for stream processing. This architecture is ideal for scenarios requiring:

- Multiple downstream consumers
- Complex event routing and transformation
- Decoupled producers and consumers
- Event replay capabilities

## Architecture

```
MySQL (Binary Log)
    ↓
Debezium Connector (CDC capture)
    ↓
Kafka Topics (event streaming)
    ↓
Flink (stream processing)
    ↓
Destinations (Iceberg, StarRocks, etc.)
```

## Components

### Kafka (Apache Kafka 4.1.1)

- **Mode**: KRaft (no Zookeeper dependency)
- **Ports**:
  - `9092`: Internal broker communication
  - `9093`: External client connections
- **Role**: Event streaming broker for CDC events

### Kafka UI (Provectus Kafka UI)

- **Port**: `8080`
- **URL**: http://localhost:8080
- **Purpose**: Web interface for monitoring topics, consumers, and messages

### Debezium Connect (Debezium 3.0)

- **Port**: `8083`
- **API**: REST API for connector management
- **Purpose**: MySQL CDC connector that writes to Kafka topics
- **Internal Topics**:
  - `debezium_configs`: Connector configurations
  - `debezium_offsets`: Tracking binlog positions
  - `debezium_statuses`: Connector health status

### Flink JobManager

- **Port**: `8081`
- **URL**: http://localhost:8081
- **Purpose**: Flink cluster coordinator and web UI

### Flink TaskManager

- **Purpose**: Executes Flink jobs and processes data streams

## When to Use This Pattern

✅ **Use when you need:**
- Multiple consumers reading the same CDC stream
- Event replay from historical data
- Complex stream joins and aggregations
- Decoupled architecture with buffering
- Schema evolution and versioning (via Schema Registry)
- Guaranteed message delivery

❌ **Avoid when:**
- End-to-end latency is critical (<100ms)
- Simple point-to-point data sync is sufficient
- Infrastructure complexity is a concern
- Resource constraints (Kafka requires significant memory)

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

### Start the CDC Pattern

```bash
docker compose -f 02-cdc-patterns/debezium-kafka-flink/compose-debezium-kafka-flink.yaml \
  --env-file env/common.env up -d
```

### Verify Services

```bash
# Check all services are healthy
docker compose -f 02-cdc-patterns/debezium-kafka-flink/compose-debezium-kafka-flink.yaml ps

# Check Kafka is accepting connections
docker exec -it kafka kafka-broker-api-versions.sh --bootstrap-server localhost:9092

# Access Kafka UI
open http://localhost:8080

# Access Flink UI
open http://localhost:8081
```

## Configuring Debezium Connector

### Register MySQL CDC Connector

Create a file [`connectors/mysql-connector.json`](connectors/mysql-connector.json):

```json
{
  "name": "mysql-connector",
  "config": {
    "connector.class": "io.debezium.connector.mysql.MySqlConnector",
    "database.hostname": "mysql",
    "database.port": "3306",
    "database.user": "${MYSQL_USER}",
    "database.password": "${MYSQL_PASSWORD}",
    "database.server.id": "184054",
    "database.server.name": "mysql",
    "table.include.list": "mydatabase.*",
    "database.history.kafka.bootstrap.servers": "kafka:9092",
    "database.history.kafka.topic": "schema-changes.mysql",
    "include.schema.changes": "true",
    "transforms": "unwrap",
    "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
    "transforms.unwrap.drop.tombstones": "false",
    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "key.converter.schemas.enable": "true",
    "value.converter.schemas.enable": "true"
  }
}
```

### Deploy the Connector

```bash
curl -i -X POST -H "Accept:application/json" -H "Content-Type:application/json" \
  http://localhost:8083/connectors/ \
  -d @02-cdc-patterns/debezium-kafka-flink/connectors/mysql-connector.json
```

### Verify Connector Status

```bash
# List all connectors
curl http://localhost:8083/connectors/

# Check connector status
curl http://localhost:8083/connectors/mysql-connector/status
```

### View CDC Events in Kafka

```bash
# List topics
docker exec -it kafka kafka-topics.sh --bootstrap-server localhost:9092 --list

# Consume messages from a table topic
docker exec -it kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic mysql.mydatabase.your_table \
  --from-beginning
```

## Flink Job Examples

### Example: Stream CDC to Console

Create a Flink SQL job [`jobs/cdc-to-console.sql`](jobs/cdc-to-console.sql):

```sql
-- Create Kafka source table
CREATE TABLE mysql_cdc_source (
  id INT,
  name STRING,
  email STRING,
  created_at TIMESTAMP(3),
  WATERMARK FOR created_at AS created_at - INTERVAL '5' SECOND
) WITH (
  'connector' = 'kafka',
  'topic' = 'mysql.mydatabase.users',
  'properties.bootstrap.servers' = 'kafka:9092',
  'properties.group.id' = 'flink-consumer',
  'scan.startup.mode' = 'earliest-offset',
  'format' = 'debezium-json'
);

-- Query the stream
SELECT * FROM mysql_cdc_source;
```

### Submit via Flink SQL Client

```bash
# Connect to Flink SQL client
docker exec -it flink-jobmanager bash -c "sql-client.sh"

# Paste the SQL above
```

## Monitoring

### Kafka UI

Navigate to http://localhost:8080 to monitor:
- Topic message rates
- Consumer lag
- Partition distribution
- Message content

### Flink Dashboard

Navigate to http://localhost:8081 to monitor:
- Running/completed jobs
- Task parallelism
- Checkpoints
- Backpressure

### Debezium Connector Logs

```bash
docker logs -f debezium
```

## Troubleshooting

### Connector Fails to Start

```bash
# Check connector logs
curl http://localhost:8083/connectors/mysql-connector/status

# Common issues:
# 1. MySQL user doesn't have REPLICATION permissions
# 2. Binary log not enabled (check MySQL config)
# 3. GTID mode mismatch
```

### No Messages in Kafka Topics

```bash
# Verify MySQL has activity
docker exec -it mysql mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "SHOW BINARY LOGS;"

# Check Debezium is reading binlog
curl http://localhost:8083/connectors/mysql-connector/status | jq '.tasks[0].state'
```

### Flink Job Fails

```bash
# Check JobManager logs
docker logs flink-jobmanager

# Common issues:
# 1. Missing Kafka connector JARs
# 2. Incorrect Kafka bootstrap servers
# 3. Topic doesn't exist
```

## Performance Tuning

### Kafka

```yaml
environment:
  KAFKA_HEAP_OPTS: "-Xms1G -Xmx2G"
  KAFKA_LOG_RETENTION_HOURS: 168  # 7 days
```

### Debezium

```json
{
  "max.batch.size": "2048",
  "max.queue.size": "8192",
  "poll.interval.ms": "1000"
}
```

### Flink

```yaml
environment:
  JOB_MANAGER_MEMORY: "1024m"
  TASK_MANAGER_MEMORY: "2048m"
```

## Comparison with Flink CDC Direct

| Feature | Debezium+Kafka+Flink | Flink CDC Direct |
|---------|----------------------|------------------|
| Latency | Higher (~seconds) | Lower (~milliseconds) |
| Multiple Consumers | ✅ Easy | ❌ Requires duplication |
| Event Replay | ✅ Yes | ❌ No |
| Complexity | High | Low |
| Resource Usage | High | Low |
| Operational Overhead | Higher | Lower |

## Next Steps

1. Configure destinations:
   - [Iceberg + MinIO](../../03-destinations/iceberg-minio/)
   - [StarRocks](../../03-destinations/starrocks/)

2. Review full-stack examples:
   - [End-to-End Pipeline](../../04-full-stacks/)

3. Advanced Flink jobs:
   - See [`jobs/`](jobs/) for examples

## References

- [Debezium MySQL Connector](https://debezium.io/documentation/reference/stable/connectors/mysql.html)
- [Apache Kafka Documentation](https://kafka.apache.org/documentation/)
- [Flink Kafka Connector](https://nightlies.apache.org/flink/flink-docs-stable/docs/connectors/datastream/kafka/)
- [Kafka UI](https://docs.kafka-ui.provectus.io/)
