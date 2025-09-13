#!/bin/bash
set -e

echo "=== PostgreSQL Slave Setup Script ==="

# Wait for master to be ready
echo "Waiting for master to be ready..."
until PGPASSWORD=ramostest123 pg_isready -h postgres-master -p 5432 -U ramos -d ramos-test-db; do
    echo "Master not ready, waiting..."
    sleep 3
done

echo "Master is ready!"

# Check if this is first time setup
if [ ! -f /var/lib/postgresql/data/PG_VERSION ]; then
    echo "Setting up slave replication..."
    
    # Clean any existing data
    rm -rf /var/lib/postgresql/data/*
    
    # Create base backup from master
    echo "Creating base backup from master..."
    PGPASSWORD=replicator_password pg_basebackup \
        -h postgres-master \
        -D /var/lib/postgresql/data \
        -U replicator \
        -v -P -R
    
    # Create standby.signal for PostgreSQL 12+
    touch /var/lib/postgresql/data/standby.signal
    
    # Configure replication connection
    cat >> /var/lib/postgresql/data/postgresql.auto.conf << EOF
primary_conninfo = 'host=postgres-master port=5432 user=replicator password=replicator_password application_name=postgres-slave'
primary_slot_name = 'slave_slot'
max_connections = 200
EOF
    
    echo "Slave setup completed successfully!"
else
    echo "Slave already initialized, skipping setup..."
fi

echo "Starting PostgreSQL..."
