#!/bin/sh
# Turn per-distro .deb dirs into a signed APT repo.
# Usage: make-repo.sh <debs-dir> <repo-dir> [gpg-key-id]
#   <debs-dir>/<codename>/*.deb  ->  <repo-dir>/{pool,dists}/<codename>/...
# One suite per codename, component "main". Unsigned if no key id given.
set -eu
DEBS=$1 REPO=$2 KEY=${3:-}
rm -rf "$REPO"
for dir in "$DEBS"/*/; do
    c=$(basename "$dir")
    mkdir -p "$REPO/pool/$c"
    cp "$dir"/*.deb "$REPO/pool/$c/"
    for arch in $(ls "$REPO/pool/$c" | sed -n 's/.*_\([a-z0-9]*\)\.deb$/\1/p' | sort -u); do
        b="dists/$c/main/binary-$arch"
        mkdir -p "$REPO/$b"
        (cd "$REPO" && apt-ftparchive -a "$arch" packages "pool/$c" > "$b/Packages")
        gzip -9kf "$REPO/$b/Packages"
    done
    archs=$(ls "$REPO/dists/$c/main" | sed 's/binary-//' | xargs)
    (cd "$REPO/dists/$c" && apt-ftparchive \
        -o APT::FTPArchive::Release::Origin=xymon-apt \
        -o APT::FTPArchive::Release::Label=Xymon \
        -o APT::FTPArchive::Release::Suite="$c" \
        -o APT::FTPArchive::Release::Codename="$c" \
        -o APT::FTPArchive::Release::Components=main \
        -o APT::FTPArchive::Release::Architectures="$archs" \
        release . > ../Release.tmp && mv ../Release.tmp Release)
    if [ -n "$KEY" ]; then
        gpg --batch --yes -u "$KEY" --clearsign -o "$REPO/dists/$c/InRelease" "$REPO/dists/$c/Release"
        gpg --batch --yes -u "$KEY" -abs -o "$REPO/dists/$c/Release.gpg" "$REPO/dists/$c/Release"
    fi
done
[ -z "$KEY" ] || gpg --export "$KEY" > "$REPO/xymon-archive-keyring.gpg"
