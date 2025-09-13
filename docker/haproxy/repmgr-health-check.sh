#!/bin/bash
# repmgr-aware-health-check.sh - repmgr 연동 헬스체크 스크립트

POSTGRES_HOST=${1:-postgres-master}
POSTGRES_PORT=${2:-5432}
POSTGRES_USER=${3:-ramos}
POSTGRES_DB=${4:-ramos-test-db}

# PostgreSQL 연결 체크
pg_isready -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB

if [ $? -eq 0 ]; then
    # 추가 체크: 데이터베이스 쿼리 실행 가능 여부
    PGPASSWORD=ramostest123 psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT 1;" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        # repmgr 상태 체크 (선택적)
        # Master 여부 체크
        PGPASSWORD=repmgr_password psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U repmgr -d repmgr -c "SELECT type FROM repmgr.nodes WHERE node_name='$(hostname)' AND active=true;" 2>/dev/null | grep -q "primary"
        if [ $? -eq 0 ]; then
            echo "PostgreSQL Master is healthy"
            exit 0
        else
            # Standby 여부 체크
            PGPASSWORD=repmgr_password psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U repmgr -d repmgr -c "SELECT type FROM repmgr.nodes WHERE node_name='$(hostname)' AND active=true;" 2>/dev/null | grep -q "standby"
            if [ $? -eq 0 ]; then
                echo "PostgreSQL Standby is healthy"
                exit 0
            else
                echo "PostgreSQL is healthy (repmgr status unknown)"
                exit 0
            fi
        fi
    else
        echo "PostgreSQL connection failed"
        exit 1
    fi
else
    echo "PostgreSQL is not ready"
    exit 1
fi