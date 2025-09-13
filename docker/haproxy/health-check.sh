#!/bin/bash
# HAProxy Health Check Script for PostgreSQL

POSTGRES_HOST=${1:-postgres-master}
POSTGRES_PORT=${2:-5432}
POSTGRES_USER=${3:-ramos}
POSTGRES_DB=${4:-ramos-test-db}

# Check if PostgreSQL is accepting connections
pg_isready -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB

if [ $? -eq 0 ]; then
    # Additional check: try to execute a simple query
    PGPASSWORD=ramostest123 psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT 1;" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "PostgreSQL is healthy"
        exit 0
    else
        echo "PostgreSQL connection failed"
        exit 1
    fi
else
    echo "PostgreSQL is not ready"
    exit 1
fi
