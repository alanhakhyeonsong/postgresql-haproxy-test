#!/bin/bash
set -e

echo "Setting up PostgreSQL Slave..."

# Wait for master to be ready
echo "Waiting for master database..."
until PGPASSWORD=ramostest123 pg_isready -h postgres-master -p 5432 -U ramos -d ramos-test-db; do
  echo "Master not ready yet, waiting..."
  sleep 5
done

echo "Master is ready. Setting up replication..."

# If this is the first run, we need to set up replication
if [ ! -f "/var/lib/postgresql/data/postgresql.conf" ]; then
    echo "First time setup - configuring for streaming replication"

    # Stop the default postgres process
    pg_ctl stop -D /var/lib/postgresql/data -m fast || true

    # Remove default data directory contents
    rm -rf /var/lib/postgresql/data/*

    # Create base backup from master
    echo "Creating base backup from master..."
    PGPASSWORD=replicator_password pg_basebackup \
        -h postgres-master \
        -D /var/lib/postgresql/data \
        -U replicator \
        -P \
        -v \
        -R \
        -X stream \
        -C -S slave_slot

    # Set proper ownership
    chown -R postgres:postgres /var/lib/postgresql/data
    chmod 700 /var/lib/postgresql/data

    echo "Base backup completed"
fi

echo "Starting PostgreSQL in standby mode..."
exec postgres -c config_file=/etc/postgresql/postgresql.conf -c hba_file=/etc/postgresql/pg_hba.conf
