#!/bin/bash
# repmgr-init-master.sh - Master 노드 초기화 스크립트

set -e

echo "repmgr Master 노드 초기화 시작..."

# PostgreSQL이 시작될 때까지 대기
until pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"; do
    echo "PostgreSQL 시작 대기 중..."
    sleep 2
done

# repmgr 사용자 및 데이터베이스 생성
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- repmgr 전용 사용자 생성
    CREATE USER repmgr SUPERUSER LOGIN;
    ALTER USER repmgr PASSWORD 'repmgr_password';
    
    -- repmgr 데이터베이스 생성
    CREATE DATABASE repmgr OWNER repmgr;
    
    -- 복제 슬롯 생성
    SELECT pg_create_physical_replication_slot('slave_slot');
EOSQL

echo "repmgr 사용자, 데이터베이스 및 복제 슬롯 생성 완료"

# repmgr 확장 설치
psql -v ON_ERROR_STOP=1 --username "repmgr" --dbname "repmgr" <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS repmgr;
EOSQL

echo "repmgr 확장 설치 완료"

# WAL 아카이브 디렉토리 생성
mkdir -p /var/lib/postgresql/archive
chown postgres:postgres /var/lib/postgresql/archive
chmod 755 /var/lib/postgresql/archive

echo "WAL 아카이브 디렉토리 생성 완료"

# Master 노드 등록 (서버가 완전히 시작된 후 실행되도록 백그라운드에서)
(
    # PostgreSQL이 완전히 시작될 때까지 추가 대기
    sleep 10
    
    # Master 노드로 등록
    su - postgres -c "PGPASSWORD=repmgr_password repmgr -f /etc/repmgr.conf primary register --force" || {
        echo "Primary 등록 실패, 5초 후 재시도..."
        sleep 5
        su - postgres -c "PGPASSWORD=repmgr_password repmgr -f /etc/repmgr.conf primary register --force"
    }
    
    echo "repmgr Primary 노드 등록 완료"
    
    # repmgrd 데몬 시작
    su - postgres -c "repmgrd -f /etc/repmgr.conf --daemonize"
    echo "repmgrd 데몬 시작 완료"
) &

echo "repmgr Master 초기화 스크립트 완료"