#!/bin/bash
# entrypoint.sh (slave) - 첫 기동 시 master 로부터 base backup 으로 standby 를 구성하고,
# PostgreSQL 을 PID1 로 띄우면서 백그라운드에서 repmgr standby 자동 등록 + repmgrd(자동 failover) 데몬
# + HTTP 헬스서버를 실행한다.
set -e

# 첫 기동 시에만 base backup 으로 standby 초기화 (이미 데이터가 있으면 건너뜀)
if [ ! -s "/var/lib/postgresql/data/PG_VERSION" ]; then
  echo "[entrypoint] waiting for master..."
  until PGPASSWORD=ramostest123 pg_isready -h postgres-master -p 5432 -U ramos -d ramos-test-db -q; do
    echo "[entrypoint] master not ready, waiting..."
    sleep 3
  done
  echo "[entrypoint] master ready, creating base backup..."

  rm -rf /var/lib/postgresql/data/*
  # -C -S slave_slot: 백업 시작 시 master 에 영구 replication slot 을 생성한다.
  # 이게 없으면 standby 가 존재하지 않는 slot 으로 접속을 시도해 streaming 이 시작되지 않는다.
  PGPASSWORD=replicator_password pg_basebackup \
    -h postgres-master \
    -D /var/lib/postgresql/data \
    -U replicator \
    -v -P -R \
    -C -S slave_slot

  touch /var/lib/postgresql/data/standby.signal

  # primary_conninfo / primary_slot_name 은 -R 이 자동 기록하지만, 명시적으로 한 번 더 보장한다.
  cat >> /var/lib/postgresql/data/postgresql.auto.conf <<EOF
primary_conninfo = 'host=postgres-master port=5432 user=replicator password=replicator_password application_name=postgres-slave'
primary_slot_name = 'slave_slot'
EOF

  chown -R postgres:postgres /var/lib/postgresql/data
  chmod 700 /var/lib/postgresql/data
  echo "[entrypoint] standby setup completed"
fi

(
  # PostgreSQL(standby) 이 응답할 때까지 대기
  until pg_isready -h 127.0.0.1 -p 5432 -U ramos -d ramos-test-db -q; do
    sleep 2
  done
  sleep 3

  # primary 가 repmgr 에 먼저 등록돼야 standby register 가 가능 → primary 등록 대기
  until PGPASSWORD=repmgr_password psql -h postgres-master -p 5432 -U repmgr -d repmgr \
      -tAc "SELECT 1 FROM repmgr.nodes WHERE type='primary'" 2>/dev/null | grep -q 1; do
    echo "[entrypoint] waiting for primary to register in repmgr..."
    sleep 3
  done

  echo "[entrypoint] registering standby with repmgr..."
  su postgres -c "repmgr -f /etc/repmgr.conf standby register --force" \
    || echo "[entrypoint] standby register failed (continuing)"

  # standby register 는 primary DB 에 기록되며, streaming 복제로 standby 로컬에 도달해야 한다.
  # repmgrd 는 자기 노드 레코드를 로컬에서 찾으므로, 복제될 때까지 기다린 뒤 데몬을 띄운다.
  echo "[entrypoint] waiting for own node record (id=2) to replicate..."
  until PGPASSWORD=repmgr_password psql -h 127.0.0.1 -U repmgr -d repmgr \
      -tAc "SELECT 1 FROM repmgr.nodes WHERE node_id=2" 2>/dev/null | grep -q 1; do
    sleep 2
  done

  if ! pgrep -x repmgrd >/dev/null 2>&1; then
    echo "[entrypoint] starting repmgrd (failover=automatic)..."
    su postgres -c "repmgrd -f /etc/repmgr.conf --daemonize --pid-file=/tmp/repmgrd.pid" \
      || echo "[entrypoint] repmgrd start failed"
  fi

  echo "[entrypoint] starting health server on :8008..."
  /usr/local/bin/health-server.sh
) &

exec docker-entrypoint.sh postgres \
  -c config_file=/etc/postgresql/postgresql.conf \
  -c hba_file=/etc/postgresql/pg_hba.conf
