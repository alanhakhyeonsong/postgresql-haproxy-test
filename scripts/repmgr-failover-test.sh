#!/bin/bash
# repmgr-failover-test.sh - repmgr failover 테스트 스크립트

echo "=== repmgr Failover 테스트 시작 ==="

# 컨테이너 상태 확인
echo "=== 컨테이너 상태 확인 ==="
docker ps --format "table {{.Names}}\t{{.Status}}" | grep postgres || echo "PostgreSQL 컨테이너가 실행되지 않았습니다."

# 현재 클러스터 상태 표시 (실패해도 계속 진행)
echo ""
echo "=== 현재 클러스터 상태 ==="
if docker ps | grep -q postgres-master; then
    docker exec postgres-master su - postgres -c "repmgr -f /etc/repmgr.conf cluster show" 2>/dev/null || echo "⚠️  repmgr 클러스터가 초기화되지 않았습니다 (정상적인 PostgreSQL 복제는 여전히 작동할 수 있습니다)"
else
    echo "❌ postgres-master 컨테이너가 실행되지 않고 있습니다."
fi

echo ""
echo "=== HAProxy 연결 테스트 (Master 중단 전) ==="
# HAProxy 컨테이너에는 psql이 없으므로 외부에서 접근
docker exec -e PGPASSWORD=ramostest123 postgres-master psql -h postgres-haproxy -p 3000 -U ramos -d ramos-test-db -c "SELECT 'Connected via HAProxy to Master', current_timestamp;" 2>/dev/null || echo "❌ HAProxy를 통한 Master 연결 실패"

echo ""
echo "=== 복제 상태 확인 ==="
echo "Master에서 복제 상태:"
docker exec postgres-master psql -U postgres -c "SELECT application_name, client_addr, state, sync_state FROM pg_stat_replication;" 2>/dev/null || echo "복제 정보 없음"

echo "Slave에서 복제 수신 상태:"
docker exec postgres-slave psql -U postgres -c "SELECT status, receive_start_lsn, received_lsn, last_msg_send_time FROM pg_stat_wal_receiver;" 2>/dev/null || echo "Standby가 아니거나 복제 수신 중 아님"

echo ""
echo "=== Master 중단 시뮬레이션 ==="
docker-compose stop postgres-master
echo "✅ Master 컨테이너 중단 완료"

echo ""
echo "=== HAProxy Failover 대기 중 (5초) ==="
sleep 5

echo ""
echo "=== HAProxy 자동 Failover 테스트 ==="
docker exec -e PGPASSWORD=ramostest123 postgres-slave psql -h postgres-haproxy -p 3000 -U ramos -d ramos-test-db -c "SELECT 'Failover Success - Connected via HAProxy to Slave', current_timestamp;" 2>/dev/null && echo "✅ HAProxy Failover 성공!" || echo "❌ HAProxy Failover 실패"

echo ""
echo "=== repmgr 자동 승격 확인 ==="
# repmgr가 자동으로 승격했는지 확인
sleep 5  # repmgr 자동 승격 대기
docker exec postgres-slave su - postgres -c "repmgr -f /etc/repmgr.conf cluster show" 2>/dev/null || echo "⚠️  repmgr 클러스터 상태 확인 불가"

echo ""
echo "=== Slave 직접 연결 테스트 ==="
docker exec -e PGPASSWORD=ramostest123 postgres-slave psql -h localhost -U ramos -d ramos-test-db -c "SELECT 'Direct Slave Connection', current_timestamp;"

echo ""
echo "=== repmgr 기반 승격 시도 (참고용) ==="
if docker ps | grep -q postgres-slave; then
    docker exec postgres-slave su - postgres -c "repmgr -f /etc/repmgr.conf standby promote" 2>/dev/null && echo "✅ repmgr 승격 성공" || echo "⚠️  repmgr 승격 실패 (HAProxy failover는 여전히 작동함)"
else
    echo "❌ postgres-slave 컨테이너가 실행되지 않고 있습니다."
fi

echo ""
echo "=== Failover 테스트 완료 ==="
echo ""
echo "📋 복구 방법:"
echo "   Master 재시작: docker-compose start postgres-master"
echo "   전체 재시작: docker-compose restart"
echo ""
echo "📊 모니터링:"
echo "   HAProxy Stats: http://localhost:8080/stats (admin/admin123)"
echo "   PgAdmin: http://localhost:8081"