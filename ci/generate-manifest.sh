#!/usr/bin/env bash
set -euo pipefail

artifact_dir="${ARTIFACT_DIR:-artifacts}"
manifest_type="${MANIFEST_TYPE:-production}"

case "$manifest_type" in
    production)
        manifest_path="${MANIFEST_PATH:-${artifact_dir}/nextcloud-image-manifest.yaml}"
        published=true
        ;;
    validation)
        manifest_path="${MANIFEST_PATH:-${artifact_dir}/nextcloud-image-validation.yaml}"
        published=false
        ;;
    *)
        echo "MANIFEST_TYPE must be production or validation" >&2
        exit 1
        ;;
esac

image_repository="${IMAGE_REPOSITORY:-rusman/nextcloud_cron_fmp}"
image_tag="${IMAGE_TAG:-${NEXTCLOUD_VERSION:-34.0.0}}"
image_digest="${IMAGE_DIGEST:-}"
immutable_image_tag="${IMMUTABLE_IMAGE_TAG:-}"
pipeline_image_tag="${PIPELINE_IMAGE_TAG:-}"
nextcloud_version="${NEXTCLOUD_VERSION:-34.0.0}"
source_project="${SOURCE_PROJECT:-${CI_PROJECT_PATH:-hn583/nextcloud_docker}}"
source_commit="${SOURCE_COMMIT:-${CI_COMMIT_SHA:-unknown}}"
source_ref="${SOURCE_REF:-${CI_COMMIT_REF_NAME:-unknown}}"
dockerfile_path="${DOCKERFILE_PATH:-34/fpm/Dockerfile}"
release_url="${RELEASE_URL:-https://download.nextcloud.com/server/releases/nextcloud-${nextcloud_version}.tar.bz2}"
release_signature_verified="${RELEASE_SIGNATURE_VERIFIED:-false}"
release_checksum_verified="${RELEASE_CHECKSUM_VERIFIED:-false}"
smoke_tests_passed="${SMOKE_TESTS_PASSED:-false}"
published_at="${PUBLISHED_AT:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
ci_pipeline_url="${CI_PIPELINE_URL:-}"
release_sha256="${NEXTCLOUD_SHA256:-}"
release_gpg_fingerprint="${NEXTCLOUD_GPG_FINGERPRINT:-28806A878AE423A28372792ED75899B9A724937A}"
publish_immutable_tags="${PUBLISH_IMMUTABLE_TAGS:-true}"

mkdir -p "$artifact_dir"

if [ "$manifest_type" = "production" ]; then
    case "$image_digest" in
        sha256:*) ;;
        *)
            echo "A production manifest requires a real sha256 Docker Hub digest" >&2
            exit 1
            ;;
    esac

    if [ "$release_signature_verified" != "true" ] || [ "$release_checksum_verified" != "true" ] || [ "$smoke_tests_passed" != "true" ]; then
        echo "A production manifest requires verified release artifacts and passing smoke tests" >&2
        exit 1
    fi
fi

if [ "$manifest_type" = "validation" ]; then
    image_digest_value="null"
    published_at_value="null"
    immutable_tags_published=false
else
    image_digest_value="\"$image_digest\""
    published_at_value="\"$published_at\""
    immutable_tags_published="$publish_immutable_tags"
fi

cat > "$manifest_path" <<EOF
published: $published
image_repository: $image_repository
image_tag: "$image_tag"
image_digest: $image_digest_value
nextcloud_version: "$nextcloud_version"
source_project: "$source_project"
source_commit: "$source_commit"
source_ref: "$source_ref"
dockerfile_path: "$dockerfile_path"
release_url: "$release_url"
release_signature_verified: $release_signature_verified
release_checksum_verified: $release_checksum_verified
smoke_tests_passed: $smoke_tests_passed
published_at: $published_at_value
ci_pipeline_url: "$ci_pipeline_url"
immutable_tags_published: $immutable_tags_published
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
notes: "Builds only the current approved image. Production migration from 26.x still requires one-major-at-a-time intermediate images."
EOF
