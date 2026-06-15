# Nextcloud Upgrade and IaC Migration Plan

Date: 2026-06-15

Status: planning only. Do not run live migration from this document without a
fresh backup, a restore test, and an operator-approved maintenance window.

## Objective

Move the existing Unraid-hosted Nextcloud deployment from the legacy DockerMan
container model to Ansible-managed Docker Compose Manager deployment through the
local GitLab Server at `https://gitlab.houselab.page:1443`.

The migration must preserve the existing two active users and their profiles,
files, shares, calendars, contacts, app state, passwords, app passwords, and
2FA state. It must be safe to redeploy the same target major version
idempotently, and it must never delete or replace the current data directory or
database as part of normal deployment.

## Major Tasks

There are two separate workstreams with a hard ownership boundary.

### Major Task 1: Custom Nextcloud Image

Owner:

```text
self-hosted GitLab project hn583/nextcloud_docker
local checkout /home/rusman/GitRepos/nextcloud_docker
```

Goal:

Build a new custom FPM Nextcloud image based on the existing
`rusman/nextcloud_cron_fmp:26.0.13` lineage, but using the latest approved
Nextcloud server release code, then publish it to Docker Hub.

Scope:

- Keep Dockerfile, image Ansible/IaC, image CI/CD, build scripts, release
  verification, image smoke tests, and Docker Hub publishing in
  `hn583/nextcloud_docker`.
- Reuse the current custom image source where applicable, especially
  `26/fpm/Dockerfile`, `cron.sh`, `entrypoint.sh`, `upgrade.exclude`, and
  `config/`.
- Build from a pinned Nextcloud release artifact or exact release tag.
- Verify release checksum and PGP signature before building.
- Push with the historical repository name:

```text
docker push rusman/nextcloud_cron_fmp:<tagname>
```

- Publish an image manifest containing repository, tag, digest, Nextcloud
  version, source commit, release URL, signature verification result, and smoke
  test result.

Out of scope:

- This `unraid` repo must not own the Dockerfile or image build pipeline.
- This `unraid` repo must not hold Docker Hub push credentials unless image
  publishing ownership is explicitly moved later.

### Major Task 2: Nextcloud Server Migration

Owner:

```text
this unraid repository
composeManager/projects/Nextcloud/
ansible/playbooks/nextcloud/
ansible/roles/nextcloud_stack/
ansible/roles/nextcloud_backup/
```

Goal:

Use the custom image from Major Task 1 and provide all Compose, Ansible, SWAG,
backup, verification, and migration configuration required to make the upgrade
as uneventful as possible for the two active users.

Scope:

- Consume only an approved image tag/digest manifest from `hn583/nextcloud_docker`.
- Preserve the existing Nextcloud data directory, database, config, custom apps,
  themes, users, passwords, app passwords, shares, calendars, contacts, and 2FA
  state.
- Keep deployment idempotent for same-major redeploys.
- Run backups, restore tests, staging rehearsal, one-major-at-a-time upgrades,
  post-upgrade checks, and user acceptance checks.
- Keep SWAG/FPM/static asset behavior working for `nextcloud.houselab.page:1443`.

Out of scope:

- Building or modifying the custom Docker image.
- Publishing image tags to Docker Hub.
- Changing user-visible behavior unless required by the Nextcloud upgrade.

## Current Local State

Reviewed files:

```text
dockerMan/templates-user/my-NextCloud-fpm.xml
dockerMan/templates-user/my-swag.xml
docker_vols/nc_conf/
/home/rusman/GitRepos/unraid-swag-config/nginx/proxy-confs-http/nextcloud.subdomain.conf
composeManager/projects/GitLab/Server/
composeManager/projects/GitLab/RunnerAdmin/
ansible/playbooks/gitlab/full_iac.yml
ansible/roles/compose_stack/
ansible/inventories/prod/group_vars/homenas/
.gitlab-ci.yml
```

Observed Nextcloud deployment shape:

- Container name: `nextcloud_server`.
- Image in DockerMan: custom `rusman/nextcloud_cron_fmp:26.0.13`.
- Docker Hub `rusman/nextcloud_cron_fmp` currently has tags `26.0.13` and
  `26.0.0`; `26.0.13` is the newest pushed tag as of 2026-06-15.
- Docker Hub digest for `rusman/nextcloud_cron_fmp:26.0.13`:
  `sha256:ffe7e0e98432f5495259cc09966216791c08f9f323a17590ea8ce06269ebd571`.
- Persisted config reports Nextcloud `26.0.0.11`; live `occ status` must verify
  the actual running version before any migration.
- Network: external Docker network `proxynet`.
- App paths:
  - `/mnt/user/appdata/nextcloud/html:/var/www/html`
  - `/mnt/user/appdata/nextcloud/data:/srv/data`
  - `/mnt/user/appdata/nextcloud/config:/var/www/html/config`
  - `/mnt/user/appdata/nextcloud/themes:/var/www/html/themes`
  - `/mnt/user/appdata/nextcloud/custom_apps:/var/www/html/custom_apps`
- Database: existing external PostgreSQL container `postgres_14`, database name
  currently recorded as `nextcloud-test`.
- DockerMan template for `postgres_14` uses `postgres:14.1` and stores data at
  `/mnt/user/appdata/postgres/14.1`; live `SELECT version()` must verify the
  actual running PostgreSQL version before migration.
- Redis: existing external container `Redis`, used for distributed cache and
  file locking.
- Current SWAG proxy uses FastCGI to `nextcloud_server:9000` and sets Nginx
  `root /var/www/html`.
- Current SWAG DockerMan template uses `--volumes-from=nextcloud_server`.
  That is important because Nginx serves static Nextcloud assets from the same
  application tree that PHP-FPM uses.
- Current SWAG Nextcloud config has hardcoded `:1443` in CalDAV/CardDAV and
  related `.well-known` redirects.
- Existing user script `Move_Media_From_NC_2_MediaShare` references user data
  under `/mnt/user/appdata/nextcloud/data/hn581` and
  `/mnt/user/appdata/nextcloud/data/hn583`, then runs `occ files:scan --all`.

Important secret handling finding:

- Current config files contain live secrets. Do not copy those values into plan
  docs, GitLab CI variables, `.env`, pipeline logs, or plain Ansible vars.
- The migration should preserve the existing `config.php` and not regenerate
  `instanceid`, `passwordsalt`, or `secret`.
- New automation secrets must use Ansible Vault or protected/masked GitLab CI
  variables as appropriate.

## Target Architecture

Source of truth:

```text
composeManager/projects/Nextcloud/
ansible/playbooks/nextcloud/
ansible/roles/nextcloud_stack/
ansible/roles/nextcloud_backup/
ansible/roles/nextcloud_database/
ansible/roles/swag_proxy/        # currently stale; implement before use
ansible/inventories/prod/group_vars/homenas/nextcloud.yml
ansible/inventories/prod/group_vars/homenas/vault.yml
```

Separate image source of truth:

```text
/home/rusman/GitRepos/nextcloud_docker
self-hosted GitLab project: hn583/nextcloud_docker
```

Remote Compose Manager target:

```text
/boot/config/plugins/compose.manager/projects/nextcloud
```

Recommended first production target:

- Keep PostgreSQL `postgres_14` and Redis `Redis` as existing external services
  for the first migration. Moving DB/Redis under the Nextcloud Compose project
  is a separate migration with a larger blast radius.
- Keep the service name and container name `nextcloud_server` initially so SWAG
  FastCGI upstream resolution does not change.
- Keep an FPM runtime rather than switching to Apache for the first migration.
  Deploy the Houselab custom image built by `hn583/nextcloud_docker` instead of
  consuming the official `nextcloud:fpm` image directly.
- Continue publishing the production image to Docker Hub as
  `rusman/nextcloud_cron_fmp:<tag>`, unless the operator explicitly decides to
  move image publishing to the local GitLab registry later.
- Add an explicit cron sidecar or equivalent Ansible-managed scheduled job.
- Preserve all existing host paths.

Expected Compose project contents:

```text
composeManager/projects/Nextcloud/.env
composeManager/projects/Nextcloud/docker-compose.yml
composeManager/projects/Nextcloud/name
composeManager/projects/Nextcloud/README.md
```

The `.env` file must contain non-secret values only: image tag, container names,
paths, network names, timezone, upload/memory limits, public host/URL, and
Compose metadata. Database and SMTP secrets should not be added there.

Existing custom image source evidence:

```text
/home/rusman/GitRepos/nextcloud_docker
branch: update_to_latest_v26
commit: 07bfcb5754309855a85c49e6c7d6e3c344d40cf2
Dockerfile: 26/fpm/Dockerfile
NEXTCLOUD_VERSION: 26.0.13
remote: git@github.com:RusmanCool/nextcloud_docker.git
self-hosted GitLab remote/push path: gitlab-houselab:hn583/nextcloud_docker.git
```

## Latest Version Decision

As of the research date:

- The official Nextcloud changelog lists Nextcloud Server `34.0.0`.

This creates a deployment gate:

- The product target is "latest Nextcloud Server".
- The safe container target is a Houselab-built custom FPM image containing a
  pinned, verified Nextcloud release source package.
- Agents must not build from `master`, a moving branch, or an unverified archive
  for production. Use an explicit release version/tag such as `34.0.0`.
- The `nextcloud_docker` pipeline must verify the release archive checksum and
  PGP signature before building the image.
- The `nextcloud_docker` pipeline must publish immutable version tags to Docker
  Hub `rusman/nextcloud_cron_fmp`.
- This Nextcloud Server pipeline must deploy by verified digest or immutable
  tag, not by a mutable `latest` tag.

## Custom Image Contract

The custom image is not built by this Unraid/Nextcloud Server IaC pipeline.
Image source, Dockerfile changes, release verification, Docker Hub publishing,
and image smoke tests belong in the separate self-hosted GitLab project
`hn583/nextcloud_docker`.

This repo consumes the image as an input:

- Desired image repository: `rusman/nextcloud_cron_fmp`.
- Desired image tag: declared in Nextcloud Server IaC variables and/or
  Compose `.env`.
- Desired image digest: captured from the image pipeline and recorded before
  deployment.
- Deployment gate: this repo must verify that the declared tag exists and
  resolves to the declared digest before deploying.

The `nextcloud_docker` repo should own:

- Dockerfile and all image build scripts/config.
- Migration of the current `26/fpm/Dockerfile` and related scripts.
- Nextcloud release archive or exact release-tag checkout selection.
- Release checksum and PGP signature verification.
- Image build, image smoke tests, and Docker Hub push.
- Publication of an image manifest artifact that this repo can consume.

Image provenance artifact expected from `nextcloud_docker`:

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
smoke_tests_passed: true
published_at: "..."
```

Expected image naming:

```text
rusman/nextcloud_cron_fmp:<nextcloud-version>-houselab.<build-number>
rusman/nextcloud_cron_fmp:<nextcloud-version>-houselab.<git-sha>
```

Existing tag compatibility rule:

- Keep the historical plain version tag pattern available when intentionally
  replacing a production target, for example `rusman/nextcloud_cron_fmp:34.0.0`.
- The push command shape is:

```text
docker push rusman/nextcloud_cron_fmp:<tagname>
```

- For CI traceability, also publish a build-specific tag and record its digest.
- Do not use `latest` as the deployment selector.

Optional registry mirror:

- The primary push target remains Docker Hub.
- A later agent may also mirror the same digest to the local GitLab registry,
  but only after GitLab registry support is confirmed and without changing the
  production deployment selector in the same migration.

Upgrade images must be built for every intermediate major in the migration
sequence by the `nextcloud_docker` pipeline. For example, do not build only a
`34.x` image and run it against the current `26.x` data. This repo's production
pipeline must refuse to run an upgrade-major job until the matching external
image manifest is present and verified.

## Why FPM Is Used

FPM is used because the current SWAG/Nginx container is the web server. Nginx
terminates TLS, serves static files from `/var/www/html`, and forwards PHP
requests to `nextcloud_server:9000` over FastCGI.

Cron is related but separate:

- Nextcloud background jobs should run `cron.php` regularly, normally every
  five minutes, under the web-server user.
- FPM does not itself make cron work. FPM is the PHP request worker for Nginx.
- The old custom image probably combined FPM and cron so both processes existed
  in one container. That is convenient but not required.
- In the new Compose model, prefer a separate cron service using the same
  Nextcloud image and the same mounted paths, or an Ansible-managed Unraid
  schedule that runs:

```text
docker exec --user www-data nextcloud_server php -f /var/www/html/cron.php
```

Important clarification:

- Cron handles registered background jobs such as cleanup, app housekeeping,
  update checks, and external-storage related work.
- Cron is not a general replacement for `occ files:scan` after files are moved
  directly in the data directory. Existing scripts that mutate
  `/mnt/user/appdata/nextcloud/data/...` should continue to run an explicit
  `occ files:scan` for the affected users or paths.

## Upgrade Strategy

Never skip major versions.

1. Verify live current version with `occ status --output=json`.
2. If the instance is actually on `26.0.0`, first bring it to the latest
   published `26.x` maintenance image.
3. Upgrade one major version at a time.
4. After each major upgrade, wait for the app to report healthy state, run
   `cron.php` two or three times, and verify no pending critical migrations
   before attempting the next major.
5. Keep a manual approval gate between every major version in production.

Target major sequence from the current 26.x baseline:

```text
26.x latest maintenance
27.x latest maintenance
28.x latest maintenance
29.x latest maintenance
30.x latest maintenance
31.x latest maintenance
32.x latest maintenance
33.x latest maintenance
34.x latest maintenance, only after the matching custom FPM image manifest is verified
```

The exact patch image for each major must be resolved by the external
`nextcloud_docker` image manifest at implementation time. Do not hardcode stale
patch versions without a verified manifest and recorded image digest.

## Database Compatibility and Migration Plan

There may be incompatibilities between the current Nextcloud 26.x stack and the
latest Nextcloud target. Database compatibility must be checked separately from
the application image.

Known support window from official Nextcloud docs:

- Nextcloud 26 supports PostgreSQL 10/11/12/13/14/15.
- Current latest Nextcloud supports PostgreSQL 14/15/16/17/18.
- The current local DockerMan template indicates `postgres:14.1`, so the
  current PostgreSQL major is probably already inside both the source and
  target support windows. Live verification is still mandatory.

Default decision:

- Do not upgrade PostgreSQL during the first production Nextcloud application
  migration if live PostgreSQL is confirmed as major 14 and healthy.
- Keeping PostgreSQL stable reduces the number of moving parts while moving
  Nextcloud across multiple major versions.
- A PostgreSQL major upgrade can be planned as a separate change before or
  after the Nextcloud migration, unless a specific intermediate Nextcloud major
  requires it.

Mandatory DB preflight:

```text
SELECT version();
SHOW server_version_num;
SELECT current_database(), current_user;
```

Ansible must compare the live PostgreSQL major against the supported range for
the current and target Nextcloud major before every upgrade step. If the live DB
major is outside either range, the pipeline must stop before touching
Nextcloud data.

Optional PostgreSQL migration path:

1. Treat PostgreSQL major migration as its own gated task, not as an implicit
   side effect of `docker compose up`.
2. Run it in staging first using a restored production backup.
3. Put Nextcloud in maintenance mode and stop cron/background writers.
4. Dump the configured Nextcloud database from the old PostgreSQL container
   using a logical dump, not a raw copy of the PostgreSQL data directory.
5. Create a new PostgreSQL container or Compose project with a new data path,
   for example `/mnt/user/appdata/postgres/<new-major>` or a dedicated
   Nextcloud DB path.
6. Create the Nextcloud DB role/database in the new PostgreSQL instance using
   Vault-managed credentials.
7. Restore the dump into the new PostgreSQL instance.
8. Compare old/new database metadata and critical table counts.
9. Update Nextcloud `dbhost` only after restore verification succeeds.
10. Start Nextcloud against the new DB and run full runtime verification.
11. Keep the old PostgreSQL container and data directory untouched until the
    operator explicitly approves retirement.

Recommended dump/restore shape:

```text
pg_dump -Fc <nextcloud_db> > nextcloud-<timestamp>.dump
createdb <nextcloud_db>
pg_restore --clean --if-exists --no-owner --role=<nextcloud_db_user> -d <nextcloud_db> nextcloud-<timestamp>.dump
```

The exact commands must be implemented by Ansible with Docker container context,
Vault-managed credentials, and no secret output in logs.

Critical DB migration checks:

- `pg_isready` succeeds on the new PostgreSQL container.
- `SELECT version()` reports the intended new major.
- Restored DB has the expected owner, encoding, collation, and table count.
- Critical tables have matching or expected row counts:
  - `oc_users`
  - `oc_accounts`
  - `oc_filecache`
  - `oc_storages`
  - `oc_share`
  - calendar/contact tables if enabled
- `occ status --output=json` succeeds against the new DB.
- `occ db:add-missing-columns --dry-run`,
  `occ db:add-missing-indices --dry-run`, and
  `occ db:add-missing-primary-keys --dry-run` are collected after the switch.

Stop conditions:

- Live PostgreSQL major is not supported by either the current or target
  Nextcloud major.
- The old DB cannot be dumped.
- The new DB cannot be restored and verified.
- Row-count comparisons show unexplained differences.
- Nextcloud cannot run `occ status` against the new DB.
- The DB host switch is not reversible from the latest backup and old DB.

## Data Safety Rules

These are hard requirements for all agents:

- Do not run `docker compose down -v`.
- Do not delete `/mnt/user/appdata/nextcloud`.
- Do not delete, recreate, or reinitialize the production Nextcloud database.
- Do not mount an old PostgreSQL data directory into a different PostgreSQL
  major version.
- Do not overwrite `config.php`.
- Do not regenerate `instanceid`, `passwordsalt`, or `secret`.
- Do not run downgrade images against the production data.
- Do not run a target image whose major version is more than one major above
  the current installed major.
- Do not proceed if `occ status` cannot be collected.
- Do not proceed if a fresh backup and restore test are not recorded.
- Do not proceed if the custom-image gate cannot verify every target release,
  image tag, and image digest.
- Do not proceed if PostgreSQL compatibility preflight fails.
- Do not proceed if SWAG cannot serve both `status.php` and static assets.
- Do not proceed if user verification for `hn581` and `hn583` is missing.

Same-major redeployment must be idempotent:

- `docker compose up -d` may recreate a container, but it must remount the same
  host paths and not touch data destructively.
- `occ upgrade` must be guarded by current/target version checks and should be
  a no-op on the same installed version.
- Cron sidecar deployment must be repeatable and must not create duplicate
  cron loops or host cron entries.
- Ansible tasks must use `changed_when` carefully for read-only checks.

## Backup and Restore Plan

The backup agent must implement and verify a backup before any staging or
production migration:

1. Put Nextcloud in maintenance mode.
2. Stop cron/background writers.
3. Capture `occ status --output=json`, `occ app:list --output=json`, and
   `occ config:list system --private --output=json` into a protected backup
   evidence folder. The private config capture must not be uploaded to CI
   artifacts unless encrypted.
4. Dump PostgreSQL with Vault-managed credentials.
5. Copy the Nextcloud config, custom apps, data, themes, and html directories
   to a timestamped backup path outside the live appdata tree.
6. Record ownership, permissions, file counts, and backup sizes.
7. Restore the backup into a staging path and staging database.
8. Prove the restored staging instance reaches `occ status` before production
   migration is allowed.
9. Turn production maintenance mode back off if this was only a rehearsal.

Backup contents must include:

```text
/mnt/user/appdata/nextcloud/config
/mnt/user/appdata/nextcloud/custom_apps
/mnt/user/appdata/nextcloud/data
/mnt/user/appdata/nextcloud/themes
/mnt/user/appdata/nextcloud/html
PostgreSQL database dump for the configured Nextcloud DB
Current SWAG nextcloud.subdomain.conf
Current DockerMan templates for Nextcloud and SWAG
```

## Staging Rehearsal Plan

Create a staging deployment before production:

- Restore production backup into a separate appdata tree such as
  `/mnt/user/appdata/nextcloud-upgrade-lab`.
- Restore the database into a separate database such as
  `nextcloud_upgrade_lab`.
- Use a separate Compose project and container names.
- Use a staging hostname such as `nextcloud-upgrade.houselab.page` or keep it
  reachable only from the Docker network.
- Disable outbound email in staging, or route SMTP to a sink.
- Run the full major-version sequence in staging first.
- Capture app compatibility issues and required config changes.
- Only promote the exact rehearsed sequence to production.

Staging is allowed to fail. Production is not the test environment.

## GitLab Pipeline Plan

The pipeline should use the existing protected runner model:

- Validation jobs: `homenas-unraid-validate`.
- Compose Manager file sync jobs: `homenas-unraid-boot-writer`.
- Docker/Ansible runtime verification jobs: `homenas-unraid-docker-admin` or an
  explicitly approved Ansible runner with the needed SSH/Vault secrets.

Recommended stages:

```text
smoke
lint
image-input-verify
ansible-syntax
compose-validate
dry-run
backup-check
deploy-compose-files
preflight-live
upgrade-major
post-upgrade
verify
rollback-readiness
```

Job requirements:

- Run only on protected branches/tags for deploy and upgrade jobs.
- Make production deploy and upgrade jobs manual.
- Require one manual job per major upgrade in production.
- Keep validation jobs unprivileged.
- Keep `/boot/config/plugins/compose.manager/projects` write access only in the
  boot-writer job.
- Keep Docker socket access only in Docker admin jobs.
- Do not expose Vault passwords, DB passwords, SMTP credentials, app passwords,
  or Nextcloud private config in logs or artifacts.

Pipeline checks:

- Verify the declared image manifest from `nextcloud_docker` is present.
- Verify the manifest reports release signature verification and passed smoke
  tests.
- Verify Docker Hub tag `rusman/nextcloud_cron_fmp:<tag>` exists.
- Verify the pushed Docker Hub tag resolves to the manifest digest.
- Verify live PostgreSQL major is supported by the current and planned
  Nextcloud major.
- `docker compose config --format json` for the Nextcloud Compose project.
- `ansible-playbook --syntax-check` for all Nextcloud playbooks.
- Ansible dry-run with `--check --diff`, where safe.
- Verify Compose references the approved custom image tag or digest.
- Verify no plaintext secrets were added to `.env`, Compose files, or docs.
- Verify Compose Manager destination file list is allowlisted.
- Verify the remote `/boot` project path receives only approved files.

## Ansible Design

Create these playbooks:

```text
ansible/playbooks/nextcloud/full_iac.yml
ansible/playbooks/nextcloud/deploy.yml
ansible/playbooks/nextcloud/preflight.yml
ansible/playbooks/nextcloud/backup.yml
ansible/playbooks/nextcloud/database_migration.yml
ansible/playbooks/nextcloud/upgrade_one_major.yml
ansible/playbooks/nextcloud/verify_iac.yml
ansible/playbooks/nextcloud/rollback_readiness.yml
```

Create `nextcloud_stack` role tasks:

```text
verify_compose.yml      Render and assert desired Compose config.
main.yml                Deploy Compose Manager files through compose_stack.
preflight.yml           Collect live status and block unsafe states.
upgrade_one_major.yml   Apply one image bump and run guarded upgrade checks.
post_upgrade.yml        Run background jobs, DB maintenance checks, and app checks.
verify_runtime.yml      Verify app, proxy, cron, DB, Redis, users, and headers.
```

Create `nextcloud_backup` role tasks:

```text
main.yml                Fresh backup workflow.
verify.yml              Verify backup file set and metadata.
restore_lab.yml         Restore to staging/lab only.
rollback_readiness.yml  Confirm rollback inputs exist and are usable.
```

Create `nextcloud_database` role tasks:

```text
verify_compatibility.yml  Check live PostgreSQL major against NC target support.
dump.yml                  Logical dump of the configured Nextcloud database.
restore.yml               Restore dump into a new PostgreSQL instance.
switch.yml                Safely update Nextcloud DB host after restore verification.
verify_migration.yml      Compare DB metadata/table counts and run Nextcloud checks.
```

Role variables should live in:

```text
ansible/inventories/prod/group_vars/homenas/nextcloud.yml
ansible/inventories/prod/group_vars/homenas/vault.yml
```

Expected non-secret vars:

```yaml
nextcloud_compose_source_dir: "{{ inventory_dir }}/../../../composeManager/projects/Nextcloud"
nextcloud_compose_file: docker-compose.yml
nextcloud_compose_stack_dir: "{{ unraid_compose_manager_projects_root }}/nextcloud"
nextcloud_compose_project_name: nextcloud
nextcloud_container_name: nextcloud_server
nextcloud_cron_container_name: nextcloud_cron
nextcloud_image_registry: docker.io
nextcloud_image_repository: rusman/nextcloud_cron_fmp
nextcloud_image_tag: "34.0.0"
nextcloud_image_digest: sha256:...
nextcloud_public_url: https://nextcloud.houselab.page:1443
nextcloud_public_host: nextcloud.houselab.page
nextcloud_appdata_root: /mnt/user/appdata/nextcloud
nextcloud_data_dir: /mnt/user/appdata/nextcloud/data
nextcloud_html_dir: /mnt/user/appdata/nextcloud/html
nextcloud_config_dir: /mnt/user/appdata/nextcloud/config
nextcloud_custom_apps_dir: /mnt/user/appdata/nextcloud/custom_apps
nextcloud_themes_dir: /mnt/user/appdata/nextcloud/themes
nextcloud_postgres_host: postgres_14
nextcloud_postgres_current_major: 14
nextcloud_postgres_target_major: null
nextcloud_postgres_migration_required: false
nextcloud_redis_host: Redis
nextcloud_docker_network: proxynet
nextcloud_expected_users:
  - hn581
  - hn583
```

Expected Vault vars:

```yaml
vault_nextcloud_postgres_backup_user: ...
vault_nextcloud_postgres_backup_password: ...
vault_nextcloud_smtp_password: ...        # only if future tasks manage SMTP
vault_nextcloud_test_hn581_app_password: ...
vault_nextcloud_test_hn583_app_password: ...
```

Do not move existing live `config.php` secrets into plaintext inventory.
Docker Hub credentials belong in the `nextcloud_docker` repo's CI/CD secret
store, not in the Nextcloud Server deployment inventory, unless this repo is
explicitly given image-publishing responsibilities later.

## SWAG Proxy Plan

The SWAG agent must implement automation before the production cutover:

1. Decide whether to keep `--volumes-from=nextcloud_server` temporarily or
   replace it with an explicit read-only mount of
   `/mnt/user/appdata/nextcloud/html:/var/www/html:ro`.
2. If keeping `--volumes-from`, confirm SWAG is restarted after the new Compose
   `nextcloud_server` container exists.
3. Update `nextcloud.subdomain.conf` against the current official Nextcloud
   Nginx guidance.
4. Preserve local requirements:
   - public host `nextcloud.houselab.page`
   - external HTTPS port `1443`
   - large upload limit near current `10368M`
   - FastCGI upstream `nextcloud_server:9000`
5. Verify `.well-known/carddav` and `.well-known/caldav` redirects through
   SWAG.
6. Run `nginx -t` inside SWAG before reload.
7. Reload SWAG without restarting if possible; restart only if static asset
   volume wiring requires it.

The SWAG role is currently a stale placeholder. Do not use it as an entry point
until it is implemented and verified.

## Pre-Deployment Integration Tests

Ansible preflight must collect and assert:

- Docker network `proxynet` exists.
- Containers `postgres_14`, `Redis`, `swag`, and `nextcloud_server` are
  present before migration.
- PostgreSQL live version is collected with `SELECT version()` and
  `SHOW server_version_num`.
- PostgreSQL major is supported by both the currently installed Nextcloud
  major and the next planned target major.
- `occ status --output=json` returns installed state and current version.
- Current major is the expected source major or an approved intermediate major.
- Current version is not higher than the planned image version.
- Maintenance mode is off before backup-only checks and on during backup.
- Config paths and data paths exist and are non-empty.
- `hn581` and `hn583` data directories exist.
- PostgreSQL accepts a connection and can be dumped.
- Redis responds to ping.
- SWAG Nginx config test passes.
- External `GET https://nextcloud.houselab.page:1443/status.php` returns
  installed and not maintenance.
- CalDAV/CardDAV `.well-known` redirects return expected locations.
- No pending unsupported third-party app blockers are detected.
- Latest backup and restore-test evidence is present.

## Post-Deployment Integration Tests

Ansible runtime verification must assert:

- Compose config matches the desired image, names, networks, and mounts.
- `nextcloud_server` is running.
- Cron sidecar or scheduled cron mechanism is present exactly once.
- `occ status --output=json` reports the target version and installed state.
- `occ check --output=json` is collected for review.
- `occ app:list --output=json` is collected and unexpected disabled apps are
  flagged.
- `php -f /var/www/html/cron.php` runs successfully two or three times after
  each major upgrade.
- Long-running DB maintenance checks are evaluated:
  - `occ db:add-missing-columns --dry-run`
  - `occ db:add-missing-indices --dry-run`
  - `occ db:add-missing-primary-keys --dry-run`
- External `status.php` works through SWAG.
- Static assets load through SWAG, not only PHP.
- WebDAV check succeeds for both active users using Vault-managed app
  passwords or operator-provided temporary test credentials.
- Each active user can list their root files over WebDAV.
- No user data path ownership drift is detected.
- The previous direct-media-move workflow still has a documented `occ
  files:scan` path.

## Rollback Plan

Rollback is restore, not downgrade.

If a production major upgrade fails after data migration:

1. Stop Nextcloud and cron containers.
2. Keep the failed appdata and DB untouched for forensic review.
3. Restore the last known-good appdata backup to a new clean path or after
   operator-approved replacement of the live path.
4. Drop/recreate and restore the PostgreSQL database from the matching backup.
5. Start the previous known-good image for the restored major.
6. Run `occ status`.
7. Run external `status.php`.
8. Ask both users to pause/resume clients only after the restored instance is
   verified.

Do not attempt to run an older Docker image against a database that was already
upgraded by a newer major.

## Agent Task Breakdown

### Agent 1: Live Discovery

Deliverables:

- `ansible/docs/NEXTCLOUD_LIVE_DISCOVERY.md`
- Redacted live-state JSON captures in a protected local evidence directory.

Tasks:

- Run read-only Docker and `occ` discovery.
- Verify actual Nextcloud version, enabled apps, disabled apps, background job
  mode, maintenance state, users, DB type, and data directory.
- Inventory Postgres, Redis, SWAG, and Docker network state.
- Confirm whether `dockerMan/templates-user` matches the actual running
  containers.
- Document all findings without secrets.

Stop conditions:

- `occ status` cannot run.
- Current version does not match the expected 26.x baseline.
- Existing config references paths or containers not present on Unraid.

### Agent 2: Backup and Restore

Deliverables:

- `ansible/roles/nextcloud_backup/`
- `ansible/playbooks/nextcloud/backup.yml`
- `ansible/playbooks/nextcloud/rollback_readiness.yml`
- Restore-test evidence.

Tasks:

- Implement fresh backup automation using maintenance mode and Vault-managed DB
  credentials.
- Implement backup verification.
- Implement staging restore workflow.
- Prove restore before production migration.

Stop conditions:

- Backup lacks config, data, database, custom apps, themes, or html.
- Restore test cannot produce a working `occ status`.

### Agent 3: Database Compatibility and Migration

Deliverables:

- `ansible/roles/nextcloud_database/`
- `ansible/playbooks/nextcloud/database_migration.yml`
- DB compatibility matrix in `ansible/docs/NEXTCLOUD_DATABASE_PLAN.md`
- Staging DB migration evidence if PostgreSQL major migration is needed.

Tasks:

- Verify live PostgreSQL version and compare it with each planned Nextcloud
  major in the migration path.
- Decide whether PostgreSQL stays on major 14 for the first production
  Nextcloud upgrade or whether a DB migration is mandatory.
- Implement logical dump/restore tasks for the configured Nextcloud database.
- If migrating PostgreSQL, create a new PostgreSQL container/data path rather
  than reusing the old PostgreSQL data directory with a new major.
- Verify restored DB metadata and critical table counts before switching
  Nextcloud `dbhost`.
- Keep old PostgreSQL data untouched until operator-approved retirement.

Stop conditions:

- Current or target Nextcloud major does not support the live PostgreSQL major.
- DB dump or restore fails.
- Critical table counts do not match expected values.
- `occ status` fails against the migrated DB.

### Agent 4: Image Handoff Contract

Deliverables:

- `ansible/docs/NEXTCLOUD_IMAGE_CONTRACT.md`
- Image manifest schema for outputs produced by `hn583/nextcloud_docker`.
- Variables in `nextcloud.yml` or Compose `.env` that declare the consumed
  image tag and digest.

Tasks:

- Document that Dockerfile/image IaC lives in the self-hosted GitLab
  `hn583/nextcloud_docker` project.
- Define the manifest fields this repo requires from the image pipeline:
  repository, tag, digest, Nextcloud version, source commit, Dockerfile path,
  release URL, signature verification result, and smoke-test result.
- Define how the Nextcloud Server pipeline receives the manifest: committed
  file, GitLab artifact download, manual variable, or protected CI variable.
- Require the manifest for every intermediate major upgrade image.
- Keep Docker Hub repository name `rusman/nextcloud_cron_fmp`.

Stop conditions:

- This repo starts owning Dockerfile/image build implementation.
- The image manifest does not include digest or source commit.
- The image manifest does not prove release verification and smoke tests.
- The tag/digest contract for an intermediate major is missing.

### Agent 5: Compose Project

Deliverables:

- `composeManager/projects/Nextcloud/docker-compose.yml`
- `composeManager/projects/Nextcloud/.env`
- `composeManager/projects/Nextcloud/name`
- `composeManager/projects/Nextcloud/README.md`

Tasks:

- Model the FPM app service with container name `nextcloud_server`.
- Point the app and cron services at the approved Houselab custom image tag or
  digest from the `nextcloud_docker` image manifest.
- Model cron as a separate service or document a host schedule if chosen.
- Reuse the existing appdata paths.
- Use external `proxynet`, `postgres_14`, and `Redis`.
- Add healthchecks that do not require secrets.
- Keep `.env` free of secrets.

Stop conditions:

- Compose would create a new empty data volume.
- Compose would change the DB host/database without an explicit migration.
- Compose cannot preserve the SWAG FastCGI/static file behavior.
- Compose references an unapproved or mutable image tag.

### Agent 6: Ansible Nextcloud Role

Deliverables:

- `ansible/roles/nextcloud_stack/`
- `ansible/playbooks/nextcloud/*.yml`
- Inventory vars in `nextcloud.yml`.

Tasks:

- Reuse `compose_stack` for Compose Manager deployment.
- Add `verify_compose`, `preflight`, `upgrade_one_major`,
  `post_upgrade`, and `verify_runtime` tasks.
- Include `nextcloud_database` compatibility checks in preflight and per-major
  upgrade gates.
- Verify the deployed image tag/digest matches the approved image manifest.
- Enforce one-major-at-a-time upgrades.
- Make same-major redeploy idempotent.
- Hide secret-bearing task output with `no_log: true`.

Stop conditions:

- Role can run an unsafe target version.
- Role needs plaintext secrets.
- Role cannot distinguish dry-run from live migration.
- Role cannot prove the running image digest.

### Agent 7: GitLab CI Pipeline

Deliverables:

- Updated `.gitlab-ci.yml`.
- Pipeline docs under `ansible/docs/`.

Tasks:

- Add protected validation, image input verification, syntax, compose
  validation, dry-run, deploy, preflight, upgrade, and verify stages.
- Route jobs to the correct protected runners by tag.
- Verify Docker Hub tag/digest against the `nextcloud_docker` manifest.
- Verify PostgreSQL compatibility before deploy/upgrade jobs.
- Make production backup/deploy/upgrade jobs manual.
- Add one manual job per major version.
- Add secret-scan checks for accidental plaintext values.

Stop conditions:

- A production job can run automatically from an unprotected branch.
- A validation job has Docker socket or `/boot` write access.
- Secrets appear in job output.
- A deployment job can run without a verified image manifest.
- Compose references a tag/digest that differs from the approved manifest.

### Agent 8: SWAG Proxy

Deliverables:

- Implemented `ansible/roles/swag_proxy/`.
- Updated SWAG config in `/home/rusman/GitRepos/unraid-swag-config`.
- Verification playbook for `nginx -t`, reload, and external route checks.

Tasks:

- Update Nextcloud proxy config against current official Nginx guidance.
- Resolve the static file mount strategy.
- Verify FastCGI upstream and external port `1443`.
- Verify `.well-known` redirects.
- Keep GitLab SWAG behavior untouched.

Stop conditions:

- Static assets cannot be served.
- `nginx -t` fails.
- Nextcloud route changes would affect GitLab route.

### Agent 9: Staging Migration

Deliverables:

- Staging migration runbook.
- Staging migration logs and version checkpoints.

Tasks:

- Restore production backup into staging.
- Consume the same verified `nextcloud_docker` image manifest planned for
  production.
- Rehearse PostgreSQL logical dump/restore if DB migration is required or
  operator-approved.
- Run each major upgrade in staging with the same Ansible workflow planned for
  production.
- Record every version transition and any app disables.
- Verify both users in staging.
- Produce the final production sequence.

Stop conditions:

- Any major upgrade requires manual repair not captured in IaC.
- User data or app state is missing in staging.

### Agent 10: Production Migration

Deliverables:

- Production migration record with timestamps, backup ID, image tags, versions,
  and verification output.

Tasks:

- Confirm maintenance window.
- Confirm users have paused sync clients or accepted downtime.
- Run final fresh backup.
- Confirm every intermediate custom image is built, pushed, and digest-recorded.
- Confirm PostgreSQL compatibility preflight passes or the rehearsed DB
  migration has completed.
- Apply one major at a time with manual gates.
- Run post-upgrade tests after each major.
- Stop if any custom image digest is missing or does not match the approved
  manifest.

Stop conditions:

- Any verification failure.
- Any unexpected data ownership change.
- Any unavailable or unverified custom image tag.
- Any PostgreSQL compatibility or DB migration verification failure.
- Any app incompatibility affecting active users.

### Agent 11: User Acceptance and Operations

Deliverables:

- User acceptance checklist for `hn581` and `hn583`.
- Updated operator runbook.

Tasks:

- Verify browser login, file listing, upload/download, mobile/desktop sync,
  WebDAV, shares, calendar/contact if used, and 2FA.
- Update the media move script if container names or scan commands changed.
- Document routine redeploy and rollback commands.

Stop conditions:

- Either active user cannot access expected files/profile state.
- Sync clients report widespread conflict or re-download behavior.

## Open Questions

- Confirm whether the running live container version is truly `26.0.0.11` or
  whether the Docker image upgrade to `26.0.13` has already completed partially.
- Confirm the exact self-hosted GitLab project URL for `hn583/nextcloud_docker`
  and the artifact/API path this repo should use to retrieve image manifests.
- Confirm whether the approved image manifest should be committed to this repo
  or consumed from `nextcloud_docker` pipeline artifacts at deploy time.
- Confirm whether Docker Hub remains the only production registry or whether
  `nextcloud_docker` should also mirror the same image to the local GitLab
  registry later.
- Confirm which Houselab-specific packages, PHP extensions, config fragments,
  hooks, and cron behavior from `rusman/nextcloud_cron_fmp` must be retained in
  the new image.
- Confirm whether direct filesystem mutations into the Nextcloud data directory
  still happen outside the documented media move script.
- Confirm whether both active users can provide temporary app passwords for
  automated WebDAV verification.
- Confirm where backups should be stored and retained on Unraid.

## References

- Nextcloud official changelog: https://nextcloud.com/changelog/
- Nextcloud upgrade guidance: https://docs.nextcloud.com/server/latest/admin_manual/maintenance/upgrade.html
- Nextcloud release schedule: https://docs.nextcloud.com/server/latest/admin_manual/release_schedule.html
- Nextcloud latest system requirements: https://docs.nextcloud.com/server/latest/admin_manual/installation/system_requirements.html
- Nextcloud 26 system requirements: https://docs.nextcloud.com/server/26/admin_manual/installation/system_requirements.html
- Nextcloud background jobs: https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/background_jobs_configuration.html
- Nextcloud backup: https://docs.nextcloud.com/server/latest/admin_manual/maintenance/backup.html
- Nextcloud restore: https://docs.nextcloud.com/server/latest/admin_manual/maintenance/restore.html
- Nextcloud system requirements: https://docs.nextcloud.com/server/latest/admin_manual/installation/system_requirements.html
- Nextcloud reverse proxy guidance: https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/reverse_proxy_configuration.html
- Nextcloud Nginx guidance: https://docs.nextcloud.com/server/latest/admin_manual/installation/nginx.html
- Nextcloud memory caching guidance: https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/caching_configuration.html
- Nextcloud official Docker README: https://github.com/nextcloud/docker
- Nextcloud Server source repository: https://github.com/nextcloud/server
- Nextcloud release artifacts repository: https://github.com/nextcloud-releases/server
- Nextcloud 34.0.0 tarball: https://download.nextcloud.com/server/releases/nextcloud-34.0.0.tar.bz2
- Nextcloud 34.0.0 checksum/signature files: https://download.nextcloud.com/server/releases/
- Docker Hub tags for `rusman/nextcloud_cron_fmp`: https://hub.docker.com/r/rusman/nextcloud_cron_fmp/tags
