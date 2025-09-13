#!/bin/bash
# repmgr-setup.sh - repmgr 클러스터 설정 스크립트

set -e

echo "=== repmgr 클러스터 설정 시작 ==="

# Master 등록
echo "Master 노드 등록 중..."
docker exec postgres-master su - postgres -c "repmgr -f /etc/repmgr.conf primary register"

# Slave 등록
echo "Slave 노드 등록 중..."
docker exec postgres-slave su - postgres -c "repmgr -f /etc/repmgr.conf standby register"

# 클러스터 상태 확인
echo "클러스터 상태 확인:"
docker exec postgres-master su - postgres -c "repmgr -f /etc/repmgr.conf cluster show"

echo "=== repmgr 클러스터 설정 완료 ==="