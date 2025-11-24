-- Example: Stream MySQL CDC to Iceberg table with upserts
-- This demonstrates real-time data lake ingestion

-- Create MySQL CDC source
CREATE TABLE mysql_users (
  id INT PRIMARY KEY NOT ENFORCED,
  name STRING,
  email STRING,
  phone STRING,
  created_at TIMESTAMP(3),
  updated_at TIMESTAMP(3)
) WITH (
  'connector' = 'mysql-cdc',
  'hostname' = 'mysql',
  'port' = '3306',
  'username' = 'myuser',
  'password' = 'mypassword',
  'database-name' = 'mydatabase',
  'table-name' = 'users',
  'server-time-zone' = 'UTC'
);

-- Configure Iceberg catalog
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

-- Switch to Iceberg catalog
USE CATALOG iceberg_catalog;

-- Create database
CREATE DATABASE IF NOT EXISTS cdc_data;

-- Create Iceberg table with upsert support
CREATE TABLE IF NOT EXISTS cdc_data.users (
  id INT,
  name STRING,
  email STRING,
  phone STRING,
  created_at TIMESTAMP(3),
  updated_at TIMESTAMP(3),
  PRIMARY KEY (id) NOT ENFORCED
) WITH (
  'format-version' = '2',
  'write.upsert.enabled' = 'true',
  'write.format.default' = 'parquet'
);

-- Stream CDC changes to Iceberg (upserts based on primary key)
INSERT INTO iceberg_catalog.cdc_data.users
SELECT
  id,
  name,
  email,
  phone,
  created_at,
  updated_at
FROM default_catalog.default_database.mysql_users;
