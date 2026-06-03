#!/bin/bash
# health-server.sh - socat 기반 경량 HTTP 헬스 리스너 (포트 8008)
#
# 중요: 매 연결마다 psql 을 fork 하면, socat 이 연결 종료 시 그 psql(및 자식)을 SIGTERM 으로 죽이면서
# PostgreSQL 백엔드가 exit 143 으로 비정상 종료 -> postmaster 전체 crash recovery 를 유발한다.
# 이를 피하기 위해 백그라운드 루프가 1초마다 역할을 파일에 캐시하고, socat 핸들러(pg-health.sh)는
# psql 없이 그 파일만 읽어 응답한다. (psql 을 socat child 프로세스 트리에서 분리)

ROLE_FILE=/tmp/pg_role

# 역할 캐시 갱신 루프 (psql 은 이 루프에서만, socat 과 무관하게 실행)
(
  while true; do
    r=$(PGPASSWORD=ramostest123 psql -h 127.0.0.1 -p 5432 -U ramos -d ramos-test-db \
      -tAc "SELECT pg_is_in_recovery();" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$r" ]; then
      printf '%s' "$r" > "${ROLE_FILE}.tmp" && mv "${ROLE_FILE}.tmp" "$ROLE_FILE"
    fi
    sleep 1
  done
) &

exec socat -T5 TCP-LISTEN:8008,reuseaddr,fork SYSTEM:'/usr/local/bin/pg-health.sh'
