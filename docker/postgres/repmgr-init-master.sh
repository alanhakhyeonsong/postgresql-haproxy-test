#!/bin/bash
# repmgr-init-master.sh - Master 초기화 스크립트

set -e

echo "=== repmgr Master 초기화 시작 ==="

# repmgr 사용자 및 데이터베이스 생성
echo "repmgr 사용자 및 데이터베이스 생성..."
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- Create repmgr user (SUPERUSER 필요: repmgr extension 설치/등록에 superuser 권한 요구)
    CREATE USER repmgr WITH SUPERUSER REPLICATION LOGIN PASSWORD 'repmgr_password';

    -- Create repmgr database
    CREATE DATABASE repmgr OWNER repmgr;

    -- Grant necessary permissions
    ALTER USER repmgr CREATEDB;
    
    -- Grant permissions on ramos-test-db
    GRANT CONNECT ON DATABASE "ramos-test-db" TO repmgr;
    GRANT USAGE ON SCHEMA "ramos-test-db" TO repmgr;
    GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA "ramos-test-db" TO repmgr;
    GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA "ramos-test-db" TO repmgr;
EOSQL

echo "repmgr 초기화 완료!"

# 로그 디렉토리 생성
mkdir -p /var/log/repmgr
chown postgres:postgres /var/log/repmgr

# repmgr.conf 는 read-only volume 마운트이므로 권한 변경하지 않는다 (chown/chmod 시 ro 에러).

echo "=== repmgr Master 초기화 완료 ==="