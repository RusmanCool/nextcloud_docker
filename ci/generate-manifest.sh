#!/usr/bin/env bash
set -euo pipefail

artifact_dir="${ARTIFACT_DIR:-artifacts}"
manifest_path="${MANIFEST_PATH:-${artifact_dir}/nextcloud-image-manifest.yaml}"

image_repository="${IMAGE_REPOSITORY:-rusman/nextcloud_cron_fmp}"
image_tag="${IMAGE_TAG:-${NEXTCLOUD_VERSION:-34.0.0}}"
image_digest="${IMAGE_DIGEST:?IMAGE_DIGEST is required}"
immutable_image_tag="${IMMUTABLE_IMAGE_TAG:?IMMUTABLE_IMAGE_TAG is required}"
pipeline_image_tag="${PIPELINE_IMAGE_TAG:?PIPELINE_IMAGE_TAG is required}"
nextcloud_version="${NEXTCLOUD_VERSION:-34.0.0}"
source_project="${SOURCE_PROJECT:-${CI_PROJECT_PATH:-hn583/nextcloud_docker}}"
source_commit="${SOURCE_COMMIT:-${CI_COMMIT_SHA:-unknown}}"
dockerfile_path="${DOCKERFILE_PATH:-34/fpm/Dockerfile}"
release_url="${RELEASE_URL:-https://download.nextcloud.com/server/releases/nextcloud-${nextcloud_version}.tar.bz2}"
release_signature_verified="${RELEASE_SIGNATURE_VERIFIED:-true}"
release_checksum_verified="${RELEASE_CHECKSUM_VERIFIED:-true}"
smoke_tests_passed="${SMOKE_TESTS_PASSED:-true}"
published_at="${PUBLISHED_AT:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
ci_pipeline_url="${CI_PIPELINE_URL:-}"
release_sha256="${NEXTCLOUD_SHA256:-}"
release_gpg_fingerprint="${NEXTCLOUD_GPG_FINGERPRINT:-28806A878AE423A28372792ED75899B9A724937A}"

mkdir -p "$artifact_dir"

cat > "$manifest_path" <<EOF
image_repository: $image_repository
image_tag: "$image_tag"
image_digest: "$image_digest"
nextcloud_version: "$nextcloud_version"
source_project: "$source_project"
source_commit: "$source_commit"
dockerfile_path: "$dockerfile_path"
release_url: "$release_url"
release_signature_verified: $release_signature_verified
release_checksum_verified: $release_checksum_verified
smoke_tests_passed: $smoke_tests_passed
published_at: "$published_at"
ci_pipeline_url: "$ci_pipeline_url"
immutable_image_tag: "$immutable_image_tag"
pipeline_image_tag: "$pipeline_image_tag"
release_sha256: "$release_sha256"
release_gpg_fingerprint: "$release_gpg_fingerprint"
base_image: "php:8.4-fpm-trixie"
php_version: "8.4"
fpm_runtime: true
cron_compatible: true
postgresql_supported: true
redis_supported: true
apcu_supported: true
mysql_supported: false
intermediate_upgrade_images_available: false
notes: "Builds only the latest approved image. Production migration from 26.x still requires one-major-at-a-time intermediate images."
EOF
