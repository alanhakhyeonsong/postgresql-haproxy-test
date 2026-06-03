#!/bin/sh
# check_haproxy.sh - keepalived VRRP track 스크립트
# 자기 짝 HAProxy(stats:8080)가 살아있는지 확인한다. 실패하면 non-zero 를 반환하고,
# keepalived 가 priority 를 낮춰(weight -2) VIP 를 다른 노드로 넘긴다.
# HAPROXY_HOST 는 컨테이너 환경변수로 자기 HAProxy 주소를 받는다.

HAPROXY_HOST="${HAPROXY_HOST:-172.20.0.20}"
HAPROXY_STATS_PORT="${HAPROXY_STATS_PORT:-8080}"

# osixia/keepalived(alpine) 에 포함된 busybox wget 사용. 응답 실패 시 non-zero.
wget -q -T 2 -O /dev/null "http://${HAPROXY_HOST}:${HAPROXY_STATS_PORT}/stats" 2>/dev/null
exit $?
