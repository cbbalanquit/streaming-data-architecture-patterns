.PHONY: help up down status clean logs

# Default target
help:
	@echo "Streaming Data Architecture Patterns - Makefile"
	@echo ""
	@echo "Common targets:"
	@echo "  make up                  - Deploy all components"
	@echo "  make down                - Stop all components"
	@echo "  make down-clean          - Stop all and remove volumes (deletes data!)"
	@echo "  make status              - Show status of all services"
	@echo "  make logs                - Tail logs from all services"
	@echo "  make clean               - Clean up stopped containers and networks"
	@echo ""
	@echo "Component-specific targets:"
	@echo "  make infra               - Deploy only networks"
	@echo "  make mysql               - Deploy MySQL source"
	@echo "  make flink-cdc           - Deploy Flink CDC Direct pattern"
	@echo "  make debezium            - Deploy Debezium+Kafka+Flink pattern"
	@echo "  make iceberg             - Deploy Iceberg+MinIO"
	@echo "  make starrocks           - Deploy StarRocks"
	@echo ""
	@echo "Full stack targets:"
	@echo "  make full-flink-cdc      - Deploy MySQL→Flink CDC→Iceberg+StarRocks"
	@echo "  make full-debezium       - Deploy MySQL→Debezium→Kafka→Flink→Iceberg+StarRocks"
	@echo ""
	@echo "Utility targets:"
	@echo "  make ps                  - List all running containers"
	@echo "  make urls                - Show all service URLs"
	@echo "  make check               - Check prerequisites"

# Deploy targets
up:
	@bash scripts/deploy.sh all

infra:
	@bash scripts/deploy.sh infra

mysql:
	@bash scripts/deploy.sh mysql

flink-cdc:
	@bash scripts/deploy.sh flink-cdc

debezium:
	@bash scripts/deploy.sh debezium

iceberg:
	@bash scripts/deploy.sh iceberg

starrocks:
	@bash scripts/deploy.sh starrocks

full-flink-cdc:
	@bash scripts/deploy.sh full-flink-cdc

full-debezium:
	@bash scripts/deploy.sh full-debezium

# Teardown targets
down:
	@bash scripts/teardown.sh all

down-clean:
	@bash scripts/teardown.sh all --volumes

down-mysql:
	@bash scripts/teardown.sh mysql

down-flink-cdc:
	@bash scripts/teardown.sh flink-cdc

down-debezium:
	@bash scripts/teardown.sh debezium

down-iceberg:
	@bash scripts/teardown.sh iceberg

down-starrocks:
	@bash scripts/teardown.sh starrocks

# Status and monitoring
status:
	@echo "=== Infrastructure ==="
	@docker network ls | grep -E "cdc_network|iceberg_net" 2>/dev/null || echo "Networks not created"
	@echo ""
	@echo "=== MySQL Source ==="
	@docker compose -f 01-sources/mysql/compose.yaml ps 2>/dev/null || echo "MySQL not running"
	@echo ""
	@echo "=== Flink CDC Direct ==="
	@docker compose -f 02-cdc-patterns/flink-cdc-direct/compose-flink-cdc.yaml ps 2>/dev/null || echo "Flink CDC not running"
	@echo ""
	@echo "=== Debezium+Kafka+Flink ==="
	@docker compose -f 02-cdc-patterns/debezium-kafka-flink/compose-debezium-kafka-flink.yaml ps 2>/dev/null || echo "Debezium stack not running"
	@echo ""
	@echo "=== Iceberg+MinIO ==="
	@docker compose -f 03-destinations/iceberg-minio/compose.yaml ps 2>/dev/null || echo "Iceberg not running"
	@echo ""
	@echo "=== StarRocks ==="
	@docker compose -f 03-destinations/starrocks/compose.yaml ps 2>/dev/null || echo "StarRocks not running"

ps:
	@docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

logs:
	@echo "Tailing logs from all services (Ctrl+C to stop)..."
	@docker compose -f 01-sources/mysql/compose.yaml \
		-f 02-cdc-patterns/flink-cdc-direct/compose-flink-cdc.yaml \
		-f 02-cdc-patterns/debezium-kafka-flink/compose-debezium-kafka-flink.yaml \
		-f 03-destinations/iceberg-minio/compose.yaml \
		-f 03-destinations/starrocks/compose.yaml \
		logs -f 2>/dev/null || echo "No services running"

# Utility targets
clean:
	@echo "Cleaning up stopped containers and unused networks..."
	@docker container prune -f
	@docker network prune -f
	@echo "Cleanup complete"

urls:
	@echo "Service URLs:"
	@echo "  - Flink (CDC Direct):     http://localhost:8082"
	@echo "  - Flink (Debezium):       http://localhost:8081"
	@echo "  - Kafka UI:               http://localhost:8080"
	@echo "  - Debezium API:           http://localhost:8083"
	@echo "  - StarRocks FE:           http://localhost:8030"
	@echo "  - MinIO Console:          http://localhost:9001"
	@echo "  - Iceberg REST Catalog:   http://localhost:8181"
	@echo ""
	@echo "Database connections:"
	@echo "  - MySQL:      mysql -h 127.0.0.1 -P 3306 -u\$${MYSQL_USER} -p"
	@echo "  - StarRocks:  mysql -h 127.0.0.1 -P 9030 -uroot"

check:
	@bash scripts/check_prereqs.sh

# Backup management (legacy support)
backup-list:
	@echo "Versioned backup files:"
	@find . -name '*.v[0-9]*.yaml' -type f 2>/dev/null || echo "No backups found"
