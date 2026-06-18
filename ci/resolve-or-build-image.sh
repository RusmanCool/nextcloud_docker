#!/usr/bin/env bash
set -euo pipefail

image_ref="${IMAGE_REF:?IMAGE_REF is required}"
image_kind="${IMAGE_KIND:-image}"
env_prefix="${ENV_PREFIX:?ENV_PREFIX is required}"
force_rebuild="${FORCE_REBUILD:-false}"
publish_image="${PUBLISH_IMAGE:-false}"
docker_context="${DOCKER_CONTEXT:-}"
dockerfile_path="${DOCKERFILE_PATH:-}"
archive_path="${ARCHIVE_PATH:?ARCHIVE_PATH is required}"
env_path="${ENV_PATH:?ENV_PATH is required}"

mkdir -p "$(dirname "$archive_path")" "$(dirname "$env_path")"

is_dockerhub_ref() {
    local ref_without_tag first_segment
    ref_without_tag="${1%%:*}"
    first_segment="${ref_without_tag%%/*}"

    case "$first_segment" in
        *.*|*:*|localhost) return 1 ;;
        *) return 0 ;;
    esac
}

inspect_remote_digest() {
    docker buildx imagetools inspect "$1" | awk '$1 == "Digest:" { print $2; exit }'
}

local_image_id() {
    docker image inspect --format '{{.Id}}' "$1" 2>/dev/null || true
}

remote_digest=""
image_source=""

if [ "$force_rebuild" != "true" ]; then
    if is_dockerhub_ref "$image_ref"; then
        echo "Checking Docker Hub for existing $image_kind image: $image_ref"
        if remote_digest="$(inspect_remote_digest "$image_ref" 2>/dev/null)" && [ -n "$remote_digest" ]; then
            echo "Found Docker Hub $image_kind image digest: $remote_digest"
            if docker pull "$image_ref"; then
                image_source="remote"
            else
                echo "Docker Hub digest resolved, but pull failed for $image_ref; checking local Docker daemon."
                remote_digest=""
            fi
        else
            echo "Docker Hub image was not resolvable for $image_ref; checking local Docker daemon."
        fi
    else
        echo "$image_ref is not a Docker Hub reference; skipping remote digest check."
    fi

    if [ -z "$image_source" ] && [ -n "$(local_image_id "$image_ref")" ]; then
        echo "Found local $image_kind image: $image_ref"
        image_source="local"
    fi
fi

if [ -z "$image_source" ]; then
    if [ "$force_rebuild" != "true" ]; then
        echo "No usable $image_kind image found for $image_ref." >&2
        echo "Set the matching FORCE_REBUILD_* variable to true to build a new one." >&2
        exit 1
    fi

    test -n "$docker_context" || { echo "DOCKER_CONTEXT is required to build $image_kind." >&2; exit 1; }
    test -f "$dockerfile_path" || { echo "Dockerfile not found for $image_kind: $dockerfile_path" >&2; exit 1; }

    echo "Building $image_kind image: $image_ref"
    docker build --pull \
        --label "org.opencontainers.image.source=${CI_PROJECT_URL:-}" \
        --label "org.opencontainers.image.revision=${CI_COMMIT_SHA:-}" \
        -t "$image_ref" \
        -f "$dockerfile_path" \
        "$docker_context"
    image_source="built"

    if [ "$publish_image" = "true" ]; then
        echo "Pushing $image_kind image: $image_ref"
        docker push "$image_ref"
        if is_dockerhub_ref "$image_ref"; then
            remote_digest="$(inspect_remote_digest "$image_ref")"
        fi
    fi
fi

local_id="$(local_image_id "$image_ref")"
if [ -n "$local_id" ]; then
    echo "Saving $image_kind image archive: $archive_path"
    docker save "$image_ref" | gzip -c > "$archive_path"
else
    echo "No local $image_kind image is available after resolution: $image_ref" >&2
    exit 1
fi

cat > "$env_path" <<EOF
${env_prefix}_IMAGE_REF=$image_ref
${env_prefix}_IMAGE_DIGEST=$remote_digest
${env_prefix}_IMAGE_LOCAL_ID=$local_id
${env_prefix}_IMAGE_ARCHIVE=$archive_path
${env_prefix}_IMAGE_SOURCE=$image_source
EOF
