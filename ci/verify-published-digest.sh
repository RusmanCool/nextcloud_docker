#!/usr/bin/env bash
set -euo pipefail

image_repository="${IMAGE_REPOSITORY:?IMAGE_REPOSITORY is required}"
plain_tag="${IMAGE_TAG:?IMAGE_TAG is required}"
publish_immutable_tags="${PUBLISH_IMMUTABLE_TAGS:-true}"
deployment_environment="${DEPLOYMENT_ENV:-prod}"
artifact_dir="${ARTIFACT_DIR:-artifacts}"

mkdir -p "$artifact_dir"

case "$deployment_environment" in
    qa|prod) ;;
    *)
        echo "DEPLOYMENT_ENV must be qa or prod" >&2
        exit 1
        ;;
esac

case "$publish_immutable_tags" in
    true|false) ;;
    *)
        echo "PUBLISH_IMMUTABLE_TAGS must be true or false" >&2
        exit 1
        ;;
esac

inspect_digest() {
    local ref="$1"
    docker buildx imagetools inspect "$ref" | awk '$1 == "Digest:" { print $2; exit }'
}

plain_digest="$(inspect_digest "${image_repository}:${plain_tag}")"
immutable_digest=""
pipeline_digest=""

if [ -z "$plain_digest" ]; then
    echo "Unable to resolve pushed image digest for ${image_repository}:${plain_tag}" >&2
    exit 1
fi

if [ "$publish_immutable_tags" = "true" ]; then
    immutable_tag="${IMMUTABLE_IMAGE_TAG:?IMMUTABLE_IMAGE_TAG is required when PUBLISH_IMMUTABLE_TAGS=true}"
    pipeline_tag="${PIPELINE_IMAGE_TAG:?PIPELINE_IMAGE_TAG is required when PUBLISH_IMMUTABLE_TAGS=true}"

    immutable_digest="$(inspect_digest "${image_repository}:${immutable_tag}")"
    pipeline_digest="$(inspect_digest "${image_repository}:${pipeline_tag}")"

    if [ -z "$immutable_digest" ] || [ -z "$pipeline_digest" ]; then
        echo "Unable to resolve one or more pushed immutable image digests" >&2
        exit 1
    fi

    if [ "$plain_digest" != "$immutable_digest" ] || [ "$plain_digest" != "$pipeline_digest" ]; then
        echo "Pushed tag digest mismatch" >&2
        echo "${plain_tag}: ${plain_digest}" >&2
        echo "${immutable_tag}: ${immutable_digest}" >&2
        echo "${pipeline_tag}: ${pipeline_digest}" >&2
        exit 1
    fi
else
    immutable_tag=""
    pipeline_tag=""
fi

cat > "$artifact_dir/image.env" <<EOF
IMAGE_DIGEST=$plain_digest
IMAGE_TAG=$plain_tag
IMAGE_REF=${image_repository}:${plain_tag}
DEPLOYMENT_ENV=$deployment_environment
IMMUTABLE_IMAGE_TAG=$immutable_tag
PIPELINE_IMAGE_TAG=$pipeline_tag
IMMUTABLE_IMAGE_DIGEST=$immutable_digest
PIPELINE_IMAGE_DIGEST=$pipeline_digest
PUBLISH_IMMUTABLE_TAGS=$publish_immutable_tags
EOF
