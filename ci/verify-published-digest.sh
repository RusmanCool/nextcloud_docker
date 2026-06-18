#!/usr/bin/env bash
set -euo pipefail

image_repository="${IMAGE_REPOSITORY:?IMAGE_REPOSITORY is required}"
plain_tag="${IMAGE_TAG:?IMAGE_TAG is required}"
runtime_image_ref="${PUBLISHED_RUNTIME_IMAGE_REF:-}"
artifact_dir="${ARTIFACT_DIR:-artifacts}"

mkdir -p "$artifact_dir"

inspect_digest() {
    local ref="$1"
    docker buildx imagetools inspect "$ref" | awk '$1 == "Digest:" { print $2; exit }'
}

plain_digest="$(inspect_digest "${image_repository}:${plain_tag}")"
runtime_digest=""

if [ -z "$plain_digest" ]; then
    echo "Unable to resolve pushed image digest for ${image_repository}:${plain_tag}" >&2
    exit 1
fi

if [ -n "$runtime_image_ref" ]; then
    runtime_digest="$(inspect_digest "$runtime_image_ref")"
    if [ -z "$runtime_digest" ]; then
        echo "Unable to resolve pushed runtime image digest for $runtime_image_ref" >&2
        exit 1
    fi
fi

cat > "$artifact_dir/image.env" <<EOF
IMAGE_DIGEST=$plain_digest
IMAGE_TAG=$plain_tag
IMAGE_REF=${image_repository}:${plain_tag}
RUNTIME_IMAGE_REF=$runtime_image_ref
RUNTIME_IMAGE_DIGEST=$runtime_digest
EOF
