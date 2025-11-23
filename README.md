# Learnings

## Exploring Starrocks data storage
1. Native Tables in Starrocks is faster compared to Iceberg tables
2. Need to test with the intended usecase to check what is better approach in terms of
* concurrency
* latency
* CPU, Memory, and Disk usage


## Exploring CDC options from MySQL to Iceberg and Starrocks
1. Debezium/Kafka + Flink
2. Flink CDC