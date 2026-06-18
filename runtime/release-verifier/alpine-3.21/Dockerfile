FROM alpine:3.21

RUN set -ex; \
    apk add --no-cache \
        bash \
        bzip2 \
        gnupg \
        tar

COPY verify-nextcloud-release.sh /usr/local/bin/verify-nextcloud-release

RUN chmod +x /usr/local/bin/verify-nextcloud-release
