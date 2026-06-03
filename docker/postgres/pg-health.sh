#!/bin/bash
# pg-health.sh - HAProxy HTTP 헬스체크 응답기 (socat 핸들러)
# 현재 노드가 primary 면 200, standby 면 503 을 반환한다.
# psql 을 직접 실행하지 않고, health-server.sh 의 백그라운드 루프가 캐시한 역할 파일만 읽는다.
# (psql 을 socat child 트리에서 분리하여 PostgreSQL 백엔드 SIGTERM crash 를 방지)
# failover 로 standby 가 promote 되면 캐시값이 t -> f 로 바뀌어 자동으로 200 을 반환한다.

ROLE_FILE=/tmp/pg_role
recovery=$(cat "$ROLE_FILE" 2>/dev/null | tr -d '[:space:]')

if [ "$recovery" = "f" ]; then
  status="200 OK"
  body="primary"
elif [ "$recovery" = "t" ]; then
  status="503 Service Unavailable"
  body="standby"
else
  status="503 Service Unavailable"
  body="unknown"
fi

len=${#body}
printf 'HTTP/1.1 %s\r\nContent-Type: text/plain\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s' \
  "$status" "$len" "$body"
