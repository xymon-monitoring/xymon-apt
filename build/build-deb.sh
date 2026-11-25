#!/bin/sh
# Rebuild Debian's xymon source package for a Debian/Ubuntu release, inside
# that release's container -- an unofficial backport.
#   Usage: build/build-deb.sh <out-dir> [releasenum]
#
# Source: the .dsc pinned in source.dsc.sha256 (Debian's own upload, fetched
# from the Debian archive); dpkg-source then checks every file the .dsc lists.
# Local changes, applied with patch -p1 on top of the unpacked source:
#   backport/all/*.patch        every target (e.g. a CVE fix not yet in Debian)
#   backport/<codename>/*.patch this release only (toolchain adaptations)
#
# Version: <debian-version>~~xymon<VERSION_ID>+<releasenum>, e.g.
# 4.3.31-1~~xymon13+1. "~~" sorts below the official backport
# (4.3.31-1~bpo13+1) and below Debian's own 4.3.31-1, so either replaces it
# cleanly; VERSION_ID (12, 13, 24.04) grows on a dist-upgrade.
set -eu
OUT=$(realpath -m "$1") REL=${2:-1}
HERE=$(dirname "$(dirname "$(realpath "$0")")")
. /etc/os-release
CODENAME=${VERSION_CODENAME:?}

read -r DSC_SHA DSC < "$HERE/source.dsc.sha256"
POOL="pool/main/x/xymon"
MIRRORS="https://deb.debian.org/debian/$POOL https://incoming.debian.org/debian-buildd/$POOL"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends build-essential ca-certificates curl devscripts equivs

WORK=$(mktemp -d)
cd "$WORK"
# The .dsc names the other files; fetch each from the first mirror that has it.
fetch() {
    for m in $MIRRORS; do curl -fsSO "$m/$1" && return 0; done
    echo "cannot fetch $1 from: $MIRRORS" >&2; return 1
}
fetch "$DSC"
echo "$DSC_SHA  $DSC" | sha256sum -c -
for f in $(awk '/^Checksums-Sha256:/{s=1; next} /^[^ ]/{s=0} s{print $3}' "$DSC"); do fetch "$f"; done
dpkg-source -x "$DSC" src
cd src

for p in "$HERE"/backport/all/*.patch "$HERE/backport/$CODENAME"/*.patch; do
    [ -e "$p" ] || continue
    echo "applying ${p#"$HERE"/}"
    patch -p1 --no-backup-if-mismatch < "$p"
done

DEBVER=$(dpkg-parsechangelog -S Version)
VER="$DEBVER~~xymon${VERSION_ID:?}+$REL"
DEBEMAIL=noreply@github.com DEBFULLNAME="xymon-apt CI" \
    dch -b -v "$VER" -D "$CODENAME" "Rebuild of Debian's $DEBVER for $CODENAME by xymon-apt."

# Build-deps from the release's official backports, where the patches above
# do not lower them (backport/<codename>/{sources.list,preferences}).
if [ -e "$HERE/backport/$CODENAME/sources.list" ]; then
    cp "$HERE/backport/$CODENAME/sources.list" /etc/apt/sources.list.d/xymon-apt-build.list
    [ ! -e "$HERE/backport/$CODENAME/preferences" ] ||
        cp "$HERE/backport/$CODENAME/preferences" /etc/apt/preferences.d/xymon-apt-build
    apt-get update
fi
mk-build-deps -i -r -t 'apt-get -y --no-install-recommends' debian/control
dpkg-buildpackage -b -us -uc
mkdir -p "$OUT"
mv ../*.deb "$OUT"/
