#!/bin/bash
# repmgr-status.sh - repmgr 상태 확인 스크립트

echo "=== repmgr 클러스터 상태 ==="

# 클러스터 정보 표시
echo "클러스터 토폴로지:"
docker exec postgres-master su - postgres -c "repmgr -f /etc/repmgr.conf cluster show" 2>/dev/null || \
docker exec postgres-slave su - postgres -c "repmgr -f /etc/repmgr.conf cluster show" 2>/dev/null || \
echo "클러스터 정보를 가져올 수 없습니다."

echo -e "\n=== 개별 노드 상태 ==="

# Master 상태
echo "Master 노드 (postgres-master):"
docker exec postgres-master su - postgres -c "repmgr -f /etc/repmgr.conf node status" 2>/dev/null || echo "Master 노드가 응답하지 않습니다."

# Slave 상태  
echo -e "\nSlave 노드 (postgres-slave):"
docker exec postgres-slave su - postgres -c "repmgr -f /etc/repmgr.conf node status" 2>/dev/null || echo "Slave 노드가 응답하지 않습니다."

echo -e "\n=== PostgreSQL 복제 상태 ==="

# Master에서 복제 상태 확인
echo "Master 복제 상태:"
docker exec -e PGPASSWORD=ramostest123 postgres-master psql -U ramos -d ramos-test-db -c "SELECT application_name, client_addr, state, sync_state FROM pg_stat_replication;" 2>/dev/null || echo "Master 복제 정보를 가져올 수 없습니다."

# Slave에서 복제 상태 확인
echo -e "\nSlave 복제 상태:"
docker exec -e PGPASSWORD=ramostest123 postgres-slave psql -U ramos -d ramos-test-db -c "SELECT status, sender_host, sender_port FROM pg_stat_wal_receiver;" 2>/dev/null || echo "Slave 복제 정보를 가져올 수 없습니다."

echo -e "\n=== 컨테이너 상태 ==="
docker-compose ps