# DO NOT EDIT: created by update.sh from Dockerfile-debian.template
ARG NEXTCLOUD_PHP_RUNTIME_IMAGE=rusman/nextcloud_php_runtime:8.2-bookworm
ARG NEXTCLOUD_RELEASE_VERIFIER_IMAGE=rusman/nextcloud_release_verifier:alpine-3.21
FROM ${NEXTCLOUD_RELEASE_VERIFIER_IMAGE} AS nextcloud-release-verifier

ARG NEXTCLOUD_SHA256=""
ARG NEXTCLOUD_GPG_FINGERPRINT="28806A878AE423A28372792ED75899B9A724937A"

COPY release/nextcloud.tar.bz2 release/nextcloud.tar.bz2.asc release/nextcloud.tar.bz2.sha256 release/nextcloud.asc /tmp/nextcloud-release/

RUN verify-nextcloud-release /tmp/nextcloud-release /usr/src; \
    rm -rf /tmp/nextcloud-release

FROM ${NEXTCLOUD_PHP_RUNTIME_IMAGE}

ENV NEXTCLOUD_VERSION 26.0.13

COPY --from=nextcloud-release-verifier /usr/src/nextcloud /usr/src/nextcloud

COPY *.sh upgrade.exclude /
COPY config/* /usr/src/nextcloud/config/

ENTRYPOINT ["/entrypoint.sh"]
CMD ["php-fpm"]
