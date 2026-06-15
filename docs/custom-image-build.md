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
CI is limited to source review and static formatting/syntax checks, such as
shell syntax checks or whitespace checks. Docker image construction and smoke
testing belong only in GitLab CI.

## GitLab CI/CD

The self-hosted GitLab project `hn583/nextcloud_docker` is the only place that
constructs and publishes the image. Configure Docker Hub credentials only as
GitLab CI/CD secret variables:

- `DOCKERHUB_USERNAME`
- `DOCKERHUB_TOKEN`

Do not commit Docker Hub credentials or runtime Nextcloud secrets.

Pipelines are manual-only. A Git push, merge request event, schedule, API call,
or parent pipeline must not create a pipeline. Start validation or publishing
from GitLab's UI:

1. Open `hn583/nextcloud_docker`.
2. Go to `Build > Pipelines > Run pipeline`.
3. Select the branch or tag with GitLab's built-in ref dropdown.
4. Set trigger-time variables.
5. Start the pipeline.

The selected GitLab ref is the source of truth. Do not use a separate
script-level branch checkout or a `BRANCH_TO_USE` variable for normal
operation.

Trigger-time variables:

- `PUBLISH_IMAGE`
  - Default: `false`
  - Set to `true` only when Docker Hub publishing is approved for this run.
- `IMAGE_TAG`
  - Default: `34.0.0`
  - Plain Docker Hub release tag used only when publishing.
- `PUBLISH_IMMUTABLE_TAGS`
  - Default: `true`
  - When `true`, also publishes trace tags with the pipeline ID and commit SHA.

With `PUBLISH_IMAGE=false`, CI verifies the release checksum and PGP signature,
constructs the image, runs smoke tests, and writes the validation artifact
`artifacts/nextcloud-image-validation.yaml`. It does not require Docker Hub
credentials, log in to Docker Hub, push tags, or write a production deployment
manifest.

With `PUBLISH_IMAGE=true`, CI performs the same validation first. Only after
validation passes, the gated publish job requires Docker Hub credentials, pushes
approved tags, verifies that pushed tags resolve to the same digest, and writes
`artifacts/nextcloud-image-manifest.yaml` with the real Docker Hub digest.

Published tags:

- `rusman/nextcloud_cron_fmp:34.0.0`
- `rusman/nextcloud_cron_fmp:34.0.0-houselab.<git-sha>` when
  `PUBLISH_IMMUTABLE_TAGS=true`
- `rusman/nextcloud_cron_fmp:34.0.0-houselab.<pipeline-id>` when
  `PUBLISH_IMMUTABLE_TAGS=true`

`latest` is intentionally not used as a deployment selector.

The current CI targets a protected Docker-socket image-build runner with tag
`homenas-docker-image-build`. The runner job container must have
`/var/run/docker.sock` mounted so the Docker CLI in the job can use the host
Docker daemon. The image layers and build cache are stored by the host Docker
daemon, not inside the GitLab job container.

The runner was created under the GitLab group path `homenas`. Confirm that the
`hn583/nextcloud_docker` project can use that group runner, or move/enable the
runner at the correct GitLab scope before starting a pipeline.

## Manifest

Validation-only runs publish `artifacts/nextcloud-image-validation.yaml` with
`published: false` and `image_digest: null`. This file is not a production
deployment manifest and must not be consumed by the Unraid deployment pipeline.

Publishing runs publish `artifacts/nextcloud-image-manifest.yaml` with the
deployment handoff fields required by the Unraid pipeline:

```yaml
published: true
image_repository: rusman/nextcloud_cron_fmp
image_tag: "34.0.0"
image_digest: "sha256:..."
nextcloud_version: "34.0.0"
source_project: "hn583/nextcloud_docker"
source_commit: "..."
source_ref: "..."
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

This task prepares only the current approved image target. Production migration
from the current 26.x server cannot jump directly to 34.x. Intermediate
one-major images for 27.x through 33.x are still a prerequisite before
production migration, or the pipeline must be extended later to produce each
required maintenance major.
