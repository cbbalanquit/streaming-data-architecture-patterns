# Streaming Data Architecture Patterns

A comprehensive exploration repository for local deployment of streaming data pipelines using MySQL CDC, Apache Flink, Apache Iceberg, and StarRocks.

## Overview

This repository provides modular, production-ready configurations for building real-time data pipelines. It demonstrates multiple CDC (Change Data Capture) patterns and storage strategies for ingesting MySQL changes into a modern data lakehouse architecture.

## Repository Structure

```
streaming-data-architecture-patterns/
│
├── 01-sources/                    # Data sources
│   └── mysql/                     # MySQL with CDC-enabled binlog
│
├── 02-cdc-patterns/               # Change Data Capture implementations
│   ├── debezium-kafka-flink/      # Debezium → Kafka → Flink
│   └── flink-cdc-direct/          # Flink CDC direct connector
│
├── 03-destinations/               # Data sinks and warehouses
│   ├── iceberg-minio/             # Apache Iceberg + MinIO S3
│   └── starrocks/                 # StarRocks OLAP database
│
├── 04-full-stacks/                # End-to-end pipeline examples
│   ├── flink-cdc-to-iceberg-starrocks/
│   └── debezium-to-iceberg-starrocks/
│
├── infra/                         # Shared infrastructure
│   └── networks.yaml              # Docker networks
│
├── env/                           # Environment configuration
│   ├── common.env.example         # Template configuration
│   └── common.env                 # Active configuration (git-ignored)
│
└── scripts/                       # Deployment automation
    ├── deploy.sh                  # Flexible deployment script
    ├── teardown.sh                # Cleanup script
    └── check_prereqs.sh           # Prerequisites validator
```

## Quick Start

### Prerequisites

- Docker 20.10+ and Docker Compose v2+
- 8GB+ RAM recommended
- Basic knowledge of SQL and streaming concepts

### 1. Setup

```bash
# Clone the repository
git clone <repository-url>
cd streaming-data-architecture-patterns

# Copy environment template
cp env/common.env.example env/common.env

# Edit credentials if needed
vim env/common.env

# Check prerequisites
make check
```

### 2. Choose a Deployment Pattern

#### Option A: Full Flink CDC Stack (Recommended for getting started)

```bash
# Deploy: MySQL → Flink CDC → Iceberg + StarRocks
make full-flink-cdc

# Check status
make status

# View service URLs
make urls
```

#### Option B: Full Debezium Stack (For event-driven architectures)

```bash
# Deploy: MySQL → Debezium → Kafka → Flink → Iceberg + StarRocks
make full-debezium

# Check status
make status
```

#### Option C: Individual Components

```bash
# Deploy only what you need
make infra          # Networks
make mysql          # MySQL source
make flink-cdc      # Flink CDC pattern
make iceberg        # Iceberg + MinIO
make starrocks      # StarRocks
```

### 3. Verify and Explore

```bash
# Check all services are running
make ps

# View logs
make logs

# Access UIs
open http://localhost:8082  # Flink Web UI
open http://localhost:9001  # MinIO Console
open http://localhost:8030  # StarRocks Web UI
```

### 4. Test the Pipeline

See [04-full-stacks/README.md](04-full-stacks/README.md) for complete workflow examples.

### 5. Teardown

```bash
# Stop all services (preserves data)
make down

# Stop and remove all data
make down-clean
```

## Architecture Patterns

### Pattern 1: Flink CDC Direct

**Flow**: `MySQL → Flink CDC → Iceberg/StarRocks`

```
┌─────────┐     ┌──────────────┐     ┌─────────────┐
│  MySQL  │────>│  Flink CDC   │────>│   Iceberg   │
│         │     │   Cluster    │     │   + MinIO   │
└─────────┘     └──────────────┘     └─────────────┘
                        │                    │
                        v                    v
                ┌──────────────┐     ┌─────────────┐
                │  StarRocks   │<────│  External   │
                │   Native     │     │   Catalog   │
                └──────────────┘     └─────────────┘
```

**Characteristics**:
- ⚡ **Low latency**: ~100-500ms
- 🎯 **Simple operations**: Fewer moving parts
- 📉 **Lower resource usage**: No Kafka overhead
- ❌ **Single consumer**: No event replay

**Best for**: Point-to-point data sync, real-time analytics, resource-constrained environments

[Read more →](02-cdc-patterns/flink-cdc-direct/README.md)

---

### Pattern 2: Debezium + Kafka

**Flow**: `MySQL → Debezium → Kafka → Flink → Iceberg/StarRocks`

```
┌─────────┐     ┌──────────┐     ┌───────┐     ┌──────────┐
│  MySQL  │────>│ Debezium │────>│ Kafka │────>│  Flink   │
└─────────┘     └──────────┘     └───────┘     └──────────┘
                                      │              │
                                      v              v
                              ┌──────────┐   ┌─────────────┐
                              │ Kafka UI │   │   Iceberg   │
                              │(monitor) │   │  StarRocks  │
                              └──────────┘   └─────────────┘
```

**Characteristics**:
- 🔄 **Event replay**: Kafka retention for reprocessing
- 🎯 **Multiple consumers**: Fan-out to many destinations
- 🔧 **Complex processing**: Rich stream transformations
- 📈 **Higher resource usage**: Kafka broker overhead

**Best for**: Event-driven architectures, multiple consumers, audit trails, complex ETL

[Read more →](02-cdc-patterns/debezium-kafka-flink/README.md)

---

## Components

### Sources

| Component | Purpose | Documentation |
|-----------|---------|---------------|
| **MySQL 8.0** | Transactional source database with binary log CDC | [01-sources/mysql/](01-sources/mysql/README.md) |

### CDC Patterns

| Pattern | Latency | Complexity | Use Case | Documentation |
|---------|---------|------------|----------|---------------|
| **Flink CDC Direct** | ~100-500ms | Low | Point-to-point sync | [flink-cdc-direct/](02-cdc-patterns/flink-cdc-direct/README.md) |
| **Debezium+Kafka** | ~1-3s | High | Event-driven architectures | [debezium-kafka-flink/](02-cdc-patterns/debezium-kafka-flink/README.md) |

### Destinations

| Component | Purpose | Documentation |
|-----------|---------|---------------|
| **Iceberg + MinIO** | Open table format for data lake with S3-compatible storage | [iceberg-minio/](03-destinations/iceberg-minio/README.md) |
| **StarRocks** | High-performance OLAP database for real-time analytics | [starrocks/](03-destinations/starrocks/README.md) |

## Key Features

### ✅ Modular Design
- Mix and match components based on your needs
- Deploy individual services or complete stacks
- Clear separation between sources, processing, and destinations

### ✅ Production-Ready Configurations
- Health checks and restart policies
- Proper networking and service dependencies
- Environment-based configuration management

### ✅ Automated Deployment
- Simple Makefile targets for common operations
- Flexible deployment scripts supporting multiple patterns
- Automated prerequisite checking

### ✅ Comprehensive Documentation
- README in every component directory
- Architectural diagrams and comparisons
- Real-world examples and troubleshooting guides

### ✅ Observable and Debuggable
- Web UIs for all major components
- Centralized logging via Docker Compose
- Health check endpoints

## Learnings and Benchmarks

### StarRocks: Native vs Iceberg Tables

**Finding**: Native tables significantly outperform Iceberg tables for real-time analytics.

| Metric | Native Tables | Iceberg Tables |
|--------|---------------|----------------|
| Query Latency | ⚡ Faster | Slower |
| Write Performance | ⚡ Faster | Slower |
| Multi-engine Support | ❌ StarRocks only | ✅ Flink, Spark, Trino |
| Time Travel | ❌ No | ✅ Yes |
| Schema Evolution | ⚠️ Limited | ✅ Non-breaking |

**Recommendation**:
- Use **native tables** for hot data and serving layer (real-time dashboards, APIs)
- Use **Iceberg tables** for cold data, archival, and multi-engine analytics

### CDC Pattern Comparison

| Feature | Flink CDC Direct | Debezium + Kafka |
|---------|------------------|------------------|
| End-to-end Latency | ~100-500ms | ~1-3 seconds |
| Multiple Consumers | ❌ | ✅ |
| Event Replay | ❌ | ✅ |
| Operational Complexity | Low | High |
| Resource Usage | Moderate | High |
| Exactly-Once | ✅ | ✅ |

### Ongoing Exploration

We're actively testing:
- **Concurrency**: How many parallel writers can each system handle?
- **Latency**: P50, P95, P99 latencies under various loads
- **Resource Usage**: CPU, memory, and disk I/O patterns

Contributions and benchmarks welcome!

## Makefile Targets

### Deployment

```bash
make up                  # Deploy all components
make full-flink-cdc      # Deploy Flink CDC full stack
make full-debezium       # Deploy Debezium full stack
make mysql               # Deploy only MySQL
make flink-cdc           # Deploy only Flink CDC pattern
make debezium            # Deploy only Debezium pattern
make iceberg             # Deploy only Iceberg + MinIO
make starrocks           # Deploy only StarRocks
```

### Monitoring

```bash
make status              # Show status of all services
make ps                  # List running containers
make logs                # Tail logs from all services
make urls                # Display all service URLs
```

### Teardown

```bash
make down                # Stop all (preserves data)
make down-clean          # Stop all and remove volumes
make down-mysql          # Stop only MySQL
make clean               # Clean up stopped containers
```

### Utilities

```bash
make help                # Show all available targets
make check               # Check prerequisites
```

## Service URLs

Once deployed, access the following UIs:

| Service | URL | Credentials |
|---------|-----|-------------|
| **Flink (CDC Direct)** | http://localhost:8082 | - |
| **Flink (Debezium)** | http://localhost:8081 | - |
| **Kafka UI** | http://localhost:8080 | - |
| **Debezium API** | http://localhost:8083 | - |
| **StarRocks Web UI** | http://localhost:8030 | - |
| **MinIO Console** | http://localhost:9001 | admin / password |
| **Iceberg REST Catalog** | http://localhost:8181 | - |

### Database Connections

```bash
# MySQL
mysql -h 127.0.0.1 -P 3306 -u${MYSQL_USER} -p

# StarRocks (MySQL protocol)
mysql -h 127.0.0.1 -P 9030 -uroot
```

## Environment Configuration

Configuration is managed via environment files in [env/](env/):

```bash
# MySQL credentials
MYSQL_ROOT_PASSWORD=rootpassword
MYSQL_USER=myuser
MYSQL_PASSWORD=mypassword
MYSQL_DATABASE=mydatabase

# MinIO (S3-compatible storage)
MINIO_ROOT_USER=admin
MINIO_ROOT_PASSWORD=password

# AWS credentials (for S3 access)
AWS_ACCESS_KEY_ID=admin
AWS_SECRET_ACCESS_KEY=password
AWS_REGION=us-east-1
```

**Security Note**: Never commit `env/common.env` with real credentials. Use `env/common.env.example` as a template.

## Troubleshooting

### Services Won't Start

```bash
# Check Docker is running
docker ps

# Check prerequisites
make check

# View logs for specific service
docker logs <container-name>
```

### Network Issues

```bash
# Recreate networks
make down
docker network prune
make infra
make up
```

### Performance Issues

See component-specific troubleshooting:
- [MySQL CDC Configuration](01-sources/mysql/README.md#troubleshooting)
- [Flink Performance Tuning](02-cdc-patterns/flink-cdc-direct/README.md#performance-tuning)
- [StarRocks Optimization](03-destinations/starrocks/README.md#performance-features)

## Contributing

Contributions are welcome! Areas of interest:

- Performance benchmarks and optimizations
- Additional CDC patterns (e.g., Debezium → Pulsar)
- Integration examples (Trino, Spark, dbt)
- Production deployment guides (Kubernetes, Terraform)

## Project Goals

This repository aims to:

1. **Educate**: Provide hands-on learning for streaming data architectures
2. **Compare**: Offer side-by-side comparisons of different patterns
3. **Accelerate**: Enable rapid prototyping of data pipelines
4. **Document**: Share real-world learnings and best practices

## License

This project is open source. See LICENSE for details.

## References

### Official Documentation
- [Apache Flink](https://flink.apache.org/)
- [Flink CDC Connectors](https://nightlies.apache.org/flink/flink-cdc-docs-master/)
- [Debezium](https://debezium.io/)
- [Apache Kafka](https://kafka.apache.org/)
- [Apache Iceberg](https://iceberg.apache.org/)
- [StarRocks](https://docs.starrocks.io/)
- [MinIO](https://min.io/docs/)

### Related Projects
- [Awesome Streaming](https://github.com/manuzhang/awesome-streaming)
- [Data Engineering Cookbook](https://github.com/andkret/Cookbook)

---

**Happy Streaming! 🚀**
