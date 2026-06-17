# Houselab custom Nextcloud FPM image.
# Based on the existing rusman/nextcloud_cron_fmp lineage, updated for
# Nextcloud 34 with PostgreSQL/Redis/APCu support and no bundled database/cache
# daemons.
FROM php:8.4-fpm-trixie

ARG NEXTCLOUD_SHA256=""
ARG NEXTCLOUD_GPG_FINGERPRINT="28806A878AE423A28372792ED75899B9A724937A"

# entrypoint.sh and cron.sh dependencies
RUN set -ex; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        busybox-static \
        bzip2 \
        libldap-common \
        libmagickcore-7.q16-10-extra \
        rsync \
    ; \
    rm -rf /var/lib/apt/lists/*; \
    mkdir -p /var/spool/cron/crontabs; \
    echo '*/5 * * * * php -f /var/www/html/cron.php' > /var/spool/cron/crontabs/www-data

# install the PHP extensions we need
# see https://docs.nextcloud.com/server/latest/admin_manual/installation/php_configuration.html
ENV PHP_MEMORY_LIMIT=2024M
ENV PHP_UPLOAD_LIMIT=10240M
ENV POST_PHP_MAX_SIZE_LIMIT=10496M
ENV PHP_OPCACHE_MEMORY_CONSUMPTION=256
ENV PHP_OPCACHE_JIT_BUFFER_SIZE=256M

RUN set -ex; \
    savedAptMark="$(apt-mark showmanual)"; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libcurl4-openssl-dev \
        libevent-dev \
        libfreetype6-dev \
        libgmp-dev \
        libicu-dev \
        libjpeg-dev \
        libldap2-dev \
        libmagickwand-dev \
        libpng-dev \
        libpq-dev \
        libwebp-dev \
        libxml2-dev \
        libzip-dev \
    ; \
    debMultiarch="$(dpkg-architecture --query DEB_BUILD_MULTIARCH)"; \
    docker-php-ext-configure ftp --with-ftp-ssl; \
    docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
    docker-php-ext-configure ldap --with-libdir="lib/$debMultiarch"; \
    docker-php-ext-install -j "$(nproc)" \
        bcmath \
        exif \
        ftp \
        gd \
        gmp \
        intl \
        ldap \
        opcache \
        pcntl \
        pdo_pgsql \
        sysvsem \
        zip \
    ; \
    pecl install APCu-5.1.28; \
    pecl install imagick-3.8.1; \
    pecl install redis-6.3.0; \
    docker-php-ext-enable \
        apcu \
        imagick \
        redis \
    ; \
    rm -r /tmp/pear; \
    apt-mark auto '.*' > /dev/null; \
    apt-mark manual $savedAptMark; \
    ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
        | awk '/=>/ { so = $(NF-1); if (index(so, "/usr/local/") == 1) { next }; gsub("^/(usr/)?", "", so); print so }' \
        | sort -u \
        | xargs -r dpkg-query --search \
        | cut -d: -f1 \
        | sort -u \
        | xargs -rt apt-mark manual; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    rm -rf /var/lib/apt/lists/*

# set recommended PHP.ini settings
# see https://docs.nextcloud.com/server/latest/admin_manual/installation/server_tuning.html#enable-php-opcache
RUN { \
        echo 'opcache.enable=1'; \
        echo 'opcache.interned_strings_buffer=32'; \
        echo 'opcache.max_accelerated_files=10000'; \
        echo 'opcache.memory_consumption=${PHP_OPCACHE_MEMORY_CONSUMPTION}'; \
        echo 'opcache.save_comments=1'; \
        echo 'opcache.revalidate_freq=60'; \
        echo 'opcache.jit=1255'; \
        echo 'opcache.jit_buffer_size=${PHP_OPCACHE_JIT_BUFFER_SIZE}'; \
    } > "${PHP_INI_DIR}/conf.d/opcache-recommended.ini"; \
    echo 'apc.enable_cli=1' >> "${PHP_INI_DIR}/conf.d/docker-php-ext-apcu.ini"; \
    { \
        echo 'memory_limit=${PHP_MEMORY_LIMIT}'; \
        echo 'upload_max_filesize=${PHP_UPLOAD_LIMIT}'; \
        echo 'post_max_size=${POST_PHP_MAX_SIZE_LIMIT}'; \
    } > "${PHP_INI_DIR}/conf.d/nextcloud.ini"; \
    mkdir /var/www/data; \
    mkdir -p /docker-entrypoint-hooks.d/pre-installation \
             /docker-entrypoint-hooks.d/post-installation \
             /docker-entrypoint-hooks.d/pre-upgrade \
             /docker-entrypoint-hooks.d/post-upgrade \
             /docker-entrypoint-hooks.d/before-starting; \
    chown -R www-data:root /var/www; \
    chmod -R g=u /var/www

VOLUME /var/www/html

ENV NEXTCLOUD_VERSION=34.0.0

COPY release/nextcloud.tar.bz2 release/nextcloud.tar.bz2.asc release/nextcloud.tar.bz2.sha256 release/nextcloud.asc /tmp/nextcloud-release/

RUN set -ex; \
    fetchDeps=" \
        gnupg \
        dirmngr \
    "; \
    apt-get update; \
    apt-get install -y --no-install-recommends $fetchDeps; \
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
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false $fetchDeps; \
    rm -rf /var/lib/apt/lists/*

COPY *.sh upgrade.exclude /
COPY config/* /usr/src/nextcloud/config/

ENTRYPOINT ["/entrypoint.sh"]
CMD ["php-fpm"]
