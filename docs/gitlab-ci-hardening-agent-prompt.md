# Agent Prompt: Harden Nextcloud Image GitLab CI/CD

You are the next engineering agent working in the custom image repository:

```text
/home/rusman/GitRepos/nextcloud_docker
self-hosted GitLab project: hn583/nextcloud_docker
GitLab remote/push path observed locally: gitlab-houselab:hn583/nextcloud_docker.git
Docker Hub repository: rusman/nextcloud_cron_fmp
```

Your task is to harden the GitLab CI/CD flow described in:

```text
docs/gitlab-ci-hardening-plan.md
```

Do not work in the Unraid deployment repo. The Unraid repo must consume only a
published image manifest/tag/digest later.

## Objective

Make the GitLab pipeline safe for controlled operator-driven validation and
publishing of the custom Nextcloud image.

The pipeline must not start automatically on Git push. It must be started
manually from GitLab's `Run pipeline` UI, where the operator selects the branch
or tag from GitLab's built-in ref dropdown and sets trigger-time variables such
as whether Docker Hub publishing is allowed.

## Hard Requirements

- No automatic pipelines from `git push`.
- No automatic pipelines from merge request events.
- No scheduled pipelines unless explicitly approved later.
- Manual GitLab UI pipeline source `web` is the only required allowed source.
- Do not implement a script-level branch checkout.
- The selected GitLab ref from the Run Pipeline UI is the source of truth.
- Docker image publishing must be parameterized at pipeline trigger time.
- Default behavior must not publish to Docker Hub.
- Docker Hub login and push commands must exist only in a gated publish job.
- Docker Hub credentials must remain only in GitLab CI/CD masked/protected
  variables or another explicitly approved secret manager.
- Do not commit Docker Hub credentials, tokens, private keys, database
  credentials, SMTP credentials, or Nextcloud runtime secrets.
- Do not use `latest` as a publish or deployment selector.
- Do not build or publish from a moving Nextcloud branch.
- Keep image construction, smoke tests, publishing, digest verification, and
  manifest generation inside GitLab CI.
- Developer checkout activity must be limited to source review and static
  formatting/syntax checks.

## Current Important Files

Inspect these before changing anything:

```text
.gitlab-ci.yml
34/fpm/Dockerfile
34/fpm/cron.sh
34/fpm/entrypoint.sh
34/fpm/config/
ci/verify-release.sh
ci/smoke-test.sh
ci/verify-published-digest.sh
ci/generate-manifest.sh
docs/custom-image-build.md
docs/gitlab-ci-hardening-plan.md
versions.json
latest.txt
```

There may be uncommitted work. Preserve user changes and do not revert files
you did not intentionally modify.

## Current Known Concerns

The existing `.gitlab-ci.yml` is not hardened enough:

- It can run on push/default branch/tag depending on GitLab defaults and job
  rules.
- It combines build, smoke test, Docker Hub push, digest verification, and
  manifest generation in one publishing-oriented job.
- It does not yet provide a clean non-publishing validation pipeline.
- Publishing is not guarded strongly enough for a first manual run.

The current image source may still need later review against current upstream
Nextcloud Docker config fragments. That is separate from this hardening task
unless you notice a CI hardening issue directly related to those files.

## Desired Operator Flow

The operator should run CI like this:

1. Open the self-hosted GitLab project `hn583/nextcloud_docker`.
2. Go to `Build > Pipelines > Run pipeline`.
3. Select the branch or tag using GitLab's built-in ref dropdown.
4. Set trigger-time variables.
5. Start the pipeline manually.

Do not add a `BRANCH_TO_USE` variable for normal use. GitLab's selected ref is
the branch/tag selector.

## Required Pipeline Variables

Define trigger-time variables in `.gitlab-ci.yml` with safe defaults.

Required:

```yaml
PUBLISH_IMAGE:
  value: "false"
  options:
    - "false"
    - "true"
  description: "Publish Docker Hub tags and production manifest."
```

```yaml
IMAGE_TAG:
  value: "34.0.0"
  description: "Plain Docker Hub release tag. Used only when publishing."
```

```yaml
PUBLISH_IMMUTABLE_TAGS:
  value: "true"
  options:
    - "true"
    - "false"
  description: "Also publish trace tags using pipeline ID and commit SHA."
```

Add other variables only when they reduce risk or improve operator clarity.
Keep defaults safe.

## Required Workflow Rules

Add top-level `workflow: rules` so push does not create a pipeline.

Minimum required behavior:

```yaml
workflow:
  rules:
    - if: '$CI_PIPELINE_SOURCE == "web"'
      when: always
    - when: never
```

Do not allow `api`, `schedule`, or `merge_request_event` unless the operator
explicitly approves that change.

## Required Stage Model

Refactor the pipeline into separate responsibilities.

Recommended stages:

```yaml
stages:
  - static
  - verify_release
  - build_smoke
  - publish
  - manifest
```

### static

Purpose:

- Validate CI/source file syntax only.
- Do not construct Docker images.
- Do not execute publish behavior.

Examples:

- `bash -n ci/*.sh`
- YAML parsing/linting if available in the CI image.
- Dockerfile formatting/static validation if a reliable tool is available
  without adding fragile dependencies.

Keep this pragmatic. Do not add a dependency-heavy static stage that is likely
to fail because of tooling availability rather than real source problems.

### verify_release

Purpose:

- Verify the pinned Nextcloud release archive.
- Verify checksum.
- Verify PGP signature.
- Verify expected Nextcloud signing key fingerprint.
- Publish dotenv/artifacts for later jobs.

Use the existing `ci/verify-release.sh` unless you find a concrete defect.

### build_smoke

Purpose:

- Construct the Docker image in GitLab CI only.
- Run `ci/smoke-test.sh`.
- Never log in to Docker Hub.
- Never push image tags.
- Save only metadata/artifacts needed by later jobs.

This job should run for manual web pipelines regardless of
`PUBLISH_IMAGE`, because validation without publishing is the default safe
operator flow.

### publish

Purpose:

- Run only when all validation passed and `PUBLISH_IMAGE == "true"`.
- Require Docker Hub secrets.
- Push only approved tags.
- Verify that pushed tags resolve to the same digest.
- Publish digest dotenv/artifacts for manifest job.

This job must not run when `PUBLISH_IMAGE == "false"`.

Required gates:

- `CI_PIPELINE_SOURCE == "web"`
- `PUBLISH_IMAGE == "true"`
- release verification succeeded
- build/smoke succeeded
- Docker Hub credentials are present
- push succeeded
- digest verification succeeded

### manifest

Purpose:

- Generate a validation artifact for non-publishing runs.
- Generate a production deployment manifest only for publishing runs with a real
  Docker Hub digest.

For non-publishing runs, avoid producing an artifact that downstream deployment
could mistake for an approved production manifest. Use a distinct filename such
as:

```text
artifacts/nextcloud-image-validation.yaml
```

For publishing runs, produce:

```text
artifacts/nextcloud-image-manifest.yaml
```

The production manifest must include a real Docker Hub digest.

## Manifest Contract

Production manifest required fields:

```yaml
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

Additional useful fields are allowed. Do not remove the fields above.

For validation-only runs, include:

```yaml
published: false
image_digest: null
```

or use a clearly separate validation schema/filename.

## Docker Hub Tag Policy

Never publish or use `latest`.

When `PUBLISH_IMAGE=true`, publish:

- Plain release tag:

```text
rusman/nextcloud_cron_fmp:<IMAGE_TAG>
```

- Pipeline trace tag when `PUBLISH_IMMUTABLE_TAGS=true`:

```text
rusman/nextcloud_cron_fmp:<IMAGE_TAG>-houselab.<CI_PIPELINE_ID>
```

- Commit trace tag when `PUBLISH_IMMUTABLE_TAGS=true`:

```text
rusman/nextcloud_cron_fmp:<IMAGE_TAG>-houselab.<CI_COMMIT_SHORT_SHA>
```

All tags published in the same pipeline must resolve to the same digest.

## Secrets

Expected GitLab CI/CD secret variables:

```text
DOCKERHUB_USERNAME
DOCKERHUB_TOKEN
```

They must not appear in committed files except as variable names in docs or CI.
They must be configured in GitLab as masked and preferably protected.

The pipeline should fail early in `publish` if these variables are missing.
Validation-only pipelines must not require Docker Hub credentials.

## Docker Runner Assumptions

The current CI uses Docker-in-Docker:

```yaml
image: docker:27.5.1
services:
  - name: docker:27.5.1-dind
```

Before finalizing, reason about whether the self-hosted GitLab runner supports
privileged Docker-in-Docker. If the runner model is unknown, document that as a
remaining operational prerequisite. Do not silently switch to a different build
engine without documenting the tradeoff.

## Documentation Updates

Update docs as needed:

```text
docs/custom-image-build.md
docs/gitlab-ci-hardening-plan.md
```

Documentation must reinforce:

- no local image construction
- no push-triggered pipelines
- branch/tag is selected through GitLab's Run Pipeline UI
- publishing is off by default
- Docker Hub publishing requires `PUBLISH_IMAGE=true`
- non-publishing validation artifacts are not production deployment manifests

## Verification To Perform

Because local image construction is prohibited, do not run Docker builds from
the developer checkout.

Allowed local/static checks:

- Inspect files with `rg`, `sed`, `git diff`, etc.
- Run syntax checks on shell/YAML only if they do not construct or run images.
- Confirm `git diff --check` for files you changed.

Do not run:

- `docker build`
- `docker run`
- `docker push`
- CI helper scripts that download, construct, run, push, or verify artifacts as
  if they were in CI

If you need to validate actual image construction, make the GitLab pipeline safe
first, then instruct the operator to run it manually from GitLab.

## Stop Conditions

Stop and ask for operator input if:

- You cannot make push pipelines disabled without breaking manual UI pipelines.
- The desired branch/tag dropdown behavior cannot be achieved with GitLab's
  built-in Run Pipeline UI.
- The GitLab runner does not support the current image construction approach.
- Docker Hub credential handling would require committing secrets.
- Publishing cannot be gated cleanly by `PUBLISH_IMAGE=true`.
- You discover that the current pipeline would still publish when
  `PUBLISH_IMAGE=false`.
- You need to choose between Docker-in-Docker and another build engine without
  enough information about the self-hosted runner.

## Expected Deliverables

In `/home/rusman/GitRepos/nextcloud_docker`:

- Hardened `.gitlab-ci.yml`.
- Updated CI helper scripts if needed to support split validation/publish
  manifests safely.
- Updated documentation describing the manual-only pipeline and trigger
  variables.
- Clear final summary listing:
  - whether push pipelines are disabled
  - how to run the pipeline manually
  - which variables to set
  - what happens when `PUBLISH_IMAGE=false`
  - what happens when `PUBLISH_IMAGE=true`
  - any remaining operational prerequisites, especially runner privileges

Do not modify the Unraid deployment repository.
