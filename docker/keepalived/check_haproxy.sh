#!/bin/bash
# Keepalived Health Check Script for HAProxy

# Check if HAProxy is running and healthy
curl -f http://172.20.0.20:8080/stats > /dev/null 2>&1

if [ $? -eq 0 ]; then
    # Additional check: verify HAProxy can reach PostgreSQL
    /usr/local/bin/health-check.sh postgres-master 5432 ramos ramos-test-db
    exit $?
else
    echo "HAProxy is not responding"
    exit 1
fi
