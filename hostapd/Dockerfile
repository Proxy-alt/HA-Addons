ARG BUILD_FROM
FROM ${BUILD_FROM}

ENV LANG=C.UTF-8

# hostapd's postinst tries to start the service via the init system, which
# doesn't exist during a Docker build. policy-rc.d tells it not to bother.
RUN \
    echo 'exit 101' > /usr/sbin/policy-rc.d \
    && chmod +x /usr/sbin/policy-rc.d \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        hostapd \
        iproute2 \
        rfkill \
        jq \
    && rm -rf /var/lib/apt/lists/*

COPY rootfs/run.sh /run.sh
RUN chmod +x /run.sh

CMD ["/run.sh"]
