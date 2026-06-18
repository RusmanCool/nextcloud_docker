# Nextcloud 26 to 34 Researched Upgrade Plan

Research date: 2026-06-17

Status: operator plan only. Do not run against production until each QA step,
backup gate, restore-test gate, image manifest, and operator approval gate in
this document has passed.

## Scope

This repository owns the custom Nextcloud application image, GitLab CI image
pipeline, smoke tests, Docker Hub publishing, digest verification, and QA/PROD
image manifests for `rusman/nextcloud_cron_fmp`.

The deployment/IaC repository owns Compose/Ansible, host volume mounts,
PostgreSQL/Redis runtime bindings, QA/PROD runtime separation, and secrets. Do
not modify the deployment repository from this image repository unless the
operator explicitly asks for that repository switch.

The approved target for this workstream is Nextcloud 34.0.0. Official docs now
show Nextcloud 35 as latest and Nextcloud 34 as stable, so this plan treats
34.0.0 as the approved target, not as a moving "latest" selector.

## Official Sources

- Upgrade policy:
  https://docs.nextcloud.com/server/stable/admin_manual/maintenance/upgrade.html
- Nextcloud 34 system requirements:
  https://docs.nextcloud.com/server/stable/admin_manual/installation/system_requirements.html
- PostgreSQL configuration:
  https://docs.nextcloud.com/server/stable/admin_manual/configuration_database/linux_database_configuration.html
- Redis/cache configuration:
  https://docs.nextcloud.com/server/stable/admin_manual/configuration_server/caching_configuration.html
- Critical changes index:
  https://docs.nextcloud.com/server/stable/admin_manual/release_notes/index.html
- Changelog:
  https://nextcloud.com/changelog/
- Release artifacts:
  https://download.nextcloud.com/server/releases/

Archived official system-requirement pages checked:

- https://docs.nextcloud.com/server/26/admin_manual/installation/system_requirements.html
- https://docs.nextcloud.com/server/27/admin_manual/installation/system_requirements.html
- https://docs.nextcloud.com/server/28/admin_manual/installation/system_requirements.html
- https://docs.nextcloud.com/server/29/admin_manual/installation/system_requirements.html
- https://docs.nextcloud.com/server/30/admin_manual/installation/system_requirements.html
- https://docs.nextcloud.com/server/31/admin_manual/installation/system_requirements.html
- https://docs.nextcloud.com/server/32/admin_manual/installation/system_requirements.html
- https://docs.nextcloud.com/server/33/admin_manual/installation/system_requirements.html

## Upgrade Policy Finding

Official Nextcloud documentation does not support skipping major versions for
this migration.

The official upgrade manual says the server must be upgraded step by step:
first upgrade to the latest point release of the currently installed major,
then run the upgrade again to move to the next major's latest point release.
It explicitly says major releases cannot be skipped and gives an example of
walking each major in order.

The reason is not only packaging policy. The same upgrade page says background
migrations may be scheduled after a major upgrade and must execute before the
next major starts. The manual also describes long-running database layout work
that is intentionally left for administrators to run after the normal upgrade:
`occ db:add-missing-columns`, `occ db:add-missing-indices`, and
`occ db:add-missing-primary-keys`. The upgrade prerequisite section also
requires reviewing critical changes and third-party app compatibility before
major upgrades.

No official exception was found for:

- Docker/container deployments.
- Production deployments with existing users, files, shares, calendars,
  contacts, app passwords, third-party apps, or 2FA.
- Any of these candidate jumps: `26 -> 28`, `28 -> 30`, `30 -> 32`,
  `32 -> 34`, or `26 -> 34`.

Container deployment does not change the version policy. The stable upgrade
manual says Docker users should follow the installation-method instructions for
the mechanics, but the documented version path remains one major at a time.
This image repo's `34/fpm/entrypoint.sh` also exits if the image major is more
than one major ahead of the installed application version. That script is local
supporting evidence; the official docs are the authority.

## Required Path

Use this path unless a later official Nextcloud source explicitly documents an
exception for this exact deployment:

```text
26.0.0 -> 26.0.13 -> 27.1.11 -> 28.0.14 -> 29.0.16 -> 30.0.17 -> 31.0.14 -> 32.0.11 -> 33.0.5 -> 34.0.0
```

Live production was reported by the operator on 2026-06-17 as:

```text
docker exec -u www-data -it nextcloud_server php occ status --output=json
{"installed":true,"version":"26.0.0.11","versionstring":"26.0.0","edition":"","maintenance":false,"needsDbUpgrade":false,"productname":"Nextcloud","extendedSupport":false}
```

That confirms the assumed starting major, but it also confirms production is
below the latest 26 point release. The first upgrade task is therefore a
same-major upgrade from 26.0.0 to 26.0.13, including QA, backup, restore-test,
and acceptance gates, before starting `26.0.13 -> 27.1.11`. Re-run
`occ status --output=json` immediately before the maintenance window; if it no
longer matches this 26.0.0 starting point, stop and update this plan.

## Version Matrix

The latest point releases below were computed from the official releases
directory on 2026-06-17. The changelog currently exposes artifact sections for
32.0.11, 33.0.5, and 34.0.0; older EOL release artifacts are still present in
the official releases directory.

| Major | Latest point | Release URL | SHA256 URL | Signature URL | PHP runtime support | PostgreSQL support | Critical changes to account for |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 26 | 26.0.13 | https://download.nextcloud.com/server/releases/nextcloud-26.0.13.tar.bz2 | https://download.nextcloud.com/server/releases/nextcloud-26.0.13.tar.bz2.sha256 | https://download.nextcloud.com/server/releases/nextcloud-26.0.13.tar.bz2.asc | 8.0, 8.1 recommended, 8.2 | 10/11/12/13/14/15 | PHP 8.2 supported, PHP 7.4 removed, mailer behavior changed, DAV sync token retention, nginx config changed. |
| 27 | 27.1.11 | https://download.nextcloud.com/server/releases/nextcloud-27.1.11.tar.bz2 | https://download.nextcloud.com/server/releases/nextcloud-27.1.11.tar.bz2.sha256 | https://download.nextcloud.com/server/releases/nextcloud-27.1.11.tar.bz2.asc | 8.0 deprecated, 8.1, 8.2 recommended | 10/11/12/13/14/15 | PHP 8.2 recommended, system address book exposure, nginx static asset list changed for `.mjs`, `.ogg`, and `.flac`. |
| 28 | 28.0.14 | https://download.nextcloud.com/server/releases/nextcloud-28.0.14.tar.bz2 | https://download.nextcloud.com/server/releases/nextcloud-28.0.14.tar.bz2.sha256 | https://download.nextcloud.com/server/releases/nextcloud-28.0.14.tar.bz2.asc | 8.0 deprecated, 8.1, 8.2 recommended, 8.3 | 10/11/12/13/14/15 | Setup checks move server-side; verify `trusted_domains`, `overwrite.cli.url`, DNS, firewall, and container networking. Monitoring app-update behavior changed. Office preview behavior changed. |
| 29 | 29.0.16 | https://download.nextcloud.com/server/releases/nextcloud-29.0.16.tar.bz2 | https://download.nextcloud.com/server/releases/nextcloud-29.0.16.tar.bz2.sha256 | https://download.nextcloud.com/server/releases/nextcloud-29.0.16.tar.bz2.asc | 8.0 deprecated, 8.1, 8.2 recommended, 8.3 | 10/11/12/13/14/15/16 | No dedicated `upgrade_to_29` page is listed in the current stable critical-changes index. Re-check archived 29 release notes and admin overview in QA before PROD. |
| 30 | 30.0.17 | https://download.nextcloud.com/server/releases/nextcloud-30.0.17.tar.bz2 | https://download.nextcloud.com/server/releases/nextcloud-30.0.17.tar.bz2.sha256 | https://download.nextcloud.com/server/releases/nextcloud-30.0.17.tar.bz2.asc | 8.1 deprecated, 8.2, 8.3 recommended | 12/13/14/15/16 | PHP 8.0 removed; PostgreSQL 9.4 removed; MariaDB 10.3/10.5 removed; serve `.webp`; config keys for forbidden filenames changed; app passwords may be cleaned up; AppAPI enabled by default. |
| 31 | 31.0.14 | https://download.nextcloud.com/server/releases/nextcloud-31.0.14.tar.bz2 | https://download.nextcloud.com/server/releases/nextcloud-31.0.14.tar.bz2.sha256 | https://download.nextcloud.com/server/releases/nextcloud-31.0.14.tar.bz2.asc | 8.1 deprecated, 8.2, 8.3 recommended, 8.4 | 13/14/15/16/17 | PHP 8.4 supported; MySQL/MariaDB row-format warning more prominent; APCu memory setup warning; upload chunk-size config moved; AppAPI default app. |
| 32 | 32.0.11 | https://download.nextcloud.com/server/releases/nextcloud-32.0.11.tar.bz2 | https://download.nextcloud.com/server/releases/nextcloud-32.0.11.tar.bz2.sha256 | https://download.nextcloud.com/server/releases/nextcloud-32.0.11.tar.bz2.asc | 8.1 deprecated, 8.2, 8.3 recommended, 8.4 | 13/14/15/16/17 | PHP 8.4 supported; remove `X-XSS-Protection` expectations; system address book may be disabled over user-count threshold; AppAPI setup checks expanded; S3 checksum behavior changes. |
| 33 | 33.0.5 | https://download.nextcloud.com/server/releases/nextcloud-33.0.5.tar.bz2 | https://download.nextcloud.com/server/releases/nextcloud-33.0.5.tar.bz2.sha256 | https://download.nextcloud.com/server/releases/nextcloud-33.0.5.tar.bz2.asc | 8.2 deprecated, 8.3, 8.4 recommended, 8.5 | 14/15/16/17/18 | PHP 8.1 removed; PostgreSQL 13 removed; Oracle 11g removed; `connectivity.nextcloud.com`; Snowflake server ID config; `/metrics`; outbound user-agent change. |
| 34 | 34.0.0 | https://download.nextcloud.com/server/releases/nextcloud-34.0.0.tar.bz2 | https://download.nextcloud.com/server/releases/nextcloud-34.0.0.tar.bz2.sha256 | https://download.nextcloud.com/server/releases/nextcloud-34.0.0.tar.bz2.asc | 8.2 deprecated, 8.3, 8.4, 8.5 recommended | 14/15/16/17/18 | No dedicated `upgrade_to_34` page was found at the expected current/latest docs path on 2026-06-17. Use the official 34.0.0 changelog, 34 system requirements, and QA/admin setup checks as the final-step critical-change gate. |

PostgreSQL 14 is inside every official PostgreSQL support window above. If
live PostgreSQL is not major 14, stop and re-evaluate the database path before
any app upgrade.

## Major-Skip Decision Report

All skip candidates are rejected unless a future official Nextcloud source
explicitly documents that exact path.

```yaml
candidate_path: "26 -> 28"
officially_supported: no
official_source: "https://docs.nextcloud.com/server/stable/admin_manual/maintenance/upgrade.html"
official_wording_summary: "Nextcloud must upgrade step by step; upgrade to the latest point release of the current major, then to the next major's latest point release; major releases cannot be skipped."
applies_to_container_deployment: no
applies_to_existing_production_data: no
requires_latest_source_major_point_release: yes
requires_latest_target_major_point_release: yes
requires_background_migrations_before_next_step: yes
known_risks: "Skipped schema, background, app, config, file-cache, and shipped-app migrations; unsupported rollback boundary; entrypoint rejects jumps greater than one major."
required_QA_tests: "No skip QA is approved. Test 26.0.13 -> 27.1.11, complete migrations, then test 27.1.11 -> 28.0.14."
decision: reject
```

```yaml
candidate_path: "28 -> 30"
officially_supported: no
official_source: "https://docs.nextcloud.com/server/stable/admin_manual/maintenance/upgrade.html"
official_wording_summary: "No major skipping; the 29 major must be installed before 30."
applies_to_container_deployment: no
applies_to_existing_production_data: no
requires_latest_source_major_point_release: yes
requires_latest_target_major_point_release: yes
requires_background_migrations_before_next_step: yes
known_risks: "Skips the 29 application and database migration boundary and app compatibility checks."
required_QA_tests: "No skip QA is approved. Test 28.0.14 -> 29.0.16, complete migrations, then test 29.0.16 -> 30.0.17."
decision: reject
```

```yaml
candidate_path: "30 -> 32"
officially_supported: no
official_source: "https://docs.nextcloud.com/server/stable/admin_manual/maintenance/upgrade.html"
official_wording_summary: "No major skipping; the 31 major must be installed before 32."
applies_to_container_deployment: no
applies_to_existing_production_data: no
requires_latest_source_major_point_release: yes
requires_latest_target_major_point_release: yes
requires_background_migrations_before_next_step: yes
known_risks: "Skips the 31 PHP/APCu/config/AppAPI checks and database migrations."
required_QA_tests: "No skip QA is approved. Test 30.0.17 -> 31.0.14, complete migrations, then test 31.0.14 -> 32.0.11."
decision: reject
```

```yaml
candidate_path: "32 -> 34"
officially_supported: no
official_source: "https://docs.nextcloud.com/server/stable/admin_manual/maintenance/upgrade.html"
official_wording_summary: "No major skipping; the 33 major must be installed before 34."
applies_to_container_deployment: no
applies_to_existing_production_data: no
requires_latest_source_major_point_release: yes
requires_latest_target_major_point_release: yes
requires_background_migrations_before_next_step: yes
known_risks: "Skips the 33 boundary where PHP 8.1 and PostgreSQL 13 are dropped, Snowflake IDs are introduced, and other config/setup checks change."
required_QA_tests: "No skip QA is approved. Test 32.0.11 -> 33.0.5, complete migrations, then test 33.0.5 -> 34.0.0."
decision: reject
```

```yaml
candidate_path: "26 -> 34"
officially_supported: no
official_source: "https://docs.nextcloud.com/server/stable/admin_manual/maintenance/upgrade.html"
official_wording_summary: "No major skipping; repeat one-major upgrades until the applicable release is reached."
applies_to_container_deployment: no
applies_to_existing_production_data: no
requires_latest_source_major_point_release: yes
requires_latest_target_major_point_release: yes
requires_background_migrations_before_next_step: yes
known_risks: "Skips seven major migration, schema, background-job, app-compatibility, and critical-change boundaries; not an official production path; local entrypoint rejects it."
required_QA_tests: "No skip QA is approved. Rehearse and pass every one-major transition in isolated QA."
decision: reject
```

## Image Build Plan

The current pipeline is hardened correctly for manual GitLab UI use, but it is
currently wired for `NEXTCLOUD_VERSION=34.0.0`, `DOCKER_CONTEXT=34/fpm`, and
`DOCKERFILE_PATH=34/fpm/Dockerfile`. Intermediate image work is required before
runtime upgrades can begin.

Required scoped image changes before execution:

1. Produce compatible image contexts for each target major from 27 through 33,
   or parameterize the existing context in a way that preserves verified
   release-artifact handoff into Docker build.
2. Use PHP versions supported by the target Nextcloud major. Do not use the
   current PHP 8.4 Dockerfile for 27, 28, 29, or 30 because their archived
   official requirements do not list PHP 8.4.
3. Keep `pdo_pgsql`, `redis`, and APCu support.
4. Keep MySQL/MariaDB PHP extensions out of this custom PostgreSQL-only image.
5. Keep Redis/PostgreSQL/MySQL/MariaDB server daemons out of the application
   image.
6. Preserve CI behavior: release archive, checksum, signature, and signing key
   are downloaded only in `verify_release`; Docker build consumes verified CI
   artifacts and must not download the release archive again.
7. Keep all construction, smoke tests, publish, digest verification, and
   manifests in GitLab CI. Do not build locally.

Do not build intermediate images by starting from the previous major's
Nextcloud image and swapping PHP underneath it. PHP extensions are compiled
against a PHP ABI and distro library set, and the official Nextcloud image
layout can carry version-specific assumptions. For each target major, start
from a PHP FPM base that is officially supported by that target major, install
the minimum required OS packages and PHP extensions cleanly, then copy the
verified target Nextcloud release into `/usr/src/nextcloud`.

Copying the target Nextcloud server code into `/usr/src/nextcloud` is necessary
for this image pattern, but it is not the full upgrade. `/usr/src/nextcloud` is
only the immutable image source payload. The installed application lives in the
mounted `/var/www/html` tree, and the real upgrade state also lives in the
database, config, data directory, custom apps, themes, background migrations,
and enabled app set. The entrypoint still has to sync `/usr/src/nextcloud` into
`/var/www/html`, preserve mounted state, enforce the one-major upgrade limit,
and run or allow `occ upgrade`.

The final Dockerfile lines remain important and must be reviewed for every
major image:

```dockerfile
COPY *.sh upgrade.exclude /
COPY config/* /usr/src/nextcloud/config/

ENTRYPOINT ["/entrypoint.sh"]
CMD ["php-fpm"]
```

`entrypoint.sh` is critical upgrade logic, not boilerplate. It handles source
sync, install/upgrade flow, one-major guardrails, mounted directory handling,
hooks, and `occ upgrade`. `upgrade.exclude` must preserve runtime-owned
directories and files so config, data, custom apps, and themes are not
overwritten by image contents. `cron.sh` is usually stable, but still needs a
syntax and behavior check. `config/*` must be checked against the target major's
official requirements and local deployment ownership; runtime secrets,
PostgreSQL/Redis bindings, QA Redis `dbindex`, and `memcache_customprefix`
remain deployment-owned and must not be baked into the image.

Suggested PHP base by target major:

| Target major | Safe PHP base direction |
| --- | --- |
| 27 | PHP 8.2 FPM Debian base |
| 28 | PHP 8.2 or 8.3 FPM Debian base |
| 29 | PHP 8.2 or 8.3 FPM Debian base |
| 30 | PHP 8.3 FPM Debian base |
| 31 | PHP 8.3 or 8.4 FPM Debian base |
| 32 | PHP 8.3 or 8.4 FPM Debian base |
| 33 | PHP 8.4 FPM Debian base |
| 34 | Existing `php:8.4-fpm-trixie` is supported, even though 34 currently recommends PHP 8.5 |

## Image Artifact Tags And Manifests

For each target major, run the GitLab UI pipeline with:

```text
PUBLISH_IMAGE=true
NEXTCLOUD_VERSION=<version>
RELEASE_URL=https://download.nextcloud.com/server/releases/nextcloud-<version>.tar.bz2
RELEASE_ASC_URL=https://download.nextcloud.com/server/releases/nextcloud-<version>.tar.bz2.asc
RELEASE_SHA256_URL=https://download.nextcloud.com/server/releases/nextcloud-<version>.tar.bz2.sha256
DOCKER_CONTEXT=<versioned-image-context>
DOCKERFILE_PATH=<versioned-image-context>/Dockerfile
RUNTIME_DOCKER_CONTEXT=<runtime-image-context-if-used>
RUNTIME_DOCKERFILE_PATH=<runtime-image-context-if-used>/Dockerfile
RUNTIME_IMAGE_REPOSITORY=rusman/nextcloud_php_runtime
RUNTIME_IMAGE_TAG=<php-runtime-tag-if-used>
RELEASE_VERIFIER_DOCKER_CONTEXT=<release-verifier-context-if-used>
RELEASE_VERIFIER_DOCKERFILE_PATH=<release-verifier-context-if-used>/Dockerfile
RELEASE_VERIFIER_IMAGE_REPOSITORY=rusman/nextcloud_release_verifier
RELEASE_VERIFIER_IMAGE_TAG=<release-verifier-tag-if-used>
```

Each publishing pipeline produces exactly one environment-neutral image
artifact tag and one published manifest:

| Target | Published tag | Manifest |
| --- | --- | --- |
| 26.0.13 | `rusman/nextcloud_cron_fmp:26.0.13-houselab.<pipeline-id>` | `artifacts/nextcloud-image-manifest.yaml` |
| 27.1.11 | `rusman/nextcloud_cron_fmp:27.1.11-houselab.<pipeline-id>` | `artifacts/nextcloud-image-manifest.yaml` |
| 28.0.14 | `rusman/nextcloud_cron_fmp:28.0.14-houselab.<pipeline-id>` | `artifacts/nextcloud-image-manifest.yaml` |
| 29.0.16 | `rusman/nextcloud_cron_fmp:29.0.16-houselab.<pipeline-id>` | `artifacts/nextcloud-image-manifest.yaml` |
| 30.0.17 | `rusman/nextcloud_cron_fmp:30.0.17-houselab.<pipeline-id>` | `artifacts/nextcloud-image-manifest.yaml` |
| 31.0.14 | `rusman/nextcloud_cron_fmp:31.0.14-houselab.<pipeline-id>` | `artifacts/nextcloud-image-manifest.yaml` |
| 32.0.11 | `rusman/nextcloud_cron_fmp:32.0.11-houselab.<pipeline-id>` | `artifacts/nextcloud-image-manifest.yaml` |
| 33.0.5 | `rusman/nextcloud_cron_fmp:33.0.5-houselab.<pipeline-id>` | `artifacts/nextcloud-image-manifest.yaml` |
| 34.0.0 | `rusman/nextcloud_cron_fmp:34.0.0-houselab.<pipeline-id>` | `artifacts/nextcloud-image-manifest.yaml` |

For the first 26.0.13 image, use:

```text
DOCKER_CONTEXT=26/26.0.13/fpm
DOCKERFILE_PATH=26/26.0.13/fpm/Dockerfile
RUNTIME_DOCKER_CONTEXT=runtime/php/8.2-bookworm
RUNTIME_DOCKERFILE_PATH=runtime/php/8.2-bookworm/Dockerfile
RUNTIME_IMAGE_REPOSITORY=rusman/nextcloud_php_runtime
RUNTIME_IMAGE_TAG=8.2-bookworm
RELEASE_VERIFIER_DOCKER_CONTEXT=runtime/release-verifier/alpine-3.21
RELEASE_VERIFIER_DOCKERFILE_PATH=runtime/release-verifier/alpine-3.21/Dockerfile
RELEASE_VERIFIER_IMAGE_REPOSITORY=rusman/nextcloud_release_verifier
RELEASE_VERIFIER_IMAGE_TAG=alpine-3.21
```

QA and PROD must deploy the same published digest from the manifest. Do not
rebuild or republish a different image between QA acceptance and PROD
deployment. QA/PROD separation belongs to the deployment/IaC repository:
volumes, PostgreSQL, Redis, hostnames, secrets, and runtime config.

## QA Runtime Isolation

QA must never mount or connect to production resources.

Required QA resources:

- QA app/html volume, for example
  `/mnt/user/appdata/nextcloud-qa/html:/var/www/html`.
- QA data volume, for example
  `/mnt/user/appdata/nextcloud-qa/data:/srv/data`.
- QA config volume, for example
  `/mnt/user/appdata/nextcloud-qa/config:/var/www/html/config`.
- QA custom apps volume, for example
  `/mnt/user/appdata/nextcloud-qa/custom_apps:/var/www/html/custom_apps`.
- QA themes volume, for example
  `/mnt/user/appdata/nextcloud-qa/themes:/var/www/html/themes`.
- QA PostgreSQL database and QA user at minimum, for example
  database `nextcloud_qa`, user `nextcloud_qa`. A separate QA PostgreSQL
  container is safer.
- QA Redis logical DB index and QA cache prefix, or a separate QA Redis
  container. Redis does not have SQL tables.
- QA hostname, for example `nextcloud-qa.houselab.page`.
- QA secrets outside Git.

Official PostgreSQL documentation says Nextcloud assumes only Nextcloud uses
its PostgreSQL database and recommends a separate database or PostgreSQL
instance for further services/users. Use that model for QA. Do not call a
PostgreSQL database an "index".

Official Redis documentation supports `redis.dbindex` and
`memcache_customprefix`. If QA shares Redis with PROD, use both:

```php
'memcache_customprefix' => 'nextcloud_qa_',
'redis' => [
  'host' => 'redis',
  'port' => 6379,
  'dbindex' => 1,
],
```

Prefer a separate QA Redis container if operationally acceptable.

## QA Upgrade Procedure Per Major

Repeat for every target in this order:

```text
27.1.11, 28.0.14, 29.0.16, 30.0.17, 31.0.14, 32.0.11, 33.0.5, 34.0.0
```

1. Restore a sanitized production backup, or a deliberate production-like test
   dataset, into QA-only volumes and QA-only PostgreSQL.
2. Configure QA-only hostname, trusted domains, overwrite URL, SMTP test
   behavior, PostgreSQL credentials, and Redis dbindex/prefix.
3. Confirm QA Compose/Ansible contains no `/mnt/user/appdata/nextcloud/...`
   production mounts.
4. Deploy the target image by the published manifest digest.
5. Run or confirm the application upgrade:

   ```text
   docker exec --user www-data nextcloud_qa php /var/www/html/occ upgrade
   ```

6. Run background jobs two or three times:

   ```text
   docker exec --user www-data nextcloud_qa php -f /var/www/html/cron.php
   ```

7. Run long-running database maintenance commands:

   ```text
   docker exec --user www-data nextcloud_qa php /var/www/html/occ db:add-missing-columns
   docker exec --user www-data nextcloud_qa php /var/www/html/occ db:add-missing-indices
   docker exec --user www-data nextcloud_qa php /var/www/html/occ db:add-missing-primary-keys
   ```

8. Run setup/status checks:

   ```text
   docker exec --user www-data nextcloud_qa php /var/www/html/occ status --output=json
   docker exec --user www-data nextcloud_qa php /var/www/html/occ app:list
   docker exec --user www-data nextcloud_qa php /var/www/html/occ maintenance:mode --off
   ```

9. Review admin overview setup checks, Nextcloud logs, container logs,
   PostgreSQL logs, Redis connectivity, cron, WebDAV, CalDAV, CardDAV, shares,
   file upload/download, app passwords, 2FA login, contacts, calendars, and
   third-party app behavior.
10. Record disabled apps and operator decisions. Do not proceed to the next
    major until QA acceptance and background migrations are complete.

PROD must consume only the same manifest accepted by QA, with:

```yaml
artifact_scope: "environment-neutral"
published: true
image_digest: "sha256:..."
image_pull_by_digest: "rusman/nextcloud_cron_fmp@sha256:..."
```

PROD must not consume validation manifests, mutable tags, or `latest`.

## PROD Runbook Per Major

Repeat this gate and runbook for each one-major transition. Do not batch
multiple majors into one production change.

Preflight gate:

1. Verify current version:

   ```text
   docker exec --user www-data nextcloud_server php /var/www/html/occ status --output=json
   ```

2. Verify PostgreSQL:

   ```text
   SELECT version();
   SHOW server_version_num;
   SELECT current_database(), current_user;
   ```

3. Confirm the current PostgreSQL major is supported by both the current
   Nextcloud major and target Nextcloud major.
4. Confirm fresh production backups exist for:
   - Nextcloud app/html volume.
   - Data volume.
   - Config volume.
   - Custom apps and themes volumes.
   - PostgreSQL logical dump.
   - Deployment config.
5. Confirm a restore test passed using QA-only resources.
6. Confirm the exact same major transition passed in isolated QA.
7. Confirm the target manifest is published, digest verified, and matches the
   same digest accepted in QA.
8. Confirm a maintenance window is approved.
9. Disable or get operator approval for third-party apps that block the target
   release.

Execution:

```text
docker exec --user www-data nextcloud_server php /var/www/html/occ maintenance:mode --on

# Deployment repo action, shown as pseudocode because this repo does not own it:
# update compose/ansible image to the production manifest digest or immutable tag
# deploy the one-major target image

docker exec --user www-data nextcloud_server php /var/www/html/occ upgrade
docker exec --user www-data nextcloud_server php -f /var/www/html/cron.php
docker exec --user www-data nextcloud_server php -f /var/www/html/cron.php
docker exec --user www-data nextcloud_server php -f /var/www/html/cron.php
docker exec --user www-data nextcloud_server php /var/www/html/occ db:add-missing-columns
docker exec --user www-data nextcloud_server php /var/www/html/occ db:add-missing-indices
docker exec --user www-data nextcloud_server php /var/www/html/occ db:add-missing-primary-keys
docker exec --user www-data nextcloud_server php /var/www/html/occ maintenance:repair
docker exec --user www-data nextcloud_server php /var/www/html/occ status --output=json
docker exec --user www-data nextcloud_server php /var/www/html/occ app:list
docker exec --user www-data nextcloud_server php /var/www/html/occ maintenance:mode --off
```

Acceptance checks:

- Admin overview shows no blocking setup warnings.
- Nextcloud logs have no new critical migration, database, Redis, or app
  errors.
- Container logs show no entrypoint or upgrade failures.
- PostgreSQL connectivity and Redis locking/cache work.
- Cron runs.
- Web UI login works for both active users.
- 2FA works.
- App passwords still work or affected app-password cleanup is explicitly
  accepted for the 30 step.
- File upload/download, WebDAV, CalDAV, CardDAV, contacts, calendars, internal
  shares, public shares, previews, and existing user scripts work.
- Third-party apps are either re-enabled and tested or deliberately left
  disabled with an operator decision.

Rollback stop points:

- Before deploying the new image: rollback is the previous image plus untouched
  volumes/database.
- After deployment but before successful `occ upgrade`: stop containers and
  restore the pre-upgrade backup if the instance cannot be made healthy.
- After `occ upgrade` succeeds: do not downgrade in place. Official docs warn
  downgrading is unsupported and risks data corruption. Rollback means fresh
  restore of the full pre-upgrade backup set to the previous image.
- After accepting a major: do not start the next major until backups,
  background migrations, admin overview, and operator acceptance are complete.

## Stop Conditions

Stop and ask the operator if any of the following occur:

- Official docs contradict this plan.
- Official docs become ambiguous about a proposed major skip.
- Live `occ status` no longer shows the confirmed 26.0.0 starting point.
- A target major's latest point release cannot be verified from official
  releases/changelog sources.
- QA cannot be isolated from production volumes, PostgreSQL, and Redis.
- A backup or restore test is missing.
- A third-party app blocks an upgrade and needs an operator decision.
- PostgreSQL major is outside either the current or target support window.
- A step requires MySQL/MariaDB support.
- A step would expose Docker Hub credentials, runtime secrets, DB passwords,
  SMTP passwords, or Nextcloud instance secrets in Git, CI logs, or plain
  files.
- GitLab runner, Docker Hub credentials, or protected/masked variable setup is
  missing.
