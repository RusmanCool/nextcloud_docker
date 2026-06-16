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
- `IMAGE_TAG`
  - Default: the selected Nextcloud version, for example `34.0.0`
  - Meaning: plain release tag to publish only when `PUBLISH_IMAGE=true`.
- `PUBLISH_IMMUTABLE_TAGS`
  - Default: `true`
  - Options: `true`, `false`
  - Meaning: controls creation of traceable tags such as
    `34.0.0-houselab.<pipeline-id>` and `34.0.0-houselab.<git-sha>`.

Branch selection should use GitLab's built-in branch/tag dropdown on the Run
Pipeline page. A separate `BRANCH_TO_USE` variable should be avoided unless
there is a later API-driven use case that truly requires it.

## Stage Layout

Stages:

- `static`
- `verify_release`
- `build_smoke`
- `publish`
- `manifest`

`static`:

- Check YAML syntax where practical.
- Check shell script syntax.
- Check Dockerfile formatting with an approved static checker if available.
- Do not construct an image in this stage.

`verify_release`:

- Download the pinned Nextcloud release archive, checksum file, signature, and
  public signing key.
- Verify checksum.
- Verify PGP signature and expected fingerprint.
- Publish only verification artifacts and dotenv values needed by later jobs.

`build_smoke`:

- Construct the image inside GitLab CI only.
- Run image smoke tests inside GitLab CI only.
- Save build metadata needed by later jobs.
- Save a compressed image archive only when `PUBLISH_IMAGE=true`, so the publish
  job can push the same image that passed smoke tests.
- Never push Docker tags from this job.

`publish`:

- Run only when `PUBLISH_IMAGE == "true"`.
- Require Docker Hub secret variables to exist.
- Push the plain release tag and any enabled immutable tags.
- Verify that all pushed tags resolve to the same digest.
- Fail if digest verification fails.

`manifest`:

- For non-publishing runs, publish a validation manifest or build report that
  clearly states no Docker Hub digest was produced.
- For publishing runs, publish the deployment manifest containing the real
  Docker Hub digest, selected ref, source commit, CI pipeline URL, release
  verification results, and smoke-test result.

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

If any gate fails, no deployment manifest with a production digest should be
published.

## Docker Hub Tag Policy

Do not publish or consume `latest`.

Required publish tags when `PUBLISH_IMAGE=true`:

- Plain release tag, for example `rusman/nextcloud_cron_fmp:34.0.0`.
- Pipeline trace tag, for example
  `rusman/nextcloud_cron_fmp:34.0.0-houselab.<pipeline-id>`, when
  `PUBLISH_IMMUTABLE_TAGS=true`.
- Commit trace tag, for example
  `rusman/nextcloud_cron_fmp:34.0.0-houselab.<git-sha>`, when
  `PUBLISH_IMMUTABLE_TAGS=true`.

All pushed tags for a single pipeline must resolve to the same digest.

## Manifest Requirements

The production manifest is valid only after a publishing run. It must include:

- `image_repository`
- `image_tag`
- `image_digest`
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
- immutable tags produced by the run

For non-publishing runs, use a separate validation artifact name or include an
explicit field such as:

```yaml
published: false
image_digest: null
```

The downstream Unraid deployment pipeline must consume only a production
manifest from a publishing run.

## Hardening Task Status

1. Done: added `workflow: rules` that allow only manual web pipelines.
2. Done: split validation into `build_smoke` and publishing into gated
   `publish_image`.
3. Done: added trigger-time variables with safe defaults and dropdown options.
4. Done: Docker Hub login and push commands exist only in `publish_image`.
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
