FROM postgres:15

# Install repmgr (repmgrd 포함) 및 socat (HTTP 헬스 리스너용)
RUN apt-get update && \
    apt-get install -y postgresql-15-repmgr socat && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create log directory for repmgr
RUN mkdir -p /var/log/repmgr && \
    chown postgres:postgres /var/log/repmgr

# repmgr.conf 는 docker-compose 에서 volume 마운트한다 (수정 시 rebuild 불필요).

# Copy initialization scripts
COPY repmgr-init-master.sh /docker-entrypoint-initdb.d/99-repmgr-init.sh
RUN chmod +x /docker-entrypoint-initdb.d/99-repmgr-init.sh