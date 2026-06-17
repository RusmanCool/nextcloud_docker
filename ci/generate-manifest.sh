#!/usr/bin/env bash
set -euo pipefail

artifact_dir="${ARTIFACT_DIR:-artifacts}"
manifest_type="${MANIFEST_TYPE:-production}"

case "$manifest_type" in
    production|published)
        manifest_type=published
        manifest_path="${MANIFEST_PATH:-${artifact_dir}/nextcloud-image-manifest.yaml}"
        published=true
        ;;
    validation)
        manifest_path="${MANIFEST_PATH:-${artifact_dir}/nextcloud-image-validation.yaml}"
        published=false
        ;;
    *)
        echo "MANIFEST_TYPE must be published, production, or validation" >&2
        exit 1
        ;;
esac

image_repository="${IMAGE_REPOSITORY:-rusman/nextcloud_cron_fmp}"
image_tag="${IMAGE_TAG:-${NEXTCLOUD_VERSION:-34.0.0}}"
image_digest="${IMAGE_DIGEST:-}"
immutable_image_tag="${IMMUTABLE_IMAGE_TAG:-}"
pipeline_image_tag="${PIPELINE_IMAGE_TAG:-}"
deployment_environment="${DEPLOYMENT_ENV:-prod}"
nextcloud_version="${NEXTCLOUD_VERSION:-34.0.0}"
source_project="${SOURCE_PROJECT:-${CI_PROJECT_PATH:-hn583/nextcloud_docker}}"
source_commit="${SOURCE_COMMIT:-${CI_COMMIT_SHA:-unknown}}"
source_ref="${SOURCE_REF:-${CI_COMMIT_REF_NAME:-unknown}}"
dockerfile_path="${DOCKERFILE_PATH:-34/fpm/Dockerfile}"
image_base="${IMAGE_BASE:-}"
if [ -z "$image_base" ] && [ -f "$dockerfile_path" ]; then
    image_base="$(awk '$1 == "FROM" { print $2; exit }' "$dockerfile_path")"
fi
image_base="${image_base:-unknown}"
php_version="${PHP_VERSION:-}"
if [ -z "$php_version" ]; then
    case "$image_base" in
        php:*) php_version="${image_base#php:}"; php_version="${php_version%%-*}" ;;
        *) php_version="unknown" ;;
    esac
fi
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

case "$deployment_environment" in
    qa|prod) ;;
    *)
        echo "DEPLOYMENT_ENV must be qa or prod" >&2
        exit 1
        ;;
esac

if [ "$manifest_type" = "published" ]; then
    if ! [[ "$image_digest" =~ ^sha256:[0-9a-f]{64}$ ]] \
        || [ "$image_digest" = "sha256:0000000000000000000000000000000000000000000000000000000000000000" ]; then
        echo "A published manifest requires a real sha256 Docker Hub digest" >&2
        exit 1
    fi

    if [ "$release_signature_verified" != "true" ] || [ "$release_checksum_verified" != "true" ] || [ "$smoke_tests_passed" != "true" ]; then
        echo "A published manifest requires verified release artifacts and passing smoke tests" >&2
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
deployment_environment: "$deployment_environment"
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
base_image: "$image_base"
php_version: "$php_version"
fpm_runtime: true
cron_compatible: true
postgresql_supported: true
redis_supported: true
apcu_supported: true
mysql_supported: false
image_contains_runtime_data: false
runtime_data_policy: "QA manifests must deploy only with QA PostgreSQL, QA Redis, and QA volumes. PROD manifests must deploy only with production resources."
intermediate_upgrade_images_available: false
notes: "Builds only the current approved image. Production migration from 26.x still requires one-major-at-a-time intermediate images."
EOF
