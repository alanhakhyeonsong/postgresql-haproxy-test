#!/bin/bash
# entrypoint.sh (master) - PostgreSQL 을 PID1 로 띄우면서
# 백그라운드에서 repmgr 자동 등록 + repmgrd 데몬 기동 + HTTP 헬스서버를 실행한다.
#
# 추가: 구 primary 자동 재합류
#   master 가 죽은 사이 slave 가 primary 로 승격된 상태에서 master 가 다시 뜨면(split-brain 방지),
#   새 primary(slave) 기준으로 pg_rewind(실패 시 base backup)하여 standby 로 재합류한다.
set -e

DATADIR=/var/lib/postgresql/data
NEW_PRIMARY=postgres-slave
REJOINED=0

# 재기동(데이터 존재)이고, 그 사이 slave 가 primary 로 승격됐다면 구 primary 자동 재합류
if [ -s "$DATADIR/PG_VERSION" ]; then
  slave_role=$(PGPASSWORD=repmgr_password psql -h "$NEW_PRIMARY" -p 5432 -U repmgr -d repmgr \
    -tAc "SELECT pg_is_in_recovery();" 2>/dev/null | tr -d '[:space:]')
  if [ "$slave_role" = "f" ]; then
    echo "[entrypoint] 구 primary 감지: '$NEW_PRIMARY' 가 현재 primary -> 자동 재합류 시작"

    # 새 primary 에 master 재합류용 영구 slot 생성 (없으면)
    PGPASSWORD=repmgr_password psql -h "$NEW_PRIMARY" -p 5432 -U repmgr -d repmgr -tAc \
      "SELECT pg_create_physical_replication_slot('master_slot') WHERE NOT EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name='master_slot');" \
      >/dev/null 2>&1 || true

    # 1) pg_rewind 우선 시도 (wal_log_hints=on 이라 가능, 빠름)
    if su postgres -c "PGPASSWORD=repmgr_password pg_rewind --target-pgdata='$DATADIR' --source-server='host=$NEW_PRIMARY port=5432 user=repmgr dbname=repmgr password=repmgr_password'" 2>&1; then
      echo "[entrypoint] pg_rewind 성공"
    else
      # 2) 실패하면 base backup 으로 폴백 (항상 동작)
      echo "[entrypoint] pg_rewind 실패 -> base backup 으로 재구성"
      rm -rf "$DATADIR"/*
      PGPASSWORD=replicator_password pg_basebackup \
        -h "$NEW_PRIMARY" -D "$DATADIR" -U replicator -v -P -R
    fi

    # standby 로 전환 설정
    touch "$DATADIR/standby.signal"
    cat >> "$DATADIR/postgresql.auto.conf" <<EOF
primary_conninfo = 'host=$NEW_PRIMARY port=5432 user=replicator password=replicator_password application_name=postgres-master'
primary_slot_name = 'master_slot'
EOF
    chown -R postgres:postgres "$DATADIR"
    chmod 700 "$DATADIR"
    REJOINED=1
    echo "[entrypoint] 구 primary 를 '$NEW_PRIMARY' 의 standby 로 재구성 완료"
  fi
fi

(
  until pg_isready -h 127.0.0.1 -p 5432 -U ramos -d ramos-test-db -q; do
    sleep 2
  done
  sleep 3

  if [ "$REJOINED" = "1" ]; then
    # 재합류한 경우: 자기 노드 레코드가 새 primary 로부터 복제될 때까지 대기 후 standby 로 등록
    until PGPASSWORD=repmgr_password psql -h 127.0.0.1 -U repmgr -d repmgr \
        -tAc "SELECT 1 FROM repmgr.nodes WHERE node_id=1" 2>/dev/null | grep -q 1; do
      sleep 2
    done
    echo "[entrypoint] (rejoin) registering as standby..."
    su postgres -c "repmgr -f /etc/repmgr.conf standby register --force" \
      || echo "[entrypoint] standby register failed (continuing)"
  else
    echo "[entrypoint] registering primary with repmgr..."
    su postgres -c "repmgr -f /etc/repmgr.conf primary register --force" \
      || echo "[entrypoint] primary register failed (continuing)"
  fi

  if ! pgrep -x repmgrd >/dev/null 2>&1; then
    echo "[entrypoint] starting repmgrd..."
    su postgres -c "repmgrd -f /etc/repmgr.conf --daemonize --pid-file=/tmp/repmgrd.pid" \
      || echo "[entrypoint] repmgrd start failed"
  fi

  echo "[entrypoint] starting health server on :8008..."
  /usr/local/bin/health-server.sh
) &

exec docker-entrypoint.sh postgres \
  -c config_file=/etc/postgresql/postgresql.conf \
  -c hba_file=/etc/postgresql/pg_hba.conf
