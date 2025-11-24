-- Example: Stream MySQL CDC to StarRocks native table
-- StarRocks Primary Key table supports real-time upserts

-- Create MySQL CDC source
CREATE TABLE mysql_orders (
  order_id INT PRIMARY KEY NOT ENFORCED,
  customer_id INT,
  product_id INT,
  amount DECIMAL(10, 2),
  status STRING,
  order_date TIMESTAMP(3),
  updated_at TIMESTAMP(3)
) WITH (
  'connector' = 'mysql-cdc',
  'hostname' = 'mysql',
  'port' = '3306',
  'username' = 'myuser',
  'password' = 'mypassword',
  'database-name' = 'mydatabase',
  'table-name' = 'orders',
  'server-time-zone' = 'UTC'
);

-- Create StarRocks sink table
CREATE TABLE starrocks_orders (
  order_id INT,
  customer_id INT,
  product_id INT,
  amount DECIMAL(10, 2),
  status STRING,
  order_date TIMESTAMP(3),
  updated_at TIMESTAMP(3),
  PRIMARY KEY (order_id) NOT ENFORCED
) WITH (
  'connector' = 'jdbc',
  'url' = 'jdbc:mysql://starrocks-fe:9030/analytics',
  'table-name' = 'orders',
  'username' = 'root',
  'password' = '',
  'sink.buffer-flush.max-rows' = '1000',
  'sink.buffer-flush.interval' = '1s',
  'sink.max-retries' = '3'
);

-- Note: Before running, create the table in StarRocks:
--
-- CREATE DATABASE IF NOT EXISTS analytics;
-- USE analytics;
--
-- CREATE TABLE orders (
--   order_id INT NOT NULL,
--   customer_id INT,
--   product_id INT,
--   amount DECIMAL(10, 2),
--   status VARCHAR(50),
--   order_date DATETIME,
--   updated_at DATETIME
-- ) PRIMARY KEY (order_id)
-- DISTRIBUTED BY HASH(order_id) BUCKETS 10;

-- Stream CDC to StarRocks
INSERT INTO starrocks_orders
SELECT
  order_id,
  customer_id,
  product_id,
  amount,
  status,
  order_date,
  updated_at
FROM mysql_orders;
