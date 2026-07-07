ARG BUILD_FROM
FROM ${BUILD_FROM}

ENV LANG=C.UTF-8 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_BREAK_SYSTEM_PACKAGES=1

# cync-lan has no tagged releases yet, so a specific upstream commit on the
# "python" branch (its default branch) is pinned here for reproducible builds.
ARG CYNC_LAN_REF="90697b76b1159279f4edbf135f79a292f502cebf"

RUN \
    apt-get update \
    && apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        git \
        openssl \
        jq \
        curl \
    && git clone https://github.com/baudneo/cync-lan.git /tmp/cync-lan \
    && git -C /tmp/cync-lan checkout "${CYNC_LAN_REF}" \
    && pip install --no-cache-dir /tmp/cync-lan \
    && mkdir -p /root/cync-lan/www \
    && cp -r /tmp/cync-lan/static/. /root/cync-lan/www/ \
    && rm -rf /tmp/cync-lan \
    && apt-get purge -y --auto-remove git \
    && rm -rf /var/lib/apt/lists/*

COPY rootfs/run.sh /run.sh
RUN chmod +x /run.sh

CMD ["/run.sh"]
