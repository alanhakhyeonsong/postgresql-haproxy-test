#!/bin/bash
# repmgr-failover-test.sh - repmgr failover 테스트 스크립트

set -e

echo "=== repmgr Failover 테스트 시작 ==="

# 현재 클러스터 상태 표시
echo "현재 클러스터 상태:"
docker exec postgres-master su - postgres -c "repmgr -f /etc/repmgr.conf cluster show" || echo "Master가 다운된 상태일 수 있습니다."

# Master 중단 시뮬레이션
echo "Master 중단 중..."
docker-compose stop postgres-master

# 잠시 대기
echo "5초 대기 중..."
sleep 5

# Slave를 Master로 승격
echo "Slave를 Master로 승격 중..."
docker exec postgres-slave su - postgres -c "repmgr -f /etc/repmgr.conf standby promote"

# 승격 후 상태 확인
echo "승격 후 클러스터 상태:"
docker exec postgres-slave su - postgres -c "repmgr -f /etc/repmgr.conf cluster show"

# 연결 테스트
echo "새로운 Master 연결 테스트:"
docker exec -e PGPASSWORD=ramostest123 postgres-slave psql -h localhost -U ramos -d ramos-test-db -c "SELECT 'New Master Active', current_timestamp;"

echo "=== Failover 테스트 완료 ==="
echo "원래 Master를 다시 시작하려면: docker-compose start postgres-master"
echo "그 후 재등록하려면: docker exec postgres-master su - postgres -c \"repmgr -f /etc/repmgr.conf standby clone -h postgres-slave -U repmgr -d repmgr --force\""