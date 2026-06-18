ARG NEXTCLOUD_PHP_RUNTIME_IMAGE=rusman/nextcloud_php_runtime:8.2-bookworm
FROM ${NEXTCLOUD_PHP_RUNTIME_IMAGE}

RUN set -ex; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        dirmngr \
        gnupg \
    ; \
    rm -rf /var/lib/apt/lists/*

COPY verify-nextcloud-release.sh /usr/local/bin/verify-nextcloud-release

RUN chmod +x /usr/local/bin/verify-nextcloud-release
