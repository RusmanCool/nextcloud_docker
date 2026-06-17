# Agent Prompt: Research and Plan Nextcloud 26 to 34 Upgrade

You are the next engineering agent working on the Houselab Nextcloud upgrade.

Start here:

```text
/home/rusman/GitRepos/nextcloud_docker
docs/nextcloud-26-to-34-upgrade-handoff.md
```

Read the handoff spec completely before changing files. Treat it as the source
of local project intent, but verify all upgrade-policy claims against official
Nextcloud documentation before relying on them.

## Objective

Create a researched, operator-ready plan to upgrade the current Nextcloud 26
deployment to the approved Nextcloud 34 target while preserving production data
and keeping QA fully isolated from PROD.

You must determine whether Nextcloud major versions can be skipped. Do not
assume the answer. Research official Nextcloud docs and record the reason behind
the rule, any official exceptions, and whether any shorter path such as
`26 -> 28 -> 30 -> 32 -> 34` is officially supported.

## Repositories and Ownership

Image repository:

```text
/home/rusman/GitRepos/nextcloud_docker
self-hosted GitLab project: hn583/nextcloud_docker
Docker Hub repository: rusman/nextcloud_cron_fmp
```

Deployment/IaC repository is separate. Do not modify it unless the operator
explicitly asks you to switch repositories.

This image repository owns:

- Dockerfile and image source.
- GitLab CI image build, smoke test, publish, digest verification, and manifests.
- QA and PROD image tags/manifests.

The deployment repository owns:

- Compose/Ansible deployment.
- Host volume mounts.
- PostgreSQL/Redis runtime service bindings.
- QA/PROD environment separation.

## Required Local Files To Review

Read these before proposing changes:

```text
docs/nextcloud-26-to-34-upgrade-handoff.md
docs/custom-image-build.md
docs/gitlab-ci-hardening-plan.md
.gitlab-ci.yml
34/fpm/Dockerfile
34/fpm/entrypoint.sh
34/fpm/config/
ci/verify-release.sh
ci/smoke-test.sh
ci/verify-published-digest.sh
ci/generate-manifest.sh
```

There may be uncommitted work. Preserve user changes. Do not revert unrelated
files.

## Official Source Requirement

Use official Nextcloud sources for upgrade policy and version decisions.

Required sources:

```text
https://docs.nextcloud.com/server/stable/admin_manual/maintenance/upgrade.html
https://docs.nextcloud.com/server/stable/admin_manual/configuration_database/linux_database_configuration.html
https://docs.nextcloud.com/server/stable/admin_manual/configuration_server/caching_configuration.html
https://nextcloud.com/changelog/
https://download.nextcloud.com/server/releases/
```

Use additional official Nextcloud pages as needed, especially critical changes,
PHP requirements, database requirements, Redis/cache requirements, and app
compatibility notes.

Do not base the major-version skip decision on memory, guesses, non-official
forum comments, or the fact that a test appears to work once.

## Major-Version Skip Research

You must answer these questions with official citations:

1. Does official Nextcloud documentation allow skipping major versions?
2. If not, why not?
3. If exceptions exist, what exact starting and ending versions are covered?
4. Do any exceptions apply to Docker/container deployments?
5. Do any exceptions apply to a production instance with existing users, files,
   shares, calendars, contacts, app passwords, third-party apps, and 2FA?
6. Are background migrations required to finish before another major upgrade?
7. What commands/checks does Nextcloud recommend before and after each upgrade?

Evaluate these candidate paths explicitly:

```text
26 -> 28
28 -> 30
30 -> 32
32 -> 34
26 -> 34
```

For each candidate, produce a decision table:

```text
candidate_path:
officially_supported: yes/no
official_source:
official_wording_summary:
applies_to_container_deployment: yes/no/unknown
applies_to_existing_production_data: yes/no/unknown
requires_latest_source_major_point_release: yes/no
requires_latest_target_major_point_release: yes/no
requires_background_migrations_before_next_step: yes/no
known_risks:
required_QA_tests:
decision: reject/consider/approve
```

Reject a skip unless an official Nextcloud source explicitly supports that exact
path.

## QA and PROD Requirements

QA must never touch production resources.

QA must use:

- QA-specific Nextcloud app/html volume.
- QA-specific data volume.
- QA-specific config volume.
- QA-specific custom apps and themes volumes.
- QA-specific PostgreSQL database and user, or a separate QA PostgreSQL
  container.
- QA-specific Redis logical DB index and cache prefix, or a separate QA Redis
  container.
- QA-specific hostname.
- QA secrets stored outside Git.

Redis terminology matters. Redis does not have SQL tables. For QA isolation use
`redis.dbindex` and `memcache_customprefix`, or a separate Redis container.

PostgreSQL terminology matters. PostgreSQL should use a separate QA database
and QA user at minimum. A separate QA PostgreSQL container is safer. Do not call
this a PostgreSQL "index".

PROD must consume only a production manifest:

```text
deployment_environment: "prod"
published: true
image_digest: "sha256:..."
```

QA manifests must not be used for PROD.

## Image Pipeline Constraints

The current pipeline intent is:

- Manual GitLab UI pipelines only.
- `PUBLISH_IMAGE=false` validates only.
- `PUBLISH_IMAGE=true` publishes only after build and smoke tests pass.
- `DEPLOYMENT_ENV=qa` publishes QA tags/manifests.
- `DEPLOYMENT_ENV=prod` publishes PROD tags/manifests.
- Docker Hub credentials stay only in protected/masked GitLab CI variables.
- No Docker Hub credentials, runtime secrets, DB passwords, SMTP passwords, or
  Nextcloud instance secrets may be committed.
- The Docker build must not download the Nextcloud release archive a second
  time. Release files must come from the verified CI release artifacts or an
  equivalent verified handoff.
- Do not use `latest` as a deployment selector.
- The image must support PostgreSQL and external Redis.
- The image must not include MySQL/MariaDB support or Redis/PostgreSQL/MySQL
  server daemons.

## Expected Deliverables

Produce or update documentation with:

1. A researched version matrix from 26 to 34.
   - Latest point release per major.
   - Official release URL.
   - Checksum/signature URLs.
   - PHP and database requirements.
   - Critical changes.

2. A major-skip decision report.
   - Include the required decision table for each candidate skip path.
   - Explain why a skip is rejected or considered.
   - Cite official Nextcloud sources.

3. A QA-first upgrade plan.
   - Exact QA image tags/manifests per major.
   - QA PostgreSQL and Redis isolation requirements.
   - QA host volume paths.
   - QA validation checks.

4. A PROD upgrade runbook.
   - Backup and restore-test gates.
   - Maintenance-mode steps.
   - Per-major deployment commands or clear pseudocode.
   - `occ` migration/repair commands.
   - Acceptance checks.
   - Rollback stop points.

5. CI/image changes if needed.
   - Keep changes scoped.
   - Preserve the no-local-build rule.
   - Run only static checks locally.

## Verification Rules

Local developer checkout may run:

```text
rg
sed
git diff
git diff --check
bash -n ci/*.sh
sh -n 34/fpm/*.sh
YAML parse/lint if available
```

Do not run locally:

```text
docker build
docker run
docker push
CI helper scripts that download, build, run, push, or verify live artifacts
```

Actual image construction and smoke testing belong in GitLab CI.

## Stop Conditions

Stop and ask the operator if:

- Official docs are ambiguous about a proposed major skip.
- Official docs contradict the local handoff.
- Current live `occ status` does not match the assumed Nextcloud 26 starting
  point.
- QA cannot be isolated from production volumes, PostgreSQL, and Redis.
- A backup or restore test is missing.
- A third-party app blocks an upgrade and needs an operator decision.
- A step requires MySQL/MariaDB support.
- A step requires exposing secrets in Git, CI logs, or plain files.
- A needed GitLab runner, Docker Hub credential, or protected-variable setup is
  missing.

## Final Response Expectations

When done, summarize:

- Whether official docs allow any major-version skip.
- The recommended path from 26 to 34.
- The QA/PROD isolation model.
- Files changed.
- Static checks run.
- Remaining operator decisions.
