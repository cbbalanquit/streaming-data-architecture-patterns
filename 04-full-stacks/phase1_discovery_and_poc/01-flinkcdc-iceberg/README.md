### Individual Setup Commands
```bash
make infra         # Create Docker networks
make mysql         # Start MySQL source
make flink-cdc     # Start Setup 1 (Flink CDC Direct)
make debezium      # Start Setup 2 (Debezium + Kafka + Flink)
```