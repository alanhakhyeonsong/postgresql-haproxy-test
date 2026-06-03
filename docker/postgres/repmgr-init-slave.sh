#!/bin/bash
# repmgr-init-slave.sh - Slave 초기화 스크립트

set -e

echo "=== repmgr Slave 초기화 시작 ==="

# Master가 준비될 때까지 대기
echo "Master 대기 중..."
until PGPASSWORD=ramostest123 pg_isready -h postgres-master -p 5432 -U ramos -d ramos-test-db; do
    echo "Master가 준비되지 않음, 대기 중..."
    sleep 3
done

echo "Master 준비 완료!"

# 로그 디렉토리 생성
mkdir -p /var/log/repmgr
chown postgres:postgres /var/log/repmgr

# repmgr.conf 는 read-only volume 마운트이므로 권한 변경하지 않는다 (chown/chmod 시 ro 에러).

echo "=== repmgr Slave 초기화 완료 ==="