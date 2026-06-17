#!/usr/bin/env bash
set -euo pipefail

image_ref="${IMAGE_REF:?IMAGE_REF is required}"
nextcloud_version="${NEXTCLOUD_VERSION:-34.0.0}"

docker run --rm --entrypoint sh \
    -e EXPECTED_NEXTCLOUD_VERSION="$nextcloud_version" \
    "$image_ref" \
    -eu -c '
php -v
php -m

require_module() {
    module="$1"
    pattern="^${module}$"
    if [ "$module" = "opcache" ]; then
        pattern="^Zend OPcache$|^opcache$"
    fi

    if ! php -m | grep -Eiq "$pattern"; then
        echo "Required PHP module is missing: $module" >&2
        exit 1
    fi
}

for module in \
    apcu \
    bcmath \
    exif \
    ftp \
    gd \
    gmp \
    imagick \
    intl \
    ldap \
    opcache \
    pcntl \
    pdo_pgsql \
    redis \
    sysvsem \
    zip
do
    require_module "$module"
done

for forbidden_module in \
    mysqli \
    pdo_mysql
do
    if php -m | grep -Eiq "^${forbidden_module}$"; then
        echo "${forbidden_module} is intentionally not part of this PostgreSQL-only image" >&2
        exit 1
    fi
done

for forbidden_command in \
    mariadbd \
    mysql \
    mysqld \
    pg_ctl \
    postgres \
    postmaster \
    redis-server
do
    if command -v "$forbidden_command" >/dev/null 2>&1; then
        echo "${forbidden_command} must not be bundled in this Nextcloud application image" >&2
        exit 1
    fi
done

if ! test -f /usr/src/nextcloud/version.php; then
    echo "Missing /usr/src/nextcloud/version.php" >&2
    exit 1
fi

actual_version="$(php -r "require '\''/usr/src/nextcloud/version.php'\''; echo \$OC_VersionString;")"
actual_internal_version="$(php -r "require '\''/usr/src/nextcloud/version.php'\''; echo implode('\''.'\'', \$OC_Version);")"
echo "Nextcloud release version: ${actual_version}; internal version: ${actual_internal_version}; expected release: ${EXPECTED_NEXTCLOUD_VERSION}"
if [ "$actual_version" != "$EXPECTED_NEXTCLOUD_VERSION" ]; then
    echo "Nextcloud release version mismatch: expected ${EXPECTED_NEXTCLOUD_VERSION}, got ${actual_version}" >&2
    exit 1
fi

find /usr/src/nextcloud/config -maxdepth 1 -name "*.php" -print -exec php -l {} \;

if ! test -x /entrypoint.sh; then
    echo "Missing executable /entrypoint.sh" >&2
    exit 1
fi
if ! test -x /cron.sh; then
    echo "Missing executable /cron.sh" >&2
    exit 1
fi
if ! test -f /var/spool/cron/crontabs/www-data; then
    echo "Missing www-data crontab" >&2
    exit 1
fi
if ! grep -q "cron.php" /var/spool/cron/crontabs/www-data; then
    echo "www-data crontab does not run cron.php" >&2
    exit 1
fi
'
