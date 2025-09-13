FROM postgres:15

# Install repmgr
RUN apt-get update && \
    apt-get install -y postgresql-15-repmgr && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create log directory for repmgr
RUN mkdir -p /var/log/repmgr && \
    chown postgres:postgres /var/log/repmgr

# Copy repmgr configuration
COPY repmgr.conf /etc/repmgr.conf
RUN chown postgres:postgres /etc/repmgr.conf && \
    chmod 600 /etc/repmgr.conf

# Copy initialization scripts
COPY repmgr-init-master.sh /docker-entrypoint-initdb.d/99-repmgr-init.sh
RUN chmod +x /docker-entrypoint-initdb.d/99-repmgr-init.sh