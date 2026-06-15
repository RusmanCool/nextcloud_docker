#!/usr/bin/env bash
set -euo pipefail

nextcloud_version="${NEXTCLOUD_VERSION:-34.0.0}"
release_url="${RELEASE_URL:-https://download.nextcloud.com/server/releases/nextcloud-${nextcloud_version}.tar.bz2}"
release_asc_url="${RELEASE_ASC_URL:-${release_url}.asc}"
release_sha256_url="${RELEASE_SHA256_URL:-${release_url}.sha256}"
release_key_url="${NEXTCLOUD_GPG_KEY_URL:-https://nextcloud.com/nextcloud.asc}"
release_fingerprint="${NEXTCLOUD_GPG_FINGERPRINT:-28806A878AE423A28372792ED75899B9A724937A}"
artifact_dir="${ARTIFACT_DIR:-artifacts/release}"

mkdir -p "$artifact_dir"

tarball="$artifact_dir/nextcloud-${nextcloud_version}.tar.bz2"
signature="$tarball.asc"
checksum_file="$tarball.sha256"
key_file="$artifact_dir/nextcloud.asc"

curl -fsSL -o "$tarball" "$release_url"
curl -fsSL -o "$signature" "$release_asc_url"
curl -fsSL -o "$checksum_file" "$release_sha256_url"
curl -fsSL -o "$key_file" "$release_key_url"

nextcloud_sha256="$(awk '{ print $1; exit }' "$checksum_file")"
if [ -z "$nextcloud_sha256" ]; then
    echo "Unable to parse SHA256 from $release_sha256_url" >&2
    exit 1
fi

printf '%s  %s\n' "$nextcloud_sha256" "$tarball" | sha256sum -c -

export GNUPGHOME
GNUPGHOME="$(mktemp -d)"
trap 'gpgconf --kill all >/dev/null 2>&1 || true; rm -rf "$GNUPGHOME"' EXIT

gpg --batch --import "$key_file"
gpg --batch --list-keys --with-colons "$release_fingerprint" \
    | awk -F: -v fpr="$release_fingerprint" '$1 == "fpr" && $10 == fpr { found=1 } END { exit !found }'
gpg --batch --verify "$signature" "$tarball"

cat > "$artifact_dir/release.env" <<EOF
NEXTCLOUD_SHA256=$nextcloud_sha256
RELEASE_CHECKSUM_VERIFIED=true
RELEASE_SIGNATURE_VERIFIED=true
RELEASE_URL=$release_url
RELEASE_ASC_URL=$release_asc_url
RELEASE_SHA256_URL=$release_sha256_url
NEXTCLOUD_GPG_FINGERPRINT=$release_fingerprint
EOF

cat > "$artifact_dir/release-verification.yaml" <<EOF
nextcloud_version: "$nextcloud_version"
release_url: "$release_url"
release_signature_url: "$release_asc_url"
release_checksum_url: "$release_sha256_url"
release_sha256: "$nextcloud_sha256"
release_gpg_fingerprint: "$release_fingerprint"
release_signature_verified: true
release_checksum_verified: true
EOF
