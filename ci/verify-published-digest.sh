#!/usr/bin/env bash
set -euo pipefail

image_repository="${IMAGE_REPOSITORY:?IMAGE_REPOSITORY is required}"
plain_tag="${IMAGE_TAG:?IMAGE_TAG is required}"
immutable_tag="${IMMUTABLE_IMAGE_TAG:?IMMUTABLE_IMAGE_TAG is required}"
pipeline_tag="${PIPELINE_IMAGE_TAG:?PIPELINE_IMAGE_TAG is required}"
artifact_dir="${ARTIFACT_DIR:-artifacts}"

mkdir -p "$artifact_dir"

inspect_digest() {
    local ref="$1"
    docker buildx imagetools inspect "$ref" | awk '$1 == "Digest:" { print $2; exit }'
}

plain_digest="$(inspect_digest "${image_repository}:${plain_tag}")"
immutable_digest="$(inspect_digest "${image_repository}:${immutable_tag}")"
pipeline_digest="$(inspect_digest "${image_repository}:${pipeline_tag}")"

if [ -z "$plain_digest" ] || [ -z "$immutable_digest" ] || [ -z "$pipeline_digest" ]; then
    echo "Unable to resolve one or more pushed image digests" >&2
    exit 1
fi

if [ "$plain_digest" != "$immutable_digest" ] || [ "$plain_digest" != "$pipeline_digest" ]; then
    echo "Pushed tag digest mismatch" >&2
    echo "${plain_tag}: ${plain_digest}" >&2
    echo "${immutable_tag}: ${immutable_digest}" >&2
    echo "${pipeline_tag}: ${pipeline_digest}" >&2
    exit 1
fi

cat > "$artifact_dir/image.env" <<EOF
IMAGE_DIGEST=$plain_digest
IMMUTABLE_IMAGE_DIGEST=$immutable_digest
PIPELINE_IMAGE_DIGEST=$pipeline_digest
EOF
