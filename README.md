# PostgreSQL 고가용성 클러스터 with HAProxy & Keepalived

## 구성 개요

이 프로젝트는 PostgreSQL Master-Slave 복제, HAProxy 로드밸런싱, Keepalived VIP 관리를 통한 완전한 고가용성 데이터베이스 클러스터를 제공합니다.

### 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                    Application Layer                        │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────┐
│              VIP: 172.20.0.100:3000                         │
│                 (Keepalived 관리)                            │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────────┐
│                HAProxy Load Balancer                            │
│               (172.20.0.20:3000/3001)                           │
│        ┌───────────────────┬───────────────────┐                │
│        │   Write Port      │   Read Port       │                │
│        │     :3000         │     :3001         │                │
└────────┼───────────────────┼───────────────────┼────────────────┘
         │                   │                   │
    ┌────▼──────┐       ┌────▼──────┐       ┌────▼────┐
    │PostgreSQL │  ◄─►  │PostgreSQL │   ◄─► │ Metrics │
    │ Master    │       │  Slave    │       │ & Admin │
    │172.20.0.10│       │172.20.0.11│       │         │
    │  :5432    │       │  :5433    │       │ PgAdmin │
    └───────────┘       └───────────┘       │  :8081  │
                                            └─────────┘
```

### 서비스 구성

- **postgres-master**: PostgreSQL 15 Master (읽기/쓰기)
- **postgres-slave**: PostgreSQL 15 Slave (읽기 전용, 스트리밍 복제)
- **haproxy**: HAProxy 2.8 로드밸런서 및 헬스체크
- **keepalived-primary/backup**: Keepalived VIP 관리 및 자동 Failover
- **pgadmin**: PgAdmin4 웹 기반 관리 도구

### 네트워크 구성 및 포트

| 서비스 | 컨테이너 IP | 호스트 포트 | 설명 |
|--------|-------------|-------------|------|
| **VIP** | 172.20.0.100 | - | **가상 IP (애플리케이션 연결점)** |
| postgres-master | 172.20.0.10 | 5432 | PostgreSQL Master DB |
| postgres-slave | 172.20.0.11 | 5433 | PostgreSQL Slave DB |
| haproxy | 172.20.0.20 | 3000, 3001, 8080 | 로드밸런서 |
| keepalived-primary | 172.20.0.21 | - | VIP 관리 (Primary) |
| keepalived-backup | 172.20.0.22 | - | VIP 관리 (Backup) |
| pgadmin | 172.20.0.30 | 8081 | 웹 관리 인터페이스 |

**Docker 네트워크**: `172.20.0.0/16` (65,534개 IP 주소 사용 가능)

## Quick Start

### 1. 전체 시스템 시작
```bash
# 모든 서비스 시작 (약 30초 소요)
docker-compose up -d

# 실시간 로그 모니터링
docker-compose logs -f
```

### 2. 서비스 상태 확인
```bash
# 컨테이너 상태 확인
docker-compose ps

# 헬스체크 상태 확인
docker-compose ps | grep "healthy"
```

### 3. 복제 상태 검증
```bash
# Master에 테스트 데이터 추가
docker exec postgres-master psql -U ramos -d ramos-test-db -c "
  CREATE TABLE IF NOT EXISTS test_replication (
    id SERIAL PRIMARY KEY, 
    data TEXT, 
    created_at TIMESTAMP DEFAULT NOW()
  );
  INSERT INTO test_replication (data) VALUES ('복제 테스트 데이터');
"

# Slave에서 복제 확인
docker exec postgres-slave psql -U ramos -d ramos-test-db -c "
  SELECT * FROM test_replication;
"
```

### 4. 웹 인터페이스 접속
- **HAProxy 통계**: http://localhost:8080/stats
- **PgAdmin 관리**: http://localhost:8081 (admin@example.com / admin123)

## 애플리케이션 연결 방법

### 로컬 개발 환경 연결
```bash
# VIP를 통한 연결 (권장)
localhost:3000  → 자동 로드밸런싱 (Write → Master, Read 분산)

# 직접 연결 (디버깅용)
localhost:5432  → Master DB (Read/Write)
localhost:5433  → Slave DB (Read-only)
```

### Spring Boot 애플리케이션 설정

#### 단일 DataSource 설정 (권장)
```yaml
spring:
  datasource:
    driver-class-name: org.postgresql.Driver
    jdbc-url: jdbc:postgresql://localhost:3000/ramos-test-db?currentSchema=ramos-test-db
    username: ramos
    password: ramostest123
    hikari:
      maximum-pool-size: 20
      connection-timeout: 30000
```

#### 읽기/쓰기 분리 설정 (고급)
```yaml
spring:
  datasource:
    master:
      jdbc-url: jdbc:postgresql://localhost:3000/ramos-test-db?currentSchema=ramos-test-db
      username: ramos
      password: ramostest123
    slave:
      jdbc-url: jdbc:postgresql://localhost:3001/ramos-test-db?currentSchema=ramos-test-db
      username: ramos
      password: ramostest123
```

### Docker 컨테이너 내부 연결
```yaml
# Docker 네트워크 내부에서 연결 시
spring:
  datasource:
    jdbc-url: jdbc:postgresql://172.20.0.100:3000/ramos-test-db?currentSchema=ramos-test-db
```

## 고가용성 및 자동 Failover

### 1. Master DB 장애 시나리오
```
정상 상태: App → VIP → HAProxy → Master (Primary)
                                 ↓
                               Slave (Standby)

장애 발생: App → VIP → HAProxy → Master (DOWN) ❌
                                 ↓
                               Slave (Promoted) ✅
```
- HAProxy가 Master 장애 감지 (3초 간격 헬스체크)
- 자동으로 Slave를 Primary로 승격
- 애플리케이션은 VIP 연결 유지로 투명한 Failover

### 2. HAProxy 장애 시나리오
```
정상 상태: App → VIP (Primary Keepalived) → HAProxy → DB

장애 발생: App → VIP (Backup Keepalived) → HAProxy → DB
```
- Primary Keepalived가 HAProxy 장애 감지
- Backup Keepalived가 VIP(172.20.0.100) 획득
- 서비스 중단 없이 연속성 보장

### 3. 복제 지연 및 동기화
- **스트리밍 복제**: 실시간 WAL 로그 전송
- **복제 슬롯**: 데이터 손실 방지 (`slave_slot`)
- **자동 재연결**: 네트워크 장애 시 자동 복구

## 모니터링 및 관리

### HAProxy 통계 대시보드
- **URL**: http://localhost:8080/stats
- **기능**: 실시간 백엔드 서버 상태, 연결 수, 응답 시간 모니터링
- **서버 상태**: UP/DOWN, 헬스체크 결과 확인

### PgAdmin 웹 관리 도구
- **URL**: http://localhost:8081
- **계정**: admin@example.com / admin123
- **기능**: 데이터베이스 관리, 쿼리 실행, 성능 모니터링

### 복제 상태 모니터링
```sql
-- Master에서 복제 상태 확인
SELECT application_name, client_addr, state, sync_state 
FROM pg_stat_replication;

-- Slave에서 복제 지연 확인
SELECT CASE WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn()
       THEN 0
       ELSE EXTRACT (EPOCH FROM now() - pg_last_xact_replay_timestamp())
       END AS replication_delay_seconds;
```

### 실시간 로그 모니터링
```bash
# 모든 서비스 로그
docker-compose logs -f

# 특정 서비스 로그
docker-compose logs -f postgres-master
docker-compose logs -f postgres-slave
docker-compose logs -f haproxy
docker-compose logs -f keepalived-primary
```

## 문제 해결 가이드

### 1. 복제 연결 문제
```bash
# 복제 상태 전체 점검
docker exec postgres-master psql -U ramos -d ramos-test-db -c "
  SELECT application_name, client_addr, state, sync_state, 
         pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), flush_lsn)) as lag
  FROM pg_stat_replication;
"

# Slave 연결 상태 확인
docker exec postgres-slave psql -U ramos -d ramos-test-db -c "
  SELECT status, sender_host, sender_port, conninfo 
  FROM pg_stat_wal_receiver;
"
```

### 2. VIP 할당 상태 확인
```bash
# VIP가 활성화된 Keepalived 확인
docker exec keepalived-primary ip addr show eth0 | grep 172.20.0.100
docker exec keepalived-backup ip addr show eth0 | grep 172.20.0.100

# Keepalived 프로세스 상태
docker exec keepalived-primary ps aux | grep keepalived
```

### 3. HAProxy 백엔드 서버 상태
```bash
# HAProxy 설정 검증
docker exec postgres-haproxy haproxy -f /usr/local/etc/haproxy/haproxy.cfg -c

# 백엔드 서버 연결 테스트
docker exec postgres-haproxy nc -zv postgres-master 5432
docker exec postgres-haproxy nc -zv postgres-slave 5432
```

### 4. 일반적인 해결 방법
```bash
# 개별 서비스 재시작
docker-compose restart postgres-slave
docker-compose restart haproxy
docker-compose restart keepalived-primary

# 전체 시스템 재시작 (데이터 보존)
docker-compose down
docker-compose up -d

# 완전 초기화 (주의: 모든 데이터 삭제)
docker-compose down -v
docker-compose up -d
```

## ⚠️ 운영 시 주의사항

### 시스템 요구사항
- **Docker**: 20.10.0 이상
- **Docker Compose**: 2.0.0 이상  
- **메모리**: 최소 4GB RAM 권장
- **네트워크**: 172.20.0.0/16 대역 사용 가능

### 초기 설정 주의사항
1. **시작 순서**: Master → Slave → HAProxy → Keepalived 순으로 초기화
2. **대기 시간**: Slave 초기화에 약 30-60초 소요
3. **권한 설정**: Keepalived는 NET_ADMIN 권한으로 실행
4. **포트 충돌**: 5432, 5433, 3000, 3001, 8080, 8081 포트 확인

### 데이터 보안 및 백업
```bash
# 정기 백업 (Master에서 실행)
docker exec postgres-master pg_dump -U ramos ramos-test-db > backup_$(date +%Y%m%d).sql

# 볼륨 백업
docker run --rm -v postgresql-haproxy_postgres_master_data:/data -v $(pwd):/backup alpine tar czf /backup/master_backup.tar.gz /data
```

## 고급 운영 가이드

### 성능 튜닝
```sql
-- 연결 풀 최적화
ALTER SYSTEM SET max_connections = 200;
ALTER SYSTEM SET shared_buffers = '256MB';
ALTER SYSTEM SET effective_cache_size = '1GB';
ALTER SYSTEM SET work_mem = '4MB';

-- 복제 성능 향상
ALTER SYSTEM SET wal_buffers = '16MB';
ALTER SYSTEM SET checkpoint_completion_target = 0.7;
```

### 수동 Failover 절차
```bash
# 1. Master 장애 시 Slave를 Master로 승격
docker exec postgres-slave pg_ctl promote -D /var/lib/postgresql/data

# 2. 새로운 Slave 설정 (기존 Master 복구 후)
docker exec postgres-master pg_basebackup -h postgres-slave -D /var/lib/postgresql/data -U replicator -v -P -R
```

### 모니터링 스크립트
```bash
#!/bin/bash
# health_check.sh - 시스템 상태 점검 스크립트
echo "=== PostgreSQL HA 클러스터 상태 점검 ==="
echo "컨테이너 상태:"
docker-compose ps

echo -e "\n복제 상태:"
docker exec postgres-master psql -U ramos -d ramos-test-db -c "SELECT application_name, state FROM pg_stat_replication;"

echo -e "\nVIP 상태:"
docker exec keepalived-primary ip addr show eth0 | grep 172.20.0.100 && echo "VIP: Primary에 할당됨" || echo "VIP: Backup에 할당됨"
```

## 체크리스트

### 배포 전 점검
- [ ] Docker 및 Docker Compose 버전 확인
- [ ] 필요 포트 사용 가능 여부 확인
- [ ] 네트워크 대역 172.20.0.0/16 충돌 확인
- [ ] 시스템 리소스 충분 여부 확인

### 배포 후 검증
- [ ] 모든 컨테이너 healthy 상태 확인
- [ ] Master-Slave 복제 동작 확인
- [ ] VIP 할당 및 Failover 테스트
- [ ] HAProxy 로드밸런싱 동작 확인
- [ ] 애플리케이션 연결 테스트
