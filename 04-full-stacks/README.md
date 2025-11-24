# Full Stack Examples

This directory contains end-to-end pipeline configurations that combine components from sources, CDC patterns, and destinations into complete streaming architectures.

## Available Stacks

### 1. [Flink CDC → Iceberg + StarRocks](flink-cdc-to-iceberg-starrocks/)

**Pattern**: Direct MySQL CDC without Kafka

```
MySQL → Flink CDC Direct → Iceberg (data lake) + StarRocks (analytics)
```

**Use case**:
- Low-latency streaming (< 1 second)
- Hybrid storage (hot + cold data)
- Multi-engine analytics

**Components**:
- MySQL (source)
- Flink CDC Direct
- MinIO + Iceberg REST
- StarRocks FE/BE

---

### 2. [Debezium + Kafka → Iceberg + StarRocks](debezium-to-iceberg-starrocks/)

**Pattern**: Event-driven CDC with Kafka broker

```
MySQL → Debezium → Kafka → Flink → Iceberg (data lake) + StarRocks (analytics)
```

**Use case**:
- Multiple downstream consumers
- Event replay capability
- Complex stream processing
- Decoupled architecture

**Components**:
- MySQL (source)
- Kafka + Debezium + Kafka UI
- Flink cluster
- MinIO + Iceberg REST
- StarRocks FE/BE

---

## Choosing a Stack

| Requirement | Recommended Stack |
|-------------|-------------------|
| Lowest latency | Flink CDC Direct |
| Multiple consumers | Debezium + Kafka |
| Event replay | Debezium + Kafka |
| Simpler operations | Flink CDC Direct |
| Complex transformations | Debezium + Kafka |
| Resource constraints | Flink CDC Direct |

## Deployment

Each stack includes:
- `compose.yaml` - Complete orchestration file
- `README.md` - Architecture diagram and instructions
- `jobs/` - Flink SQL job examples
- `connectors/` - Connector configurations (Debezium stack only)

### Quick Start

```bash
# Choose a stack
cd 04-full-stacks/flink-cdc-to-iceberg-starrocks

# Create networks
docker compose -f ../../infra/networks.yaml up -d

# Deploy the full stack
docker compose --env-file ../../env/common.env up -d

# Verify all services are healthy
docker compose ps

# Follow the stack-specific README for next steps
```

## Architecture Comparison

### Flink CDC Direct Stack

```
┌─────────┐     ┌──────────────┐     ┌─────────────┐
│  MySQL  │────>│  Flink CDC   │────>│   Iceberg   │
│ (source)│     │   Cluster    │     │   (MinIO)   │
└─────────┘     └──────────────┘     └─────────────┘
                        │                    │
                        │                    │
                        v                    v
                ┌──────────────┐     ┌─────────────┐
                │  StarRocks   │<────│  External   │
                │   Native     │     │   Catalog   │
                └──────────────┘     └─────────────┘
```

**Latency**: ~100-500ms
**Complexity**: Low
**Resource Usage**: Moderate

---

### Debezium + Kafka Stack

```
┌─────────┐     ┌──────────┐     ┌───────┐     ┌──────────┐
│  MySQL  │────>│ Debezium │────>│ Kafka │────>│  Flink   │
│ (source)│     │ Connect  │     │Topics │     │ Cluster  │
└─────────┘     └──────────┘     └───────┘     └──────────┘
                                      │              │
                                      v              v
                              ┌──────────┐   ┌─────────────┐
                              │ Kafka UI │   │   Iceberg   │
                              │(monitor) │   │   (MinIO)   │
                              └──────────┘   └─────────────┘
                                                    │
                                                    v
                                            ┌──────────────┐
                                            │  StarRocks   │
                                            │   + Iceberg  │
                                            └──────────────┘
```

**Latency**: ~1-3 seconds
**Complexity**: High
**Resource Usage**: High

---

## Common Operations

### Check All Services

```bash
# From stack directory
docker compose ps

# Check specific service logs
docker logs -f flink-jobmanager
docker logs -f starrocks-fe
docker logs -f iceberg-rest
```

### Access UIs

- **Flink Dashboard**: http://localhost:8081 or http://localhost:8082
- **Kafka UI**: http://localhost:8080 (Debezium stack only)
- **StarRocks**: `mysql -h 127.0.0.1 -P 9030 -uroot`
- **MinIO Console**: http://localhost:9001

### Submit Flink Jobs

```bash
# Connect to SQL client
docker exec -it sql-client bash -c "sql-client.sh"

# Run a pre-built job
docker exec -it sql-client bash -c "sql-client.sh < /opt/flink/jobs/cdc-to-iceberg.sql"
```

### Teardown

```bash
# Stop and remove all containers
docker compose down

# Remove volumes (data will be lost!)
docker compose down -v
```

## Next Steps

1. Review component-specific documentation:
   - [01-sources/](../01-sources/)
   - [02-cdc-patterns/](../02-cdc-patterns/)
   - [03-destinations/](../03-destinations/)

2. Customize configurations in `env/common.env`

3. Add your own Flink SQL jobs in the `jobs/` directory

4. Monitor performance and tune based on your workload

## References

- [Apache Flink CDC](https://nightlies.apache.org/flink/flink-cdc-docs-master/)
- [Debezium Documentation](https://debezium.io/documentation/)
- [Apache Iceberg](https://iceberg.apache.org/)
- [StarRocks Documentation](https://docs.starrocks.io/)
