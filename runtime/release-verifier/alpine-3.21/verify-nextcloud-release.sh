#!/usr/bin/env bash
set -euo pipefail

release_dir="${1:-/tmp/nextcloud-release}"
extract_dir="${2:-/usr/src}"
expected_sha256="${NEXTCLOUD_SHA256:-}"
expected_fingerprint="${NEXTCLOUD_GPG_FINGERPRINT:-28806A878AE423A28372792ED75899B9A724937A}"

tarball="$release_dir/nextcloud.tar.bz2"
signature="$release_dir/nextcloud.tar.bz2.asc"
checksum_file="$release_dir/nextcloud.tar.bz2.sha256"
key_file="$release_dir/nextcloud.asc"

for file in "$tarball" "$signature" "$checksum_file" "$key_file"; do
    if [ ! -s "$file" ]; then
        echo "Missing release verification input: $file" >&2
        exit 1
    fi
done

if [ -n "$expected_sha256" ]; then
    printf '%s  %s\n' "$expected_sha256" "$tarball" | sha256sum -c -
else
    checksum="$(awk '{ print $1; exit }' "$checksum_file")"
    if [ -z "$checksum" ]; then
        echo "Unable to parse SHA256 from $checksum_file" >&2
        exit 1
    fi
    printf '%s  %s\n' "$checksum" "$tarball" | sha256sum -c -
fi

export GNUPGHOME
GNUPGHOME="$(mktemp -d)"
trap 'gpgconf --kill all >/dev/null 2>&1 || true; rm -rf "$GNUPGHOME"' EXIT

gpg --batch --import "$key_file"
gpg --batch --list-keys --with-colons "$expected_fingerprint" \
    | awk -F: -v fpr="$expected_fingerprint" '$1 == "fpr" && $10 == fpr { found=1 } END { exit !found }'
gpg --batch --verify "$signature" "$tarball"

mkdir -p "$extract_dir"
tar -xjf "$tarball" -C "$extract_dir"

rm -rf "$extract_dir/nextcloud/updater"
mkdir -p "$extract_dir/nextcloud/data"
mkdir -p "$extract_dir/nextcloud/custom_apps"
chmod +x "$extract_dir/nextcloud/occ"
