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

- **postgres-master**: PostgreSQL 15 Master with repmgr (읽기/쓰기)
- **postgres-slave**: PostgreSQL 15 Slave with repmgr (읽기 전용, 자동 failover 지원)
- **haproxy**: HAProxy 2.8 로드밸런서 및 헬스체크
- **keepalived-primary/backup**: Keepalived VIP 관리 및 자동 Failover
- **pgadmin**: PgAdmin4 웹 기반 관리 도구
- **repmgr**: PostgreSQL 자동 failover 및 클러스터 관리

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

### 4. repmgr 클러스터 설정
```bash
# repmgr 클러스터 초기 설정
chmod +x scripts/repmgr-setup.sh
./scripts/repmgr-setup.sh

# repmgr 클러스터 상태 확인
chmod +x scripts/repmgr-status.sh
./scripts/repmgr-status.sh
```

### 4. 웹 인터페이스 접속
- **HAProxy 통계**: http://localhost:8080/stats
- **PgAdmin 관리**: http://localhost:8081 (admin@example.com / admin123)

#### PgAdmin 서버 등록 정보

**Master 서버 등록:**
- Name: `PostgreSQL Master`
- Host: `postgres-master` (Docker 네트워크) 또는 `localhost` (호스트)
- Port: `5432`
- Database: `ramos-test-db`
- Username: `ramos`
- Password: `ramostest123`

**Slave 서버 등록:**
- Name: `PostgreSQL Slave`
- Host: `postgres-slave` (Docker 네트워크) 또는 `localhost` (호스트)
- Port: `5432` (Docker 네트워크) 또는 `5433` (호스트)
- Database: `ramos-test-db`
- Username: `ramos`
- Password: `ramostest123`

**HAProxy 통합 연결 (권장):**
- Name: `PostgreSQL via HAProxy`
- Host: `postgres-haproxy` (Docker 네트워크) 또는 `localhost` (호스트)
- Port: `3000` (Write) 또는 `3001` (Read)
- Database: `ramos-test-db`
- Username: `ramos`
- Password: `ramostest123`

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

## repmgr 자동 Failover 시스템

### repmgr 특징
- **자동 장애 감지**: Master 장애 시 자동으로 Slave를 Master로 승격
- **클러스터 관리**: 노드 상태 모니터링 및 관리
- **무중단 Failover**: 애플리케이션 연결 중단 최소화
- **자동 복구**: 장애 복구 시 자동으로 클러스터에 재참여

### repmgr 관리 명령어

#### 클러스터 상태 확인
```bash
# 전체 클러스터 상태
./scripts/repmgr-status.sh

# 간단한 클러스터 정보
docker exec postgres-master su - postgres -c "repmgr -f /etc/repmgr.conf cluster show"
```

#### 수동 Failover 테스트
```bash
# Failover 테스트 (Master 중단 → Slave 승격)
./scripts/repmgr-failover-test.sh
```

#### 노드 관리
```bash
# Master 재등록 (Failover 후 복구 시)
docker exec postgres-master su - postgres -c "repmgr -f /etc/repmgr.conf standby clone -h postgres-slave -U repmgr -d repmgr --force"
docker exec postgres-master su - postgres -c "repmgr -f /etc/repmgr.conf standby register --force"

# Slave 재등록
docker exec postgres-slave su - postgres -c "repmgr -f /etc/repmgr.conf standby register --force"
```

## 고가용성 및 자동 Failover

### 1. repmgr 기반 자동 Failover 시나리오

#### 정상 운영 상태
```
App → VIP(172.20.0.100) → HAProxy → Master(postgres-master) [Primary]
                                      ↓ (Streaming Replication)
                                   Slave(postgres-slave) [Standby]
                                      ↑
                                 repmgr(Monitoring)
```

#### Master 장애 발생 시
```bash
# 1. Master 서버 중단 시뮬레이션
docker stop postgres-master

# 2. repmgr 자동 반응 과정 (5-10초 내)
# - repmgr가 Master 장애 감지
# - Slave 노드가 자동으로 Master로 승격
# - 새로운 Master가 쓰기 권한 획득

# 3. HAProxy 자동 재라우팅
# - HAProxy가 승격된 노드 감지
# - 트래픽이 새로운 Master로 전환
```

#### Failover 완료 상태
```
App → VIP(172.20.0.100) → HAProxy → Master(postgres-master) [DOWN] ❌
                                      ↓
                                   Slave(postgres-slave) [Promoted Master] ✅
```

#### Failover 테스트 및 확인
```bash
# 자동 Failover 테스트
./scripts/repmgr-failover-test.sh

# 클러스터 상태 확인
./scripts/repmgr-status.sh

# 새로운 Master로 연결 테스트
docker exec postgres-slave psql -h haproxy -p 5432 -U ramos -d ramos-test-db

# 쓰기 권한 확인 (승격 테스트)
echo "INSERT INTO test_failover (timestamp) VALUES (NOW());" | \
docker exec -i postgres-slave psql -h haproxy -p 5432 -U ramos -d ramos-test-db
```

### 2. HAProxy 장애 시나리오
```
정상 상태: App → VIP(Primary Keepalived) → HAProxy-1 → PostgreSQL Cluster
                                         
장애 발생: App → VIP(Backup Keepalived) → HAProxy-2 → PostgreSQL Cluster
```
- Primary Keepalived가 HAProxy 장애 감지
- Backup Keepalived가 VIP(172.20.0.100) 획득
- 서비스 중단 없이 연속성 보장

### 3. 전체 장애 복구 절차

#### Master 노드 복구 (Failover 후)
```bash
# 1. 기존 Master 컨테이너 제거
docker rm postgres-master

# 2. 새로운 Master에서 기존 Master를 Standby로 재구성
docker exec postgres-slave su - postgres -c "pg_basebackup -h postgres-slave -D /tmp/master_backup -U repmgr -v -P -W"

# 3. Master 컨테이너 재시작 (Standby 모드)
docker-compose up -d postgres-master

# 4. repmgr에 Standby로 재등록
docker exec postgres-master su - postgres -c "repmgr -f /etc/repmgr.conf standby register --force"
```

#### 클러스터 상태 복구 확인
```bash
# 클러스터 전체 상태 확인
./scripts/repmgr-status.sh

# 복제 상태 확인
docker exec postgres-master psql -U postgres -c "SELECT * FROM pg_stat_replication;"
docker exec postgres-slave psql -U postgres -c "SELECT * FROM pg_stat_wal_receiver;"
```

### 4. repmgr 고급 설정

#### 자동 Failover 파라미터
- **failover_validation_command**: 승격 전 검증 명령
- **promote_command**: Master 승격 시 실행 명령  
- **follow_command**: 새로운 Master 추적 명령
- **monitoring_interval**: 상태 모니터링 주기 (5초)
- **retry_promote_interval_secs**: 승격 재시도 간격

#### 클러스터 모니터링
- **스트리밍 복제**: 실시간 WAL 로그 전송
- **복제 슬롯**: 데이터 손실 방지 (`slave_slot`)
- **자동 재연결**: 네트워크 장애 시 자동 복구
- **상태 체크**: repmgr daemon을 통한 지속적 모니터링

## 모니터링 및 관리

### 1. repmgr 클러스터 모니터링

#### 통합 상태 확인 스크립트
```bash
# 전체 클러스터 상태 (권장)
./scripts/repmgr-status.sh

# 출력 예시:
# ==========================================
# repmgr Cluster Status
# ==========================================
# ID | Name              | Role    | Status    | Upstream | Location
# ---+-------------------+---------+-----------+----------+----------
# 1  | postgres-master   | primary | * running |          | default
# 2  | postgres-slave    | standby |   running | 1        | default
```

#### 개별 모니터링 명령어
```bash
# 클러스터 간단 보기
docker exec postgres-master su - postgres -c "repmgr -f /etc/repmgr.conf cluster show"

# 복제 지연 확인
docker exec postgres-master su - postgres -c "repmgr -f /etc/repmgr.conf cluster show --verbose"

# 노드별 상세 정보
docker exec postgres-master su - postgres -c "repmgr -f /etc/repmgr.conf node status"
docker exec postgres-slave su - postgres -c "repmgr -f /etc/repmgr.conf node status"
```

### 2. HAProxy 통계 대시보드
- **URL**: http://localhost:8404/stats
- **인증**: admin / admin123
- **기능**: 
  - 실시간 백엔드 서버 상태 모니터링
  - 연결 수 및 응답 시간 추적
  - repmgr 승격 시 자동 서버 전환 확인
- **서버 상태**: UP/DOWN, 헬스체크 결과 실시간 확인

### 3. PgAdmin 웹 관리 도구
- **URL**: http://localhost:8081
- **계정**: admin@example.com / admin123
- **기능**: 데이터베이스 관리, 쿼리 실행, 성능 모니터링, repmgr 이벤트 로그 확인

### 4. PostgreSQL 복제 상태 모니터링
```sql
-- Master에서 복제 상태 확인
SELECT application_name, client_addr, state, sync_state, 
       sent_lsn, write_lsn, flush_lsn, replay_lsn
FROM pg_stat_replication;

-- Slave에서 복제 지연 확인
SELECT CASE WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn()
       THEN 0
       ELSE EXTRACT (EPOCH FROM now() - pg_last_xact_replay_timestamp())
       END AS replication_delay_seconds;

-- repmgr 이벤트 로그 확인
SELECT * FROM repmgr.events ORDER BY event_timestamp DESC LIMIT 10;

-- 클러스터 노드 정보 확인
SELECT * FROM repmgr.nodes;
```

### 5. 실시간 로그 모니터링
```bash
# 모든 서비스 로그
docker-compose logs -f

# 특정 서비스 로그 (repmgr 관련 정보 포함)
docker-compose logs -f postgres-master  # repmgr primary 로그
docker-compose logs -f postgres-slave   # repmgr standby 로그
docker-compose logs -f haproxy          # 백엔드 전환 로그
docker-compose logs -f keepalived-primary # VIP 관리 로그

# repmgr 전용 로그 확인
docker exec postgres-master tail -f /var/log/postgresql/repmgr.log
docker exec postgres-slave tail -f /var/log/postgresql/repmgr.log
```

## repmgr 트러블슈팅 가이드

### 1. repmgr 클러스터 연결 문제

#### 증상: "repmgr cluster show" 명령이 실패하거나 노드가 보이지 않음
```bash
# 문제 진단
./scripts/repmgr-status.sh

# repmgr 데이터베이스 연결 확인
docker exec postgres-master psql -U repmgr -d repmgr -c "SELECT * FROM repmgr.nodes;"

# 해결 방안
# 1. 노드 재등록
docker exec postgres-master su - postgres -c "repmgr -f /etc/repmgr.conf primary register --force"
docker exec postgres-slave su - postgres -c "repmgr -f /etc/repmgr.conf standby register --force"

# 2. repmgr 서비스 재시작
docker-compose restart postgres-master postgres-slave
```

### 2. 자동 Failover 실패

#### 증상: Master 장애 시 Slave가 자동으로 승격되지 않음
```bash
# repmgrd 데몬 상태 확인
docker exec postgres-slave ps aux | grep repmgrd

# repmgr 설정 확인
docker exec postgres-slave cat /etc/repmgr.conf | grep -E "(promote_command|follow_command)"

# 수동 승격 테스트
docker exec postgres-slave su - postgres -c "repmgr -f /etc/repmgr.conf standby promote"

# 해결 방안: repmgrd 데몬 재시작
docker exec postgres-slave su - postgres -c "repmgrd -f /etc/repmgr.conf --daemonize"
```

### 3. 복제 지연 및 동기화 문제

#### 증상: Slave의 데이터가 Master와 동기화되지 않음
```bash
# 복제 상태 전체 점검
docker exec postgres-master psql -U postgres -c "
SELECT application_name, client_addr, state, sync_state, 
       pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS lag_bytes
FROM pg_stat_replication;"

# 복제 슬롯 확인
docker exec postgres-master psql -U postgres -c "SELECT * FROM pg_replication_slots;"

# WAL 송신 상태 확인
docker exec postgres-slave psql -U postgres -c "SELECT * FROM pg_stat_wal_receiver;"

# 해결 방안
# 1. 복제 재시작
docker exec postgres-slave su - postgres -c "pg_ctl reload"

# 2. 복제 슬롯 재생성 (심각한 경우)
docker exec postgres-master psql -U postgres -c "SELECT pg_drop_replication_slot('slave_slot');"
docker exec postgres-master psql -U postgres -c "SELECT pg_create_physical_replication_slot('slave_slot');"
```

### 4. HAProxy 백엔드 전환 문제

#### 증상: repmgr Failover 후 HAProxy가 새로운 Master를 인식하지 못함
```bash
# HAProxy 상태 확인
curl -u admin:admin123 http://localhost:8404/stats

# 백엔드 서버 헬스체크 로그 확인
docker-compose logs haproxy | grep -E "(check|health)"

# 수동 헬스체크 테스트
docker exec haproxy /usr/local/bin/health-check.sh postgres-master 5432
docker exec haproxy /usr/local/bin/health-check.sh postgres-slave 5432

# 해결 방안: HAProxy 설정 재로드
docker exec haproxy kill -USR2 1  # Graceful reload
```

### 5. 전체 클러스터 재설정 (최후 수단)

#### 모든 설정이 꼬인 경우 완전 재설정
```bash
# 1. 모든 컨테이너 중단 및 삭제
docker-compose down -v
docker system prune -f

# 2. 데이터 볼륨 삭제 (주의: 모든 데이터 손실)
docker volume rm $(docker volume ls -q | grep postgres)

# 3. 전체 재구축
docker-compose up -d

# 4. repmgr 초기화
./scripts/repmgr-setup.sh

# 5. 상태 확인
./scripts/repmgr-status.sh
```

## 성능 최적화 및 모범 사례

### 1. PostgreSQL 복제 최적화
```sql
-- postgresql.conf 권장 설정 (이미 적용됨)
wal_level = replica
max_wal_senders = 3
wal_keep_size = 1GB
shared_preload_libraries = 'repmgr'
track_commit_timestamp = on

-- 복제 성능 모니터링
SELECT slot_name, database, active, restart_lsn, 
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) as lag
FROM pg_replication_slots;
```

### 2. repmgr 모니터링 최적화
```bash
# 정기적인 클러스터 상태 체크 (cron 등록 권장)
# 매 5분마다 실행
*/5 * * * * /path/to/scripts/repmgr-status.sh >> /var/log/repmgr-monitor.log

# 복제 지연 알림 설정 (임계값: 10MB)
# 지연이 클 경우 알림 발송 로직 구현 가능
```

### 3. 백업 전략
```bash
# Master에서 정기 백업 (매일 새벽 2시)
0 2 * * * docker exec postgres-master pg_dump -U ramos -d ramos-test-db > /backup/daily_$(date +\%Y\%m\%d).sql

# WAL 아카이빙 설정 (재해 복구용)
# postgresql.conf에 추가 권장:
# archive_mode = on
# archive_command = 'cp %p /archive/%f'
```
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

#### 복제 슬롯 누락 문제 해결
Slave에서 "replication slot does not exist" 오류가 발생하는 경우:

```bash
# 1. Master에서 복제 슬롯 생성
docker exec postgres-master psql -U ramos -d ramos-test-db -c "
  SELECT pg_create_physical_replication_slot('slave_slot');
"

# 2. 복제 슬롯 생성 확인
docker exec postgres-master psql -U ramos -d ramos-test-db -c "
  SELECT slot_name, slot_type, active FROM pg_replication_slots;
"

# 3. Slave 재시작
docker-compose restart postgres-slave

# 4. 복제 상태 재확인 (약 10초 대기 후)
sleep 10
docker exec postgres-master psql -U ramos -d ramos-test-db -c "
  SELECT application_name, client_addr, state, sync_state FROM pg_stat_replication;
"
```

#### 사용자 권한 문제 ("role does not exist" 오류)
완전한 시스템 재초기화가 필요한 경우:

```bash
# 1. 모든 컨테이너와 볼륨 삭제 (주의: 모든 데이터 삭제됨)
docker-compose down -v

# 2. 시스템 재시작
docker-compose up -d

# 3. Master가 healthy 상태가 될 때까지 대기
docker-compose ps | grep postgres-master

# 4. 필요시 복제 슬롯 재생성 (위의 복제 슬롯 생성 단계 참조)
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

echo -e "\n복제 슬롯 상태:"
docker exec postgres-master psql -U ramos -d ramos-test-db -c "SELECT slot_name, slot_type, active FROM pg_replication_slots;"

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
- [ ] 복제 슬롯(`slave_slot`) 생성 및 활성화 확인
- [ ] VIP 할당 및 Failover 테스트
- [ ] HAProxy 로드밸런싱 동작 확인
- [ ] 애플리케이션 연결 테스트
