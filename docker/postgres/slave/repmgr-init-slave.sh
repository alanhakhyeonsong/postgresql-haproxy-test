#!/bin/bash
# repmgr-init-slave.sh - Slave 노드 초기화 스크립트

set -e

echo "repmgr Slave 노드 초기화 시작..."

# Master가 준비될 때까지 대기
echo "Master 노드 대기 중..."
until pg_isready -h postgres-master -U postgres -d postgres; do
    echo "Master 노드 준비 대기 중..."
    sleep 5
done

echo "Master 노드 연결 확인됨"

# 기존 PostgreSQL 프로세스 중단
echo "기존 PostgreSQL 프로세스 중단..."
pkill -f postgres || true
sleep 3

# 기존 데이터 디렉토리 정리
if [ -d "$PGDATA" ] && [ "$(ls -A $PGDATA 2>/dev/null)" ]; then
    echo "기존 데이터 디렉토리 정리 중..."
    rm -rf $PGDATA/*
fi

# Master에서 베이스 백업
echo "Master에서 베이스 백업 수행 중..."
su - postgres -c "PGPASSWORD=ramostest123 pg_basebackup -h postgres-master -D $PGDATA -U postgres -v -P -R"

# 추가 replication 설정
echo "Replication 설정 추가..."
cat >> $PGDATA/postgresql.auto.conf << EOF
# Enhanced replication settings
primary_conninfo = 'host=postgres-master port=5432 user=replicator password=replicator_password application_name=postgres-slave'
primary_slot_name = 'slave_slot'
restore_command = 'cp /var/lib/postgresql/archive/%f %p'
recovery_target_timeline = 'latest'
standby_mode = 'on'
hot_standby = on
hot_standby_feedback = on
EOF

# Standby 신호 파일 생성 (PostgreSQL 12+)
echo "Standby 신호 파일 생성 중..."
touch $PGDATA/standby.signal

# PostgreSQL 설정 파일 권한 조정
echo "권한 설정 중..."
chown -R postgres:postgres $PGDATA
chmod 700 $PGDATA
chmod 600 $PGDATA/postgresql.auto.conf

echo "repmgr Slave 초기화 스크립트 완료"

# 백그라운드에서 repmgr standby 등록 (PostgreSQL 시작 후)
(
    sleep 15
    echo "repmgr standby 등록 시작..."
    
    # repmgr 사용자 및 데이터베이스 생성 (필요한 경우)
    su - postgres -c "createuser -h localhost -s repmgr" 2>/dev/null || true
    su - postgres -c "createdb -h localhost -O repmgr repmgr" 2>/dev/null || true
    su - postgres -c "psql -h localhost -d repmgr -c \"CREATE EXTENSION IF NOT EXISTS repmgr;\"" 2>/dev/null || true
    
    # Standby 등록
    su - postgres -c "PGPASSWORD=repmgr_password repmgr -f /etc/repmgr.conf standby register --force" || {
        echo "Standby 등록 실패, 5초 후 재시도..."
        sleep 5
        su - postgres -c "PGPASSWORD=repmgr_password repmgr -f /etc/repmgr.conf standby register --force"
    }
    
    echo "repmgr standby 등록 완료"
) &