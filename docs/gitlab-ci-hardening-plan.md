# GitLab CI/CD Hardening Plan

## Objective

Harden the `hn583/nextcloud_docker` GitLab CI/CD flow so image construction,
smoke testing, publishing, digest verification, and manifest generation happen
only from an operator-triggered pipeline.

The pipeline must not start automatically from a Git push.

## Implemented State

The hardened pipeline now uses top-level `workflow: rules` that allow only
manual GitLab UI pipelines where `CI_PIPELINE_SOURCE == "web"`. Push pipelines,
merge request pipelines, schedules, API pipelines, parent pipelines, and all
other sources are rejected by default.

The default manual run is validation-only:

- `PUBLISH_IMAGE=false`
- release archive checksum and PGP signature are verified
- the image is built and smoke-tested in GitLab CI
- Docker Hub login and push commands do not run
- `artifacts/nextcloud-image-validation.yaml` is produced with
  `published: false` and `image_digest: null`

Publishing requires an operator to set `PUBLISH_IMAGE=true` at pipeline start.
Only then does the gated publish job require Docker Hub secrets, push approved
tags, verify remote digests, and produce
`artifacts/nextcloud-image-manifest.yaml` with a real Docker Hub digest.

## Required Operator Flow

The operator starts the pipeline from GitLab:

1. Open the `hn583/nextcloud_docker` project in self-hosted GitLab.
2. Go to `Build > Pipelines > Run pipeline`.
3. Select the branch or tag from GitLab's built-in ref dropdown.
4. Set trigger-time variables, including whether Docker Hub publishing is
   allowed for this run.
5. Start the pipeline manually.

The selected GitLab ref is the source of truth for the pipeline code and image
source. Do not implement a separate script-level checkout that builds a
different branch from the one selected in the Run Pipeline UI.

## Pipeline Trigger Rules

Use `workflow: rules` to reject automatic pipeline sources.

Allowed:

- `CI_PIPELINE_SOURCE == "web"` for manual UI runs.

Optional later, only if explicitly approved:

- `CI_PIPELINE_SOURCE == "api"` for controlled automation.

Rejected:

- `push`
- `merge_request_event`
- `schedule`
- `parent_pipeline`
- any other source not explicitly allowed

The intent is that pushing a commit to any branch creates no pipeline.

## Trigger-Time Parameters

Define pipeline variables in `.gitlab-ci.yml` with clear descriptions and safe
defaults.

Required parameters:

- `PUBLISH_IMAGE`
  - Default: `false`
  - Options: `false`, `true`
  - Meaning: when `false`, the pipeline may verify, construct, and smoke-test
    the image, but must not log in to Docker Hub or push tags.
- `BUILD_NEXTCLOUD_IMAGE`
  - Default: `true`
  - Options: `false`, `true`
  - Meaning: when `false`, the pipeline can run shared runtime/verifier image
    maintenance without verifying or building a Nextcloud server image.
The published image tag is not operator-selected. When `PUBLISH_IMAGE=true`,
the pipeline publishes exactly one environment-neutral artifact tag:
`<NEXTCLOUD_VERSION>-houselab.<CI_PIPELINE_ID>`.

Shared image controls:

- `USE_RUNTIME_IMAGE`
  - Default for the current 26.0.13 target: `true`
  - Meaning: resolve a shared PHP runtime image before building the Nextcloud
    server image.
- `FORCE_REBUILD_RUNTIME`
  - Default: `false`
  - Meaning: build the shared runtime image instead of requiring an existing
    Docker Hub or local image.
- `USE_RELEASE_VERIFIER_IMAGE`
  - Default for the current 26.0.13 target: `true`
  - Meaning: resolve a shared release verifier image before building the
    Nextcloud server image.
- `FORCE_REBUILD_VERIFIER`
  - Default: `false`
  - Meaning: build the shared verifier image instead of requiring an existing
    Docker Hub or local image.

Branch selection should use GitLab's built-in branch/tag dropdown on the Run
Pipeline page. A separate `BRANCH_TO_USE` variable should be avoided unless
there is a later API-driven use case that truly requires it.

## Stage Layout

Stages:

- `static`
- `verify_release`
- `runtime`
- `verifier`
- `nextcloud`
- `manifest`

`static`:

- Check YAML syntax where practical.
- Check shell script syntax.
- Check Dockerfile formatting with an approved static checker if available.
- Do not construct an image in this stage.

`verify_release`:

- Run only when `BUILD_NEXTCLOUD_IMAGE == "true"`.
- Download the pinned Nextcloud release archive, checksum file, signature, and
  public signing key.
- Verify checksum.
- Verify PGP signature and expected fingerprint.
- Publish only verified release files, verification artifacts, and dotenv values
  needed by later jobs.
- Upload trusted verification artifacts only on successful job completion, so a
  failed checkout or script cannot publish stale files from a reused runner
  workspace.

`runtime`:

- Run only when `USE_RUNTIME_IMAGE == "true"`.
- Resolve the configured runtime image from Docker Hub only for Docker Hub
  image refs, then pull and archive it for downstream jobs.
- If Docker Hub is unavailable or the image does not exist, fall back to the
  local Docker daemon.
- If neither remote nor local image exists, build only when
  `FORCE_REBUILD_RUNTIME == "true"`; otherwise fail with a clear message.

`verifier`:

- Run only when `USE_RELEASE_VERIFIER_IMAGE == "true"`.
- Apply the same remote, local, and force-rebuild behavior for the shared
  release verifier image.

`nextcloud`:

- Run only when `BUILD_NEXTCLOUD_IMAGE == "true"`.
- Construct the image inside GitLab CI only.
- Use only the verified release artifacts from the `verify_release` job for
  Nextcloud source code. The Docker build must not download the Nextcloud
  release archive, checksum, signature, or signing key a second time.
- Run image smoke tests inside GitLab CI only.
- Load runtime and verifier image archives from upstream jobs when those shared
  images are enabled.
- Push exactly one environment-neutral Nextcloud artifact tag when
  `PUBLISH_IMAGE == "true"` and verify that the pushed tag resolves to a real
  digest.

`manifest`:

- Run only when `BUILD_NEXTCLOUD_IMAGE == "true"`.
- For non-publishing runs, publish a validation manifest or build report that
  clearly states no Docker Hub digest was produced.
- For publishing runs, publish an environment-neutral artifact manifest
  containing the real Docker Hub digest, selected ref, source commit, CI
  pipeline URL, release verification results, and smoke-test result.

## Publishing Safety Gates

Publishing must require all of the following:

- Manual pipeline source: `CI_PIPELINE_SOURCE == "web"`.
- Trigger variable: `PUBLISH_IMAGE == "true"`.
- Successful release checksum verification.
- Successful release PGP verification.
- Successful image construction.
- Successful image smoke tests.
- Docker Hub credentials available only as protected/masked GitLab CI/CD
  variables.
- Successful Docker Hub push.
- Successful pushed digest verification.

If any gate fails, no published artifact manifest with a Docker Hub digest
should be produced.

## Docker Hub Tag Policy

Do not publish or consume `latest`.

Required publish tags when `PUBLISH_IMAGE=true`:

- One pipeline-scoped artifact tag, for example
  `rusman/nextcloud_cron_fmp:34.0.0-houselab.<pipeline-id>`.

Downstream deployment should consume the manifest digest, for example
`rusman/nextcloud_cron_fmp@sha256:...`, and promote that same digest through
QA and PROD. QA/PROD separation belongs to deployment IaC and runtime
configuration.

## Manifest Requirements

The published artifact manifest is valid only after a publishing run. It must
include:

- `image_repository`
- `artifact_scope`
- `image_tag`
- `image_digest`
- `image_pull_by_digest`
- `nextcloud_version`
- `source_project`
- `source_commit`
- `source_ref`
- `dockerfile_path`
- `release_url`
- `release_signature_verified`
- `release_checksum_verified`
- `smoke_tests_passed`
- `published_at`
- `ci_pipeline_url`

For non-publishing runs, use a separate validation artifact name or include an
explicit field such as:

```yaml
published: false
image_digest: null
```

The downstream Unraid deployment pipeline must consume only a matching manifest
from a publishing run. The same digest should be promoted through QA and PROD;
environment separation belongs to deployment IaC.

## Hardening Task Status

1. Done: added `workflow: rules` that allow only manual web pipelines.
2. Done: split validation into shared-image resolution, `nextcloud`, and
   `manifest` jobs.
3. Done: added trigger-time variables with safe defaults and dropdown options.
4. Done: Docker Hub login and push commands exist only in jobs that publish
   selected artifacts.
5. Done: manifest generation distinguishes validation-only artifacts from
   production deployment manifests.
6. Done: CI targets the protected Docker-socket image-build runner tagged
   `homenas-docker-image-build` instead of Docker-in-Docker.
7. Operational prerequisite: confirm Docker Hub variables are protected/masked
   and scoped to the intended protected refs if protected refs are used.
8. Operational prerequisite: confirm the `homenas` group runner is available to
   the `hn583/nextcloud_docker` project, or adjust GitLab runner scope.

## Open Decisions

- Whether manual API-triggered pipelines should ever be allowed in addition to
  GitLab UI `web` pipelines.
- Whether publishing should be limited to protected branches/tags after the
  manual trigger gate.
- Whether intermediate major images should be parameterized in this same
  pipeline or handled as a separate follow-up hardening task.
- Whether to later create a project-specific image-build runner instead of
  sharing the `homenas-docker-image-build` group runner.
