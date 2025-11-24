-- Example Flink SQL Job: Stream CDC events to console
-- This demonstrates reading from Kafka topics created by Debezium

-- Create Kafka source table reading Debezium CDC events
CREATE TABLE mysql_users_cdc (
  id INT,
  name STRING,
  email STRING,
  created_at TIMESTAMP(3),
  updated_at TIMESTAMP(3),
  -- Debezium metadata fields
  PRIMARY KEY (id) NOT ENFORCED
) WITH (
  'connector' = 'kafka',
  'topic' = 'mysql.mydatabase.users',
  'properties.bootstrap.servers' = 'kafka:9092',
  'properties.group.id' = 'flink-cdc-console',
  'scan.startup.mode' = 'earliest-offset',
  'format' = 'debezium-json'
);

-- Simple SELECT to print all changes
SELECT
  id,
  name,
  email,
  created_at,
  updated_at
FROM mysql_users_cdc;

-- More advanced: Count changes by hour
-- CREATE VIEW hourly_changes AS
-- SELECT
--   TUMBLE_START(created_at, INTERVAL '1' HOUR) as window_start,
--   COUNT(*) as change_count
-- FROM mysql_users_cdc
-- GROUP BY TUMBLE(created_at, INTERVAL '1' HOUR);
