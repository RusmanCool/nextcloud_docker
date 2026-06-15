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
    if [ "$module" = "opcache" ]; then
        php -m | grep -Eiq "^Zend OPcache$|^opcache$"
    else
        php -m | grep -Eiq "^${module}$"
    fi
done

if php -m | grep -Eiq "^pdo_mysql$"; then
    echo "pdo_mysql is intentionally not part of this PostgreSQL-only image" >&2
    exit 1
fi

test -f /usr/src/nextcloud/version.php
actual_version="$(php -r '\''require "/usr/src/nextcloud/version.php"; echo implode(".", $OC_Version);'\'')"
test "$actual_version" = "$EXPECTED_NEXTCLOUD_VERSION"

find /usr/src/nextcloud/config -maxdepth 1 -name "*.php" -print -exec php -l {} \;

test -x /entrypoint.sh
test -x /cron.sh
test -f /var/spool/cron/crontabs/www-data
grep -q "cron.php" /var/spool/cron/crontabs/www-data
'
