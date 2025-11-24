-- Example: Stream MySQL CDC changes to console
-- This is the simplest example for testing CDC connectivity

CREATE TABLE users_cdc (
  id INT PRIMARY KEY NOT ENFORCED,
  name STRING,
  email STRING,
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
  'server-time-zone' = 'UTC',
  'scan.startup.mode' = 'initial'  -- Options: initial, latest-offset, timestamp, specific-offset
);

-- Print all changes to console
SELECT
  id,
  name,
  email,
  created_at,
  updated_at,
  PROCTIME() as processing_time
FROM users_cdc;
