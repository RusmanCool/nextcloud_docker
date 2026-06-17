# Handoff Spec: Nextcloud 26 to 34 Major Upgrade Plan

## Purpose

Prepare the next engineering agent to expand the production upgrade plan from
the current Nextcloud 26 deployment to the approved Nextcloud 34 target without
skipping major releases and without allowing QA to touch production data.

This is a planning and implementation handoff. The next agent must verify all
version facts against official Nextcloud sources before building or deploying
anything.

## Evidence Standard

Use official Nextcloud documentation and release artifacts as primary sources.
Do not infer upgrade rules from memory, forum comments, existing scripts, or
Docker image behavior unless those claims are backed by official docs.

Required official sources to review:

- Nextcloud 34 upgrade manual:
  `https://docs.nextcloud.com/server/stable/admin_manual/maintenance/upgrade.html`
- Nextcloud 34 database configuration:
  `https://docs.nextcloud.com/server/stable/admin_manual/configuration_database/linux_database_configuration.html`
- Nextcloud 34 Redis/memory cache configuration:
  `https://docs.nextcloud.com/server/stable/admin_manual/configuration_server/caching_configuration.html`
- Nextcloud changelog:
  `https://nextcloud.com/changelog/`
- Nextcloud release download directory:
  `https://download.nextcloud.com/server/releases/`

The upgrade manual says Nextcloud must be upgraded step by step. It requires
upgrading to the latest point release of the current major before upgrading to
the next major, then repeating that process. It explicitly says major releases
cannot be skipped. It also says background migrations must finish after major
upgrades before starting another major upgrade.

The next agent must not stop at quoting this rule. It must research and explain
why the rule exists using official sources. At minimum, investigate whether the
reason is tied to database schema migrations, background jobs, app framework
changes, shipped app migrations, config migrations, file cache changes, or
supported rollback/repair boundaries.

The next agent must also research whether official Nextcloud documentation
defines any exception to the no-skip rule. If an exception exists, record:

- The exact source and wording.
- The exact starting and ending versions covered by the exception.
- Whether the exception applies to Docker/container installs.
- Whether it applies to production systems with existing users, apps, files,
  calendars, contacts, shares, app passwords, and 2FA.
- Required preconditions, backup/restore requirements, and post-upgrade repair
  commands.

Do not invent an exception. Do not assume that "it worked in QA once" means the
path is supported for production.

The existing custom image entrypoint has the same practical guard at
`34/fpm/entrypoint.sh`: it exits if the image major version is more than one
major ahead of the installed version. This script behavior is supporting
evidence only; the official docs are the authority.

## Current Assumptions To Re-Verify

- Current production application lineage is Nextcloud 26.x.
- Existing Docker Hub production image is
  `rusman/nextcloud_cron_fmp:26.0.13`.
- Current persisted config may report `26.0.0.11`; live `occ status` must
  verify the actual installed version before planning the first jump.
- Approved target for this workstream is Nextcloud 34, currently represented by
  the custom image pipeline variable `NEXTCLOUD_VERSION=34.0.0`.
- Do not treat "latest" as stable without checking official release/changelog
  pages at the time of work. If Nextcloud 35 is latest upstream but 34 is the
  approved migration target, document that distinction explicitly.

## Non-Negotiable Upgrade Rule

Default position: do not upgrade 26 directly to 34, and do not skip any major
release.

The required major path is:

```text
26 -> 27 -> 28 -> 29 -> 30 -> 31 -> 32 -> 33 -> 34
```

Before each major step, verify the latest point release for the current major
and the target major. If production is not already on the latest 26 point
release, first upgrade within 26 before moving to 27.

Each major step must complete its own application upgrade, database migrations,
background jobs, and acceptance checks before the next major step starts.

## Major-Skip Research Gate

The operator is open to a shorter path only if it is officially supported and
the risk is explicitly understood. The next agent must research this before
proposing any skip such as `26 -> 28`, `28 -> 30`, or another two-major jump.

For each possible skip candidate, create a decision table:

```text
candidate_path: 26 -> 28
officially_supported: yes/no
official_source:
official_wording_summary:
applies_to_container_deployment: yes/no/unknown
requires_latest_source_major_point_release: yes/no
requires_latest_target_major_point_release: yes/no
background_migrations_before_next_step: yes/no
known_risks:
required_QA_tests:
decision: reject/consider/approve
```

Required candidate paths to evaluate:

```text
26 -> 28
28 -> 30
30 -> 32
32 -> 34
```

Also evaluate whether any one-off larger jump is officially supported:

```text
26 -> 34
```

If official documentation says major releases cannot be skipped, mark each
candidate as rejected unless another official Nextcloud source explicitly
documents an exception for that exact path.

If official documentation permits a skip, the next agent must still require a
QA rehearsal using isolated QA PostgreSQL, QA Redis, and QA volumes before
production. A permitted skip is not automatically a production approval.

## Image Pipeline Requirements

The image repository owns custom image builds:

```text
/home/rusman/GitRepos/nextcloud_docker
self-hosted GitLab project: hn583/nextcloud_docker
Docker Hub repository: rusman/nextcloud_cron_fmp
```

The next agent must extend or replicate the existing hardened CI model for each
required major:

- Release archive, checksum, signature, and signing key are downloaded only in
  the release verification stage.
- Docker build consumes verified CI artifacts. The Dockerfile must not download
  the Nextcloud release archive again.
- Build and smoke tests run in GitLab CI, not from a developer checkout.
- The image must include PostgreSQL PHP support and Redis PHP client support.
- The image must not include MySQL/MariaDB support or Redis/PostgreSQL/MySQL
  server daemons.
- QA publishing uses QA tags and QA manifests.
- PROD publishing uses release tags and production manifests.

Recommended tag pattern per major:

```text
QA:   rusman/nextcloud_cron_fmp:<version>-qa
QA:   rusman/nextcloud_cron_fmp:<version>-qa-houselab.<commit-sha>
QA:   rusman/nextcloud_cron_fmp:<version>-qa-houselab.<pipeline-id>
PROD: rusman/nextcloud_cron_fmp:<version>
PROD: rusman/nextcloud_cron_fmp:<version>-houselab.<commit-sha>
PROD: rusman/nextcloud_cron_fmp:<version>-houselab.<pipeline-id>
```

For each pushed image, verify all tags resolve to the same Docker Hub digest.

## QA Isolation Requirements

QA must never mount or connect to production resources.

QA requires all of the following:

- QA-specific Nextcloud app/html volume.
- QA-specific Nextcloud data volume.
- QA-specific config volume.
- QA-specific custom apps and themes volumes.
- QA-specific PostgreSQL database and user, or a separate PostgreSQL instance.
- QA-specific Redis logical database index and cache prefix, or a separate Redis
  instance.
- QA-specific public hostname or local-only hostname.
- QA-specific secrets, stored outside Git.

Do not use production bind mounts such as:

```text
/mnt/user/appdata/nextcloud/html
/mnt/user/appdata/nextcloud/data
/mnt/user/appdata/nextcloud/config
/mnt/user/appdata/nextcloud/custom_apps
/mnt/user/appdata/nextcloud/themes
```

Use QA paths instead, for example:

```text
/mnt/user/appdata/nextcloud-qa/html
/mnt/user/appdata/nextcloud-qa/data
/mnt/user/appdata/nextcloud-qa/config
/mnt/user/appdata/nextcloud-qa/custom_apps
/mnt/user/appdata/nextcloud-qa/themes
```

Redis does not have SQL-style tables. For QA isolation, use an isolated Redis
logical database index through Nextcloud's `redis.dbindex` setting and a
QA-specific `memcache_customprefix`, or run a separate QA Redis container. The
official Nextcloud Redis configuration documents `dbindex` and
`memcache_customprefix`.

PostgreSQL does not isolate applications with an "index" in the way Redis uses
`dbindex`. Use a separate QA PostgreSQL database and QA database user at
minimum. A separate QA PostgreSQL container is safer. The official PostgreSQL
configuration recommends a separate database or PostgreSQL instance for further
services/users.

Example QA config intent:

```php
'dbtype' => 'pgsql',
'dbname' => 'nextcloud_qa',
'dbuser' => 'nextcloud_qa',
'dbhost' => 'postgres_qa',
'memcache.local' => '\OC\Memcache\APCu',
'memcache.distributed' => '\OC\Memcache\Redis',
'memcache.locking' => '\OC\Memcache\Redis',
'memcache_customprefix' => 'nextcloud_qa_',
'redis' => [
  'host' => 'redis_qa',
  'port' => 6379,
  'dbindex' => 1,
],
```

If QA shares a Redis server with PROD, do not use the production Redis dbindex
or production prefix. Prefer a separate QA Redis container if the operational
cost is acceptable.

## PROD Requirements

Production must consume only production manifests:

```text
artifacts/nextcloud-image-manifest.yaml
deployment_environment: "prod"
published: true
image_digest: "sha256:..."
```

Production must not consume:

```text
artifacts/nextcloud-image-qa-manifest.yaml
artifacts/nextcloud-image-qa-validation.yaml
artifacts/nextcloud-image-validation.yaml
```

Production deploys must use the manifest digest or an immutable production tag,
not `latest` and not a QA tag.

## Per-Major Upgrade Template

Repeat this template for each major transition:

```text
26 -> 27
27 -> 28
28 -> 29
29 -> 30
30 -> 31
31 -> 32
32 -> 33
33 -> 34
```

For each transition:

1. Research and record official release target.
   - Check the Nextcloud changelog and release download directory.
   - Determine the latest point release for the target major.
   - Record release URL, checksum URL, signature URL, and GPG fingerprint.

2. Review official critical changes.
   - Use the critical changes page for the target major.
   - Record required PHP, database, Redis, app, and config changes.
   - Update the custom Dockerfile only for requirements proven by official docs
     or upstream image practice.

3. Build QA image.
   - Use the hardened image pipeline.
   - Set `DEPLOYMENT_ENV=qa`.
   - Publish `<version>-qa` and immutable QA tags.
   - Produce `nextcloud-image-qa-manifest.yaml`.

4. Prepare QA runtime.
   - Restore a sanitized production backup or a deliberate test dataset into QA
     volumes only.
   - Restore or clone the database into the QA PostgreSQL database only.
   - Configure QA Redis dbindex/prefix or QA Redis container.
   - Confirm QA Compose/Ansible cannot mount production volumes.

5. Run QA upgrade.
   - Start QA with the target major image.
   - Run `occ upgrade` if the container entrypoint does not complete it.
   - Run `cron.php` 2-3 times after the major upgrade.
   - Run any required long-running migration commands, including:
     - `occ db:add-missing-columns`
     - `occ db:add-missing-indices`
     - `occ db:add-missing-primary-keys`
   - Run app compatibility checks and re-enable approved apps.
   - Confirm users, files, shares, calendars, contacts, app passwords, and 2FA
     behavior in QA.

6. Gate production approval.
   - Fresh production backup exists.
   - Restore test completed.
   - QA acceptance for this exact major transition passed.
   - Rollback plan documented.
   - Maintenance window approved.

7. Publish PROD image.
   - Set `DEPLOYMENT_ENV=prod`.
   - Publish the plain release tag and immutable PROD tags.
   - Produce `nextcloud-image-manifest.yaml`.

8. Run PROD upgrade.
   - Put production in maintenance mode.
   - Deploy the production image by digest or immutable tag.
   - Let the entrypoint/`occ upgrade` complete.
   - Run `cron.php` 2-3 times.
   - Run required `occ db:*` repair/migration commands.
   - Validate admin overview, logs, user workflows, sharing, WebDAV, CalDAV,
     CardDAV, cron, Redis locking, and PostgreSQL connectivity.
   - Leave production on this major until background migrations and acceptance
     checks are complete.

9. Record result.
   - Image tag and digest.
   - Source commit and pipeline URL.
   - Release verification result.
   - QA and PROD upgrade timestamps.
   - Any disabled or removed apps.
   - Any manual migrations run.

## Concrete Step List For 26 To 34

The next agent should expand this into exact patch/build/deploy tasks after
researching current point releases:

1. Verify current production version with `occ status`.
2. If production is below the final 26 point release, upgrade within 26 first.
3. Build/test/publish QA image for latest 27 point release.
4. Upgrade QA 26 -> 27 and complete migrations.
5. Publish PROD 27 image and upgrade PROD 26 -> 27.
6. Build/test/publish QA image for latest 28 point release.
7. Upgrade QA 27 -> 28 and complete migrations.
8. Publish PROD 28 image and upgrade PROD 27 -> 28.
9. Repeat the same QA-first, PROD-second flow for 29, 30, 31, 32, and 33.
10. Build/test/publish QA image for approved 34 target.
11. Upgrade QA 33 -> 34 and complete migrations.
12. Publish PROD 34 image and upgrade PROD 33 -> 34.

Do not merge multiple major upgrades into one container start unless the
Major-Skip Research Gate proves that exact path is officially supported. Do not
continue to the next major until the current major has completed background
migrations and acceptance checks.

## Stop Conditions

Stop and ask the operator before continuing if:

- Official docs contradict this handoff.
- Official docs are ambiguous about whether a proposed major skip is supported.
- Current live `occ status` does not match the assumed 26.x starting point.
- A target major's latest point release cannot be verified from official
  sources.
- QA cannot be fully isolated from production volumes, PostgreSQL, and Redis.
- A backup or restore test is missing.
- A third-party app is incompatible and has no approved replacement/disable
  decision.
- The Docker image would need MySQL/MariaDB support.
- Any step requires exposing production secrets in Git, CI logs, or plain files.

## Deliverables For The Next Agent

- A researched version matrix for 26 -> 34 with official links.
- CI/image changes needed to build each intermediate major.
- QA manifests and QA deployment configs for each major.
- PROD manifests for each approved production major transition.
- A runbook with commands and validation checks for each transition.
- A final risk list with unresolved app, database, Redis, volume, or proxy
  concerns.
