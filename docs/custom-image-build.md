# Houselab Nextcloud Custom Image

This repository owns the custom Nextcloud image source and GitLab CI/CD
publication flow for Docker Hub repository `rusman/nextcloud_cron_fmp`. The
Unraid deployment repository should consume only a published tag plus digest
and the CI manifest artifact from this project.

## Target

The selected production target is Nextcloud Server `34.0.0`.

Official source evidence checked on 2026-06-15:

- Nextcloud changelog lists `34.0.0`, dated 2026-06-09, as the latest
  Nextcloud 34 release.
- The release archive is
  `https://download.nextcloud.com/server/releases/nextcloud-34.0.0.tar.bz2`.
- The release checksum and PGP signature are verified by GitLab CI before image
  construction and again inside the CI image construction step.

The runtime base is `php:8.4-fpm-trixie`. Nextcloud latest documentation lists
PHP 8.2, 8.3, 8.4, and 8.5 as supported for the current release, with 8.2
deprecated. PHP 8.4 on Debian trixie matches current upstream Nextcloud Docker
practice while keeping a conservative stable runtime.

## Static Checks Only

Do not construct, run, publish, or verify image artifacts from a developer
checkout, and do not execute the CI helper scripts there. Work outside GitLab
CI is limited to source review and static formatting/syntax checks of
`34/fpm/Dockerfile`.

## GitLab CI/CD

The self-hosted GitLab project `hn583/nextcloud_docker` is the only place that
constructs and publishes the image. Configure Docker Hub credentials only as
GitLab CI/CD secret variables:

- `DOCKERHUB_USERNAME`
- `DOCKERHUB_TOKEN`

Do not commit Docker Hub credentials or runtime Nextcloud secrets.

The pipeline verifies the release checksum and PGP signature, constructs the FPM
image, runs smoke tests, logs in to Docker Hub, pushes all tags, verifies the
pushed digests, and writes `artifacts/nextcloud-image-manifest.yaml`.

Published tags:

- `rusman/nextcloud_cron_fmp:34.0.0`
- `rusman/nextcloud_cron_fmp:34.0.0-houselab.<git-sha>`
- `rusman/nextcloud_cron_fmp:34.0.0-houselab.<pipeline-id>`

`latest` is intentionally not used as a deployment selector.

## Manifest

CI publishes `artifacts/nextcloud-image-manifest.yaml` with the deployment
handoff fields required by the Unraid pipeline:

```yaml
image_repository: rusman/nextcloud_cron_fmp
image_tag: "34.0.0"
image_digest: "sha256:..."
nextcloud_version: "34.0.0"
source_project: "hn583/nextcloud_docker"
source_commit: "..."
dockerfile_path: "34/fpm/Dockerfile"
release_url: "https://download.nextcloud.com/server/releases/nextcloud-34.0.0.tar.bz2"
release_signature_verified: true
release_checksum_verified: true
smoke_tests_passed: true
published_at: "..."
ci_pipeline_url: "..."
```

## Customization Notes Compared With 26.0.13

Retained:

- FPM runtime with `/var/www/html` as the application root.
- `www-data` ownership expectations and upstream-style entrypoint sync.
- Busybox cron support via `/cron.sh` and a five-minute `cron.php` crontab.
- APCu per-process cache support and Redis extension/config for external Redis.
- PostgreSQL support via `pdo_pgsql` and PostgreSQL-only autoconfig.
- LDAP, imagick, GD, intl, zip, gmp, exif, pcntl, sysvsem, and opcache.
- Large upload/memory/opcache tuning from the custom 26.x image lineage.

Changed deliberately:

- Base image moved from the old 26.x PHP 8.2 lineage to
  `php:8.4-fpm-trixie`.
- MySQL support is not included in the custom 34 FPM image because the target
  deployment uses external PostgreSQL and the previous customization removed the
  MySQL install path.
- The memcached PHP extension is not included. The target deployment uses Redis
  and APCu; Nextcloud documentation describes memcached as an older alternative
  to Redis rather than the preferred new-installation cache.
- No Redis, memcached, MySQL, or PostgreSQL server daemon is bundled in the
  image. Databases and Redis remain external runtime services.

## Intermediate Major Upgrades

This task prepares only the latest approved image target. Production migration
from the current 26.x server cannot jump directly to 34.x. Intermediate
one-major images for 27.x through 33.x are still a prerequisite before
production migration, or the pipeline must be extended later to produce each
required maintenance major.
