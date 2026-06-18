#!/usr/bin/env bash
set -euo pipefail

image_repository="${IMAGE_REPOSITORY:?IMAGE_REPOSITORY is required}"
plain_tag="${IMAGE_TAG:?IMAGE_TAG is required}"
runtime_image_ref="${PUBLISHED_RUNTIME_IMAGE_REF:-}"
release_verifier_image_ref="${PUBLISHED_RELEASE_VERIFIER_IMAGE_REF:-}"
artifact_dir="${ARTIFACT_DIR:-artifacts}"

mkdir -p "$artifact_dir"

is_dockerhub_ref() {
    local ref_without_tag first_segment
    ref_without_tag="${1%%:*}"
    first_segment="${ref_without_tag%%/*}"

    case "$first_segment" in
        *.*|*:*|localhost) return 1 ;;
        *) return 0 ;;
    esac
}

inspect_digest() {
    local ref="$1"

    if ! is_dockerhub_ref "$ref"; then
        echo "Ref is not a Docker Hub ref, skipping docker buildx imagetools inspect: $ref" >&2
        return 1
    fi

    docker buildx imagetools inspect "$ref" | awk '$1 == "Digest:" { print $2; exit }'
}

plain_digest="$(inspect_digest "${image_repository}:${plain_tag}")"
runtime_digest=""
release_verifier_digest=""

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

if [ -n "$release_verifier_image_ref" ]; then
    release_verifier_digest="$(inspect_digest "$release_verifier_image_ref")"
    if [ -z "$release_verifier_digest" ]; then
        echo "Unable to resolve pushed release verifier image digest for $release_verifier_image_ref" >&2
        exit 1
    fi
fi

cat > "$artifact_dir/image.env" <<EOF
IMAGE_DIGEST=$plain_digest
IMAGE_TAG=$plain_tag
IMAGE_REF=${image_repository}:${plain_tag}
RUNTIME_IMAGE_REF=$runtime_image_ref
RUNTIME_IMAGE_DIGEST=$runtime_digest
RELEASE_VERIFIER_IMAGE_REF=$release_verifier_image_ref
RELEASE_VERIFIER_IMAGE_DIGEST=$release_verifier_digest
EOF
