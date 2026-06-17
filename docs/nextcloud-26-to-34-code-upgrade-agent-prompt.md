# Agent Prompt: Review and Upgrade Nextcloud Image Code

You are the next engineering agent working on the Houselab Nextcloud image
upgrade.

Start here:

```text
/home/rusman/GitRepos/nextcloud_docker
docs/nextcloud-26-to-34-researched-upgrade-plan.md
```

Read the researched upgrade plan completely before changing files. Treat it as
the local project source of truth for version path, QA/PROD isolation, CI
constraints, and known official-source findings. Verify any new version,
requirement, or upgrade-policy claim against official Nextcloud documentation
before relying on it.

## Objective

Review and upgrade the image code the operator provides so this repository can
build the required one-major-at-a-time Nextcloud images from the confirmed
production start point to the approved Nextcloud 34 target.

Confirmed production start:

```json
{"installed":true,"version":"26.0.0.11","versionstring":"26.0.0","edition":"","maintenance":false,"needsDbUpgrade":false,"productname":"Nextcloud","extendedSupport":false}
```

Required path:

```text
26.0.0 -> 26.0.13 -> 27.1.11 -> 28.0.14 -> 29.0.16 -> 30.0.17 -> 31.0.14 -> 32.0.11 -> 33.0.5 -> 34.0.0
```

Do not skip majors. If official docs appear to support a shorter path, stop and
record the exact official exception before changing implementation.

## Repository Boundary

This image repository owns:

- Dockerfiles and image source trees.
- Entrypoints, cron scripts, `upgrade.exclude`, and image-bundled config
  snippets.
- GitLab CI image validation, release verification, smoke tests, publishing,
  digest verification, and manifests.
- QA and PROD image tags/manifests.

The deployment/IaC repository owns:

- Compose/Ansible deployment.
- Host volume mounts.
- PostgreSQL and Redis runtime service bindings.
- QA/PROD runtime separation.
- Secrets.

Do not modify the deployment repository unless the operator explicitly asks you
to switch repositories.

## Current Worktree Warning

There may be uncommitted operator work, including versioned directory
restructuring under `26/` and new target-major image code. Preserve user
changes. Do not revert unrelated files. If a file has user changes and you need
to edit it, read it first and work with the current contents.

## Required Files To Review

Read these before proposing or making changes:

```text
docs/nextcloud-26-to-34-researched-upgrade-plan.md
docs/custom-image-build.md
docs/gitlab-ci-hardening-plan.md
.gitlab-ci.yml
ci/verify-release.sh
ci/smoke-test.sh
ci/verify-published-digest.sh
ci/generate-manifest.sh
34/fpm/Dockerfile
34/fpm/entrypoint.sh
34/fpm/cron.sh
34/fpm/upgrade.exclude
34/fpm/config/
```

Also review every operator-provided image tree relevant to the upgrade path,
especially any directories matching:

```text
26/**/Dockerfile
26/**/entrypoint.sh
26/**/cron.sh
26/**/upgrade.exclude
26/**/config/
27/**/Dockerfile
28/**/Dockerfile
29/**/Dockerfile
30/**/Dockerfile
31/**/Dockerfile
32/**/Dockerfile
33/**/Dockerfile
34/**/Dockerfile
```

Use `rg --files` and `git status --short` first so you understand the current
layout and dirty worktree.

## Official Source Requirement

Use official Nextcloud sources for:

- Upgrade policy.
- Latest point release per major.
- PHP runtime support.
- Database requirements.
- Critical changes.
- Redis/cache requirements.
- PostgreSQL requirements.
- App compatibility notes where applicable.

Primary sources:

```text
https://docs.nextcloud.com/server/stable/admin_manual/maintenance/upgrade.html
https://docs.nextcloud.com/server/stable/admin_manual/installation/system_requirements.html
https://docs.nextcloud.com/server/stable/admin_manual/configuration_database/linux_database_configuration.html
https://docs.nextcloud.com/server/stable/admin_manual/configuration_server/caching_configuration.html
https://nextcloud.com/changelog/
https://download.nextcloud.com/server/releases/
```

Use archived official docs for older majors when reviewing PHP/database
requirements, for example `https://docs.nextcloud.com/server/30/...`.

## Image Review Requirements

For every target image tree you touch or approve, review and document:

1. `FROM` image:
   - Must be a PHP FPM base supported by that target Nextcloud major.
   - Do not start from the previous major's Nextcloud image and swap PHP
     underneath it.
   - Do not use PHP 8.4 for target majors whose official requirements do not
     list PHP 8.4.

2. OS packages:
   - Keep installed packages minimal.
   - Include only libraries needed by required PHP extensions or runtime
     scripts.
   - Do not install PostgreSQL, MySQL/MariaDB, Redis, or memcached server
     daemons in the application image.

3. PHP extensions:
   - Required: PostgreSQL client support via `pdo_pgsql`, Redis PHP extension,
     APCu, and the Nextcloud-required modules for the target version.
   - Preserve locally needed extensions such as LDAP, imagick, GD, intl, zip,
     gmp, exif, pcntl, and sysvsem where still supported and needed.
   - Do not include MySQL/MariaDB extensions such as `mysqli` or `pdo_mysql`
     unless the operator explicitly changes the PostgreSQL-only requirement.

4. Nextcloud source:
   - Docker build must consume verified release artifacts from CI or an
     equivalent verified handoff.
   - Dockerfile must not download the Nextcloud release archive a second time.
   - Copying target server code into `/usr/src/nextcloud` is necessary but not
     sufficient; it is only the immutable source payload for the image.

5. Entrypoint behavior:
   - Review every `entrypoint.sh`.
   - It must preserve mounted `/var/www/html` runtime state, sync
     `/usr/src/nextcloud` safely, preserve config/data/custom apps/themes,
     enforce one-major-at-a-time upgrades, and run or allow `occ upgrade`.
   - It must not silently overwrite production config, data, custom apps, or
     themes.
   - It must not expose secrets in logs.

6. `upgrade.exclude`:
   - Review every target version's `upgrade.exclude`.
   - It must protect runtime-owned paths and avoid deleting or replacing
     mounted config, data, custom apps, themes, and local runtime files.

7. `cron.sh`:
   - Review every target version's `cron.sh`.
   - It should run `cron.php` under the web-server user and match the FPM image
     model.

8. `config/*`:
   - Review all bundled config snippets per major.
   - Keep runtime secrets out of image code.
   - PostgreSQL and Redis bindings are deployment-owned.
   - QA Redis `dbindex` and `memcache_customprefix` are deployment-owned unless
     the operator explicitly asks for image-level support.
   - Ensure any config snippet remains compatible with the target major.

9. CI variables and manifests:
   - Intermediate targets must set matching `NEXTCLOUD_VERSION`,
     `RELEASE_URL`, `RELEASE_ASC_URL`, `RELEASE_SHA256_URL`,
     `DOCKER_CONTEXT`, and `DOCKERFILE_PATH`.
   - QA publishing must produce QA tags/manifests only.
   - PROD publishing must produce production tags/manifests only.
   - Do not use `latest` as a deployment selector.

## Expected Implementation Direction

Prefer a small, maintainable implementation over duplicating fragile code.
Acceptable options:

- Versioned image directories per required target major.
- A parameterized build layout, if it preserves reviewability and CI artifact
  handoff.
- Shared scripts/templates only when they make the one-major image set easier
  to audit.

Do not refactor unrelated historical image variants unless required for the
upgrade path.

## Required Local Verification

Allowed locally:

```text
rg
sed
git diff
git diff --check
bash -n ci/*.sh
sh -n **/*.sh
YAML parse/lint if available
```

Do not run locally:

```text
docker build
docker run
docker push
ci/verify-release.sh
ci/smoke-test.sh
ci/verify-published-digest.sh
any helper that downloads, builds, runs, pushes, or verifies live artifacts
```

Actual image construction, release verification, smoke testing, and Docker Hub
publishing belong in GitLab CI.

## Stop Conditions

Stop and ask the operator if:

- Official docs contradict the researched upgrade plan.
- Official docs are ambiguous about a proposed major skip.
- Live `occ status` no longer matches the confirmed 26.0.0 starting point.
- A target major's latest point release cannot be verified from official
  sources.
- A target image would require unsupported PHP.
- A target image would require MySQL/MariaDB support.
- A required PHP extension cannot be built on the selected PHP/Debian base.
- Entrypoint behavior cannot be proven to preserve mounted runtime state.
- QA cannot be isolated from production volumes, PostgreSQL, and Redis.
- Backup or restore-test evidence is missing.
- A third-party app blocks an upgrade and needs an operator decision.
- Any step would expose Docker Hub credentials, runtime secrets, database
  passwords, SMTP passwords, or Nextcloud instance secrets in Git, CI logs, or
  plain files.
- Required GitLab runner, Docker Hub credential, or protected-variable setup is
  missing.

## Final Response Expectations

When done, summarize:

- Files changed.
- Which image trees were reviewed.
- Which PHP bases and extension sets were selected per target major.
- Entrypoint, `upgrade.exclude`, `cron.sh`, and config findings.
- CI changes made.
- Static checks run.
- What still needs GitLab CI validation.
- Remaining operator decisions.

