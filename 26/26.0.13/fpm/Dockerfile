# DO NOT EDIT: created by update.sh from Dockerfile-debian.template
ARG NEXTCLOUD_PHP_RUNTIME_IMAGE=rusman/nextcloud_php_runtime:8.2-bookworm
FROM ${NEXTCLOUD_PHP_RUNTIME_IMAGE}

ENV NEXTCLOUD_VERSION 26.0.13

ARG NEXTCLOUD_SHA256=""
ARG NEXTCLOUD_GPG_FINGERPRINT="28806A878AE423A28372792ED75899B9A724937A"

COPY release/nextcloud.tar.bz2 release/nextcloud.tar.bz2.asc release/nextcloud.tar.bz2.sha256 release/nextcloud.asc /tmp/nextcloud-release/

RUN set -ex; \
    fetchDeps=" \
        gnupg \
        dirmngr \
    "; \
    apt-get update; \
    apt-get install -y --no-install-recommends $fetchDeps; \
    \
    cd /tmp/nextcloud-release; \
    if [ -n "$NEXTCLOUD_SHA256" ]; then \
        echo "$NEXTCLOUD_SHA256  nextcloud.tar.bz2" | sha256sum -c -; \
    else \
        checksum="$(awk '{ print $1; exit }' nextcloud.tar.bz2.sha256)"; \
        echo "$checksum  nextcloud.tar.bz2" | sha256sum -c -; \
    fi; \
    export GNUPGHOME="$(mktemp -d)"; \
    gpg --batch --import nextcloud.asc; \
    gpg --batch --list-keys --with-colons "$NEXTCLOUD_GPG_FINGERPRINT" \
        | awk -F: -v fpr="$NEXTCLOUD_GPG_FINGERPRINT" '$1 == "fpr" && $10 == fpr { found=1 } END { exit !found }'; \
    gpg --batch --verify nextcloud.tar.bz2.asc nextcloud.tar.bz2; \
    tar -xjf nextcloud.tar.bz2 -C /usr/src/; \
    gpgconf --kill all; \
    rm -rf "$GNUPGHOME"; \
    cd /; \
    rm -rf /tmp/nextcloud-release; \
    rm -rf /usr/src/nextcloud/updater; \
    mkdir -p /usr/src/nextcloud/data; \
    mkdir -p /usr/src/nextcloud/custom_apps; \
    chmod +x /usr/src/nextcloud/occ; \
    \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false $fetchDeps; \
    rm -rf /var/lib/apt/lists/*

COPY *.sh upgrade.exclude /
COPY config/* /usr/src/nextcloud/config/

ENTRYPOINT ["/entrypoint.sh"]
CMD ["php-fpm"]
