-- Master Database Initialization Script
-- Create replication user
CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD 'replicator_password';

-- Create ramos-test-db schema if not exists
CREATE SCHEMA IF NOT EXISTS "ramos-test-db";

-- Grant necessary permissions
GRANT USAGE ON SCHEMA "ramos-test-db" TO ramos;
GRANT ALL PRIVILEGES ON SCHEMA "ramos-test-db" TO ramos;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA "ramos-test-db" TO ramos;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA "ramos-test-db" TO ramos;

-- Set default schema for ramos user
ALTER USER ramos SET search_path TO "ramos-test-db";
