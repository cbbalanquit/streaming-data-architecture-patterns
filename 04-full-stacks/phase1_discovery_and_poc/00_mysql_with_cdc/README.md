# MySQL with Change Data Capture (CDC) - Phase 1 Exploration

## Overview

This is the first phase of exploring streaming data architecture patterns, starting with **MySQL as the source** and learning two different approaches to **Change Data Capture (CDC)**. This POC serves as a foundation for building a complete streaming pipeline from MySQL to analytical destinations like Iceberg and StarRocks.

### Learning Goals

1. Understand how MySQL binary logs enable CDC
2. Compare two CDC patterns: direct vs. buffered streaming
3. Build hands-on experience with Flink stream processing
4. Establish a foundation for end-to-end streaming pipelines

## Quick Start

### Option 1: One-Command Setup (Easiest)

```bash
# Setup 1: Flink CDC Direct (everything in one command)
make phase1-setup1

# OR Setup 2: Debezium + Kafka + Flink (everything in one command)
make phase1-setup2

# Create test data
make phase1-test

# When done exploring
make phase1-down
```

### Option 2: Step-by-Step Setup

```bash
# 1. Setup infrastructure and MySQL
make infra
make mysql

# 2. Choose your CDC setup:

# Option A: Direct streaming with Flink CDC (low latency)
make flink-cdc

# Option B: Buffered streaming with Debezium + Kafka (flexible)
make debezium

# 3. Check status
make status

# 4. View service URLs
make urls
```

### Option 3: Using Docker Compose Directly

See the detailed instructions in each setup section below.

## Architecture Comparison

This exploration covers two distinct CDC architectures:

### Setup 1: Direct Streaming (Flink CDC Connector)
```
MySQL (Binary Log)
    ↓
Flink CDC Connector
    ↓
Flink Stream Processing
    ↓
Destinations (Iceberg, StarRocks, Console)
```

**Characteristics:**
- **Low latency**: ~100-500ms end-to-end
- **Simple architecture**: Fewer moving parts
- **Point-to-point**: Single consumer per CDC stream
- **Lower resource usage**: No intermediate broker

### Setup 2: Buffered Streaming (Debezium + Kafka + Flink)
```
MySQL (Binary Log)
    ↓
Debezium Connector
    ↓
Kafka Topics
    ↓
Flink Kafka Connector
    ↓
Flink Stream Processing
    ↓
Destinations (Iceberg, StarRocks, Console)
```

**Characteristics:**
- **Higher latency**: ~1-3 seconds end-to-end
- **Complex architecture**: More components to manage
- **Event replay**: Kafka provides historical event buffering
- **Multiple consumers**: Kafka enables fan-out to many consumers

## Components

### Common Components (Both Setups)

#### MySQL
- **Role**: Source database with binary logging enabled
- **CDC Method**: Binary log (binlog) replication
- **Required Config**:
  - `log_bin = ON`
  - `binlog_format = ROW`
  - User with REPLICATION permissions

#### Flink Cluster
- **JobManager**: Coordinates stream processing jobs
- **TaskManager**: Executes data processing tasks
- **SQL Client**: Interactive interface for SQL-based job submission

### Setup 1 Specific Components

#### Flink CDC Connector
- **Type**: Source connector built into Flink
- **Method**: Direct MySQL binlog reading
- **JAR**: `flink-sql-connector-mysql-cdc-3.5.0.jar`

### Setup 2 Specific Components

#### Debezium Connect
- **Port**: 8083
- **Role**: Captures MySQL changes via binlog and publishes to Kafka
- **API**: REST API for connector management
- **Version**: Debezium 3.0

#### Apache Kafka
- **Ports**: 9092 (client), 9093 (controller)
- **Mode**: KRaft (no Zookeeper)
- **Role**: Event streaming platform for CDC events
- **Version**: 4.1.1

#### Kafka UI
- **Port**: 8080
- **URL**: http://localhost:8080
- **Role**: Web interface for monitoring topics and messages

## Prerequisites

Before starting either setup, ensure the following are running:

### 0. Configure Environment Variables

Ensure your [env/common.env](../../../env/common.env) file has the correct MySQL credentials:

```env
MYSQL_ROOT_PASSWORD=rootpassword
MYSQL_USER=appuser
MYSQL_PASSWORD=apppassword
MYSQL_DATABASE=active
```

### 1. Create Docker Networks
```bash
make infra
```

Or using docker compose directly:
```bash
docker compose -f infra/networks.yaml up -d
```

### 2. Start MySQL Source
```bash
make mysql
```

Or using docker compose directly:
```bash
docker compose -f 01-sources/mysql/compose.yaml --env-file env/common.env up -d
```

### 3. Verify MySQL Setup

Check that MySQL is running with binary logging enabled:
```bash
docker exec -it mysql mysql -uroot -p${MYSQL_ROOT_PASSWORD} \
  -e "SHOW VARIABLES LIKE 'log_bin';"
```

Expected output: `log_bin = ON`

## Setup 1: Direct Streaming with Flink CDC Connector

### Why Use This Setup?

✅ **Choose this when:**
- You need low-latency streaming (<1 second)
- Your use case is point-to-point (single consumer)
- You want minimal operational complexity
- Resource efficiency is important

❌ **Avoid this when:**
- Multiple consumers need the same CDC stream
- You need event replay capabilities
- Producer-consumer decoupling is required

### Architecture Details

This setup uses Flink's native MySQL CDC connector to directly read from MySQL binary logs without any intermediate message broker. The connector tracks binlog position and provides exactly-once semantics through Flink's checkpointing mechanism.

### Required JARs

The required JARs should already be in [02-cdc-patterns/flink-cdc-direct/lib/](../../02-cdc-patterns/flink-cdc-direct/lib/). If not, download them:

```bash
cd 02-cdc-patterns/flink-cdc-direct/lib

# Flink MySQL CDC Connector
wget https://repo1.maven.org/maven2/org/apache/flink/flink-sql-connector-mysql-cdc/3.5.0/flink-sql-connector-mysql-cdc-3.5.0.jar

# Iceberg Flink Runtime (for Iceberg destinations)
wget https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-flink-runtime-1.16/1.3.1/iceberg-flink-runtime-1.16-1.3.1.jar

# Hadoop Dependencies (for Iceberg)
wget https://repo.maven.apache.org/maven2/org/apache/flink/flink-shaded-hadoop-2-uber/2.7.5-10.0/flink-shaded-hadoop-2-uber-2.7.5-10.0.jar
```

### Start Setup 1

Using Makefile (recommended):
```bash
make flink-cdc
```

Or using docker compose directly:
```bash
docker compose -f 02-cdc-patterns/flink-cdc-direct/compose-flink-cdc.yaml \
  --env-file env/common.env up -d
```

### Verify Services

```bash
# Check all containers are running
make status

# Or check just this setup
docker compose -f 02-cdc-patterns/flink-cdc-direct/compose-flink-cdc.yaml ps

# Access Flink Web UI
open http://localhost:8082

# Connect to Flink SQL Client
docker exec -it flink-sql-client /opt/flink/bin/sql-client.sh
```

### Example: Stream MySQL to Console

```sql
-- Create CDC source table for tenants
CREATE TABLE tenants (
  id INT PRIMARY KEY NOT ENFORCED,
  name STRING,
  street_number STRING,
  street_name STRING,
  suburb STRING,
  state STRING,
  postcode STRING,
  created_at TIMESTAMP(3),
  updated_at TIMESTAMP(3),
  country_id INT,
  timezone STRING
) WITH (
  'connector' = 'mysql-cdc',
  'hostname' = 'mysql',
  'port' = '3306',
  'username' = 'root',
  'password' = 'rootpassword',
  'database-name' = 'active',
  'table-name' = 'tenants',
  'server-time-zone' = 'UTC'
);

-- Stream changes to console
SELECT * FROM tenants;

-- Or query specific columns
SELECT id, name, suburb, state, timezone FROM tenants;
```

#### Example 2: Stream member_scans (Body Composition Data)

```sql
-- Create CDC source table for member_scans (all 228 columns)
CREATE TABLE member_scans (
  id BIGINT PRIMARY KEY NOT ENFORCED,
  member_id BIGINT,
  location_id INT,
  device_id INT,
  operator_id INT,
  IsKgLb INT,
  Kiko_fatXY_ext INT,
  VSR_low_limit INT,
  VSR_max_limit INT,
  VSR_min_limit INT,
  VSR_top_limit INT,
  age INT,
  bca_main_set STRING,
  bcm INT,
  bcm_low INT,
  bcm_top INT,
  beauty_weight INT,
  bmi INT,
  bmi_low_limit INT,
  bmi_max_limit INT,
  bmi_min_limit INT,
  bmi_top_limit INT,
  bmr INT,
  bmr_mode INT,
  body_age INT,
  bone_slim INT,
  bone_slim_low INT,
  bone_slim_max INT,
  bone_slim_min INT,
  bone_slim_top INT,
  bujong_judge INT,
  bujong_judge_low INT,
  bujong_judge_top INT,
  calory INT,
  control_guide_for_me INT,
  dex_mode INT,
  dias INT,
  dias_se INT,
  ecf INT,
  ecw_low INT,
  ecw_top INT,
  edema INT,
  fat STRING,
  fat_type INT,
  fat_xy INT,
  height INT,
  height_for_kiko INT,
  icf INT,
  icw_low INT,
  icw_top INT,
  id_number INT,
  impedance INT,
  kiko_kids_state_ext INT,
  lbm_control_value STRING,
  lbm_foot_low INT,
  lbm_foot_max INT,
  lbm_foot_min INT,
  lbm_foot_top INT,
  lbm_hand_low INT,
  lbm_hand_max INT,
  lbm_hand_min INT,
  lbm_hand_top INT,
  lbm_low_limit INT,
  lbm_max_limit INT,
  lbm_min_limit INT,
  lbm_quantity INT,
  lbm_top_limit INT,
  lbm_trunk_low INT,
  lbm_trunk_max INT,
  lbm_trunk_min INT,
  lbm_trunk_top INT,
  left_foot_edema_ecw INT,
  left_foot_impedance_250k INT,
  left_foot_impedance_50k INT,
  left_foot_impedance_550k INT,
  left_foot_impedance_5k INT,
  left_foot_lbm INT,
  left_foot_mbf INT,
  left_foot_muscle INT,
  left_hand_bmf INT,
  left_hand_edema_ecw INT,
  left_hand_impedance_250k INT,
  left_hand_impedance_50k INT,
  left_hand_impedance_550k INT,
  left_hand_impedance_5k INT,
  left_hand_lbm INT,
  left_hand_muscle INT,
  lowerbody_balance_low INT,
  lowerbody_balance_std INT,
  lowerbody_balance_top INT,
  mbf_control_step INT,
  mbf_control_value INT,
  mbf_grade_i INT,
  mbf_low_limit INT,
  mbf_max_limit INT,
  mbf_min_limit INT,
  mbf_quantity INT,
  mbf_standard INT,
  mbf_top_limit INT,
  mean INT,
  mean_se INT,
  mineral_grade INT,
  mineral_low_limit INT,
  mineral_quantity INT,
  mineral_top_limit INT,
  mode STRING,
  msf_quantity INT,
  muscle_control_value STRING,
  muscle_grade_i INT,
  muscle_grade_ii INT,
  muscle_low_limit INT,
  muscle_max_limit INT,
  muscle_min_limit INT,
  muscle_quantity INT,
  muscle_standard INT,
  muscle_top_limit INT,
  mvf_quantity INT,
  part_foot_muscle_low INT,
  part_foot_muscle_top INT,
  part_hand_muscle_low INT,
  part_hand_muscle_top INT,
  part_left_foot_mbf_percent INT,
  part_left_hand_mbf_percent INT,
  part_right_foot_mbf_low INT,
  part_right_foot_mbf_percent INT,
  part_right_foot_mbf_top INT,
  part_right_hand_mbf_low INT,
  part_right_hand_mbf_percent INT,
  part_right_hand_mbf_top INT,
  part_trunk_mbf_low INT,
  part_trunk_mbf_percent INT,
  part_trunk_mbf_top INT,
  part_trunk_muscle_low INT,
  part_trunk_muscle_top INT,
  pbf_low_limit INT,
  pbf_max_limit INT,
  pbf_min_limit INT,
  pbf_rate INT,
  pbf_top_limit INT,
  practical_bodyfat_top INT,
  practical_bodyfat_under INT,
  practical_mineral_top INT,
  practical_mineral_under INT,
  practical_protein_top INT,
  practical_protein_under INT,
  practical_tbw_top INT,
  practical_tbw_under INT,
  protein_grade INT,
  protein_low_limit INT,
  protein_quantity INT,
  protein_top_limit INT,
  protocol_command STRING,
  prp STRING,
  pulse INT,
  received_date INT,
  right_foot_edema_ecw INT,
  right_foot_impedance_250k INT,
  right_foot_impedance_50k INT,
  right_foot_impedance_550k INT,
  right_foot_impedance_5k INT,
  right_foot_lbm INT,
  right_foot_mbf INT,
  right_foot_muscle INT,
  right_hand_edema_ecw INT,
  right_hand_impedance_50k INT,
  right_hand_impedance_550k INT,
  right_hand_impedance_250k INT,
  right_hand_impedance_5k INT,
  right_hand_lbm INT,
  right_hand_mbf INT,
  right_hand_muscle INT,
  sex INT,
  slm_graph_percent INT,
  std_weight INT,
  sys INT,
  sys_se INT,
  target_to_control STRING,
  tbw_low_limit INT,
  tbw_max_limit INT,
  tbw_min_limit INT,
  tbw_quantity INT,
  tbw_top_limit INT,
  total_score INT,
  trunk_ecw INT,
  trunk_impedance_250k INT,
  trunk_impedance_50k INT,
  trunk_impedance_550k INT,
  trunk_impedance_5k INT,
  trunk_lbm INT,
  trunk_mbf INT,
  trunk_muscle INT,
  upperbody_balance_low INT,
  upperbody_balance_std INT,
  upperbody_balance_top INT,
  vfa INT,
  vfa_low INT,
  vfa_max INT,
  vfa_min INT,
  vfa_top INT,
  vsr INT,
  waist_measurement INT,
  week_time_for_calory INT,
  weight INT,
  weight_control_value STRING,
  weight_for_kiko INT,
  weight_low_limit INT,
  weight_max_limit INT,
  weight_min_limit INT,
  weight_top_limit INT,
  whr_level INT,
  whr_low INT,
  whr_max INT,
  whr_min INT,
  whr_rate INT,
  whr_top INT,
  whr_type INT,
  created_at TIMESTAMP(3),
  updated_at TIMESTAMP(3),
  utc_created STRING,
  transaction STRING,
  enabled BOOLEAN,
  scan_template STRING,
  tz_created STRING,
  macro_goal STRING,
  macro_bodytype STRING,
  macro_activitylevel STRING,
  macro_activitytype STRING,
  macro_fatloss STRING
) WITH (
  'connector' = 'mysql-cdc',
  'hostname' = 'mysql',
  'port' = '3306',
  'username' = 'root',
  'password' = 'rootpassword',
  'database-name' = 'export',
  'table-name' = 'member_scans',
  'server-time-zone' = 'UTC',
  'scan.incremental.snapshot.enabled' = 'true'
);

-- Stream all changes to console
SELECT * FROM member_scans;

-- Or query key metrics only
SELECT
  id,
  member_id,
  location_id,
  weight,
  height,
  bmi,
  pbf_rate as body_fat_pct,
  muscle_quantity,
  created_at
FROM member_scans
WHERE enabled = true;
```

### More Examples

Pre-built SQL jobs are available in [02-cdc-patterns/flink-cdc-direct/jobs/](../../02-cdc-patterns/flink-cdc-direct/jobs/):
- [cdc-to-console.sql](../../02-cdc-patterns/flink-cdc-direct/jobs/cdc-to-console.sql) - Basic CDC streaming
- [cdc-to-iceberg.sql](../../02-cdc-patterns/flink-cdc-direct/jobs/cdc-to-iceberg.sql) - Write to Iceberg table
- [cdc-to-starrocks.sql](../../02-cdc-patterns/flink-cdc-direct/jobs/cdc-to-starrocks.sql) - Write to StarRocks

### Full Documentation

For detailed documentation, troubleshooting, and advanced configurations, see:
[02-cdc-patterns/flink-cdc-direct/README.md](../../02-cdc-patterns/flink-cdc-direct/README.md)

---

## Setup 2: Buffered Streaming with Debezium + Kafka + Flink

### Why Use This Setup?

✅ **Choose this when:**
- Multiple consumers need to process the same CDC events
- You need event replay from historical data
- Producer-consumer decoupling is important
- Complex stream joins and routing are required

❌ **Avoid this when:**
- Low latency (<1 second) is critical
- Simple point-to-point streaming is sufficient
- Infrastructure complexity is a concern
- You have strict resource constraints

### Architecture Details

This setup uses Debezium to capture MySQL changes and publish them to Kafka topics. Flink then consumes from Kafka topics for stream processing. This architecture provides buffering, replay capabilities, and enables multiple independent consumers.

### Start Setup 2

Using Makefile (recommended):
```bash
make debezium
```

Or using docker compose directly:
```bash
docker compose -f 02-cdc-patterns/debezium-kafka-flink/compose-debezium-kafka-flink.yaml \
  --env-file env/common.env up -d
```

### Verify Services

```bash
# Check all containers are healthy
make status

# Or check just this setup
docker compose -f 02-cdc-patterns/debezium-kafka-flink/compose-debezium-kafka-flink.yaml ps

# Check Kafka is ready
docker exec -it kafka kafka-broker-api-versions.sh --bootstrap-server localhost:9092

# Access Kafka UI
open http://localhost:8080

# Access Flink UI
open http://localhost:8081
```

### Configure Debezium Connector

Register the MySQL CDC connector with Debezium:

```bash
curl -i -X POST -H "Accept:application/json" -H "Content-Type:application/json" \
  http://localhost:8083/connectors/ \
  -d @02-cdc-patterns/debezium-kafka-flink/connectors/mysql-connector.json
```

**Note:** Make sure the connector configuration includes the `active` database. Update the `mysql-connector.json` to include:
```json
{
  "name": "mysql-connector",
  "config": {
    "table.include.list": "active.tenants",
    "database.include.list": "active"
  }
}
```

Verify connector is running:
```bash
curl http://localhost:8083/connectors/mysql-connector/status
```

### View CDC Events in Kafka

```bash
# List all topics (you should see mysql.active.* topics)
docker exec -it kafka kafka-topics.sh --bootstrap-server localhost:9092 --list

# Consume CDC messages from the tenants table
docker exec -it kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic mysql.active.tenants \
  --from-beginning
```

### Example: Stream Kafka CDC to Console

Connect to Flink SQL Client:
```bash
docker exec -it flink-jobmanager /opt/flink/bin/sql-client.sh
```

Create Flink table reading from Kafka:
```sql
-- Create Kafka source table for tenants
CREATE TABLE tenants (
  id INT,
  name STRING,
  street_number STRING,
  street_name STRING,
  suburb STRING,
  state STRING,
  postcode STRING,
  created_at TIMESTAMP(3),
  updated_at TIMESTAMP(3),
  country_id INT,
  timezone STRING,
  WATERMARK FOR created_at AS created_at - INTERVAL '5' SECOND
) WITH (
  'connector' = 'kafka',
  'topic' = 'mysql.active.tenants',
  'properties.bootstrap.servers' = 'kafka:29092',
  'properties.group.id' = 'flink-consumer',
  'scan.startup.mode' = 'earliest-offset',
  'format' = 'debezium-json'
);

-- Query the stream
SELECT * FROM tenants;

-- Or query specific columns with filtering
SELECT id, name, suburb, state, timezone
FROM tenants
WHERE state IN ('NSW', 'VIC', 'QLD');
```

### More Examples

Pre-built examples are available in [02-cdc-patterns/debezium-kafka-flink/jobs/](../../02-cdc-patterns/debezium-kafka-flink/jobs/)

### Full Documentation

For detailed documentation, troubleshooting, and advanced configurations, see:
[02-cdc-patterns/debezium-kafka-flink/README.md](../../02-cdc-patterns/debezium-kafka-flink/README.md)

---

## Side-by-Side Comparison

| Aspect | Setup 1: Flink CDC Direct | Setup 2: Debezium + Kafka + Flink |
|--------|----------------------------|-------------------------------------|
| **Latency** | ~100-500ms | ~1-3 seconds |
| **Architecture Complexity** | Low (3 components) | High (5+ components) |
| **Resource Usage** | Low | High (Kafka needs memory) |
| **Multiple Consumers** | ❌ Requires job duplication | ✅ Native support via Kafka |
| **Event Replay** | ❌ No historical replay | ✅ Kafka retention |
| **Operational Overhead** | Lower | Higher |
| **Use Case** | Point-to-point streaming | Event-driven architecture |
| **Exactly-Once Semantics** | ✅ Flink native | ✅ Flink + Kafka transactions |
| **Best For** | Low-latency pipelines | Complex multi-consumer systems |

## Testing Both Setups

### Create Test Data in MySQL

**Option 1: Using Makefile (Quick)**
```bash
make phase1-test
```

This will insert test data into the existing `tenants` table (the table is created automatically when MySQL starts from the compose setup).

**Option 2: Manual Setup**

Connect to MySQL (the `tenants` table already exists from the MySQL compose setup):
```bash
docker exec -it mysql mysql -uappuser -papppassword active
```

Then run:
```sql
-- Insert test data
INSERT INTO tenants (name, street_number, street_name, suburb, state, postcode, country_id, timezone) VALUES
  ('Acme Corp', '123', 'Main Street', 'Sydney', 'NSW', '2000', 1, 'Australia/Sydney'),
  ('Tech Solutions', '456', 'Elizabeth Street', 'Melbourne', 'VIC', '3000', 1, 'Australia/Melbourne'),
  ('Data Analytics Ltd', '789', 'Queen Street', 'Brisbane', 'QLD', '4000', 1, 'Australia/Brisbane');

-- View inserted data
SELECT * FROM tenants ORDER BY id DESC LIMIT 3;

-- Update a record (triggers CDC)
UPDATE tenants SET suburb = 'Surry Hills', postcode = '2010' WHERE name = 'Acme Corp';

-- Insert another record (triggers CDC)
INSERT INTO tenants (name, street_number, street_name, suburb, state, postcode, country_id, timezone)
VALUES ('Global Services', '321', 'George Street', 'Perth', 'WA', '6000', 1, 'Australia/Perth');

-- Delete a record (triggers CDC)
DELETE FROM tenants WHERE name = 'Data Analytics Ltd';
```

**Note:** The `tenants` table schema is:
```sql
-- Schema (already created in MySQL)
CREATE TABLE tenants (
  id INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  name VARCHAR(255) NOT NULL,
  street_number VARCHAR(255) NOT NULL,
  street_name VARCHAR(255) NOT NULL,
  suburb VARCHAR(255) NOT NULL,
  state VARCHAR(255) NOT NULL,
  postcode VARCHAR(255) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT '0000-00-00 00:00:00',
  country_id INT NOT NULL DEFAULT 0,
  timezone VARCHAR(255) DEFAULT 'UTC',
  INDEX idx_name (name)
);
```

### Observe CDC Events

**Setup 1 (Flink CDC):**

1. **Via Flink SQL Client** (Real-time streaming):
   ```bash
   # Connect to Flink SQL Client
   docker exec -it flink-sql-client /opt/flink/bin/sql-client.sh
   ```

   Then run the CDC query:
   ```sql
   -- Create the CDC source table
   CREATE TABLE tenants (
     id INT PRIMARY KEY NOT ENFORCED,
     name STRING,
     street_number STRING,
     street_name STRING,
     suburb STRING,
     state STRING,
     postcode STRING,
     created_at TIMESTAMP(3),
     updated_at TIMESTAMP(3),
     country_id INT,
     timezone STRING
   ) WITH (
     'connector' = 'mysql-cdc',
     'hostname' = 'mysql',
     'port' = '3306',
     'username' = 'root',
     'password' = 'rootpassword',
     'database-name' = 'active',
     'table-name' = 'tenants',
     'server-time-zone' = 'UTC'
   );

   -- Stream changes in real-time (this will block and show new changes as they happen)
   SELECT id, name, suburb, state FROM tenants;
   ```

   Now in another terminal, insert/update/delete data in MySQL and you'll see the changes appear in Flink!

2. **Via Flink Web UI** (http://localhost:8082):
   - Go to "Running Jobs" to see active CDC streaming jobs
   - Click on a job to see:
     - **Records Sent**: Number of CDC events processed
     - **Bytes Sent**: Volume of data processed
     - **Records Received**: Events consumed from MySQL
   - Check the "Task Metrics" tab for detailed metrics per operator

3. **Via Flink JobManager Logs**:
   ```bash
   docker logs -f flink-jobmanager
   ```

**Setup 2 (Debezium + Kafka):**

1. **Via Kafka UI** (http://localhost:8080):
   - Navigate to "Topics" → `mysql.active.tenants`
   - View the message count increasing as CDC events arrive
   - Click "Messages" to see the actual CDC event payloads
   - Each message shows the before/after state of records

2. **Via Kafka Console Consumer**:
   ```bash
   # Watch CDC events in real-time
   docker exec -it kafka kafka-console-consumer.sh \
     --bootstrap-server localhost:9092 \
     --topic mysql.active.tenants \
     --from-beginning
   ```

3. **Via Flink SQL Client** (after creating Kafka source table):
   ```bash
   docker exec -it flink-jobmanager /opt/flink/bin/sql-client.sh
   ```

   ```sql
   -- Create Kafka source table
   CREATE TABLE tenants (
     id INT,
     name STRING,
     street_number STRING,
     street_name STRING,
     suburb STRING,
     state STRING,
     postcode STRING,
     created_at TIMESTAMP(3),
     updated_at TIMESTAMP(3),
     country_id INT,
     timezone STRING,
     WATERMARK FOR created_at AS created_at - INTERVAL '5' SECOND
   ) WITH (
     'connector' = 'kafka',
     'topic' = 'mysql.active.tenants',
     'properties.bootstrap.servers' = 'kafka:29092',
     'properties.group.id' = 'flink-consumer',
     'scan.startup.mode' = 'earliest-offset',
     'format' = 'debezium-json'
   );

   -- Query the stream
   SELECT id, name, suburb, state FROM tenants;
   ```

4. **Via Flink Web UI** (http://localhost:8081):
   - Similar to Setup 1, but check metrics for Kafka consumer lag
   - Look for "records-lag-max" in metrics to ensure Flink is keeping up

5. **Via Debezium Connector Status**:
   ```bash
   # Check connector health and stats
   curl http://localhost:8083/connectors/mysql-connector/status | jq
   ```

### End-to-End Test Flow

Here's a complete workflow to see CDC in action:

**Terminal 1 - Start Flink SQL Client with CDC query:**
```bash
docker exec -it flink-sql-client /opt/flink/bin/sql-client.sh

# Then paste the CREATE TABLE and SELECT statements from above
```

**Terminal 2 - Make changes in MySQL:**
```bash
docker exec -it mysql mysql -uappuser -papppassword active

# In MySQL shell:
INSERT INTO tenants (name, street_number, street_name, suburb, state, postcode, country_id, timezone)
VALUES ('Test Company', '100', 'Test St', 'Sydney', 'NSW', '2000', 1, 'Australia/Sydney');

UPDATE tenants SET suburb = 'Parramatta' WHERE name = 'Test Company';

DELETE FROM tenants WHERE name = 'Test Company';
```

**Terminal 1 - Observe changes:**
You'll see each INSERT, UPDATE, and DELETE appear in real-time in the Flink SQL Client!

### Understanding CDC Event Types

Flink CDC shows different operations:
- **+I** (Insert): New record added
- **-U** (Update Before): Old version of updated record
- **+U** (Update After): New version of updated record
- **-D** (Delete): Record deleted

Example output:
```
+I[101, Test Company, Sydney, NSW]           <- INSERT
-U[101, Test Company, Sydney, NSW]           <- UPDATE (before)
+U[101, Test Company, Parramatta, NSW]       <- UPDATE (after)
-D[101, Test Company, Parramatta, NSW]       <- DELETE
```

## Key Learnings

### 1. MySQL Binary Log is Essential
Both setups rely on MySQL's binary log for CDC. Understanding binlog configuration is critical for production deployments.

### 2. Trade-offs Between Latency and Flexibility
- **Setup 1** excels at low latency but lacks replay capabilities
- **Setup 2** provides flexibility and decoupling at the cost of latency

### 3. Flink as the Processing Engine
Both setups use Flink for stream processing, highlighting its versatility in consuming from different sources (direct MySQL vs. Kafka).

### 4. Operational Complexity
- **Setup 1** is easier to operate but harder to scale to multiple consumers
- **Setup 2** requires managing Kafka cluster but provides better scalability

## Makefile Reference

The project includes a comprehensive Makefile for easier management. Here are the key commands:

### Phase 1 Specific Commands (Recommended)
```bash
make phase1-setup1     # Deploy Setup 1 (infra + MySQL + Flink CDC) - all-in-one
make phase1-setup2     # Deploy Setup 2 (infra + MySQL + Debezium + Kafka + Flink) - all-in-one
make phase1-test       # Create test data in MySQL
make phase1-down       # Stop all Phase 1 components
```

### Individual Setup Commands
```bash
make infra         # Create Docker networks
make mysql         # Start MySQL source
make flink-cdc     # Start Setup 1 (Flink CDC Direct)
make debezium      # Start Setup 2 (Debezium + Kafka + Flink)
```

### Teardown Commands
```bash
make down-flink-cdc    # Stop Setup 1
make down-debezium     # Stop Setup 2
make down-mysql        # Stop MySQL
make down              # Stop all services
make down-clean        # Stop all and remove volumes (deletes data!)
```

### Monitoring Commands
```bash
make status        # Show status of all services
make ps            # List all running containers
make logs          # Tail logs from all services
make urls          # Show all service URLs
```

### Utility Commands
```bash
make check         # Check prerequisites (Docker, Docker Compose)
make clean         # Clean up stopped containers and networks
```

## Troubleshooting

### MySQL Binary Log Not Enabled

```bash
docker exec -it mysql mysql -uroot -p${MYSQL_ROOT_PASSWORD} \
  -e "SHOW VARIABLES LIKE 'log_bin';"
```

If `log_bin = OFF`, check your MySQL configuration.

### Flink Cannot Connect to MySQL

```bash
# Test network connectivity
docker exec -it flink-sql-client ping mysql

# Verify MySQL is on the cdc_network
docker network inspect cdc_network
```

### Debezium Connector Not Starting (Setup 2)

```bash
# Check connector status
curl http://localhost:8083/connectors/mysql-connector/status | jq

# View Debezium logs
docker logs debezium
```

## Next Steps

After exploring both CDC setups, the next phases include:

1. **Phase 2: Add Destinations**
   - Stream to Iceberg tables for analytics
   - Stream to StarRocks for real-time queries

2. **Phase 3: End-to-End Pipeline**
   - Combine CDC with transformations
   - Build complete MySQL → Processing → Analytics pipeline

3. **Phase 4: Production Considerations**
   - Schema evolution handling
   - Backpressure management
   - Monitoring and alerting

## References

### MySQL CDC Concepts
- [MySQL Binary Log](https://dev.mysql.com/doc/refman/8.0/en/binary-log.html)
- [Binlog Event Types](https://dev.mysql.com/doc/internals/en/binlog-event-type.html)

### Flink CDC
- [Flink CDC Connectors](https://nightlies.apache.org/flink/flink-cdc-docs-master/)
- [MySQL CDC Connector](https://nightlies.apache.org/flink/flink-cdc-docs-master/docs/connectors/flink-sources/mysql-cdc/)

### Debezium
- [Debezium MySQL Connector](https://debezium.io/documentation/reference/stable/connectors/mysql.html)
- [Debezium Architecture](https://debezium.io/documentation/reference/stable/architecture.html)

### Apache Flink
- [Flink SQL Client](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sqlclient/)
- [Flink Kafka Connector](https://nightlies.apache.org/flink/flink-docs-stable/docs/connectors/datastream/kafka/)

### Apache Kafka
- [Kafka Documentation](https://kafka.apache.org/documentation/)
- [KRaft Mode](https://kafka.apache.org/documentation/#kraft)
