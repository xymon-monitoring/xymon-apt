#!/bin/sh
# Rebuild Debian's xymon source package for a Debian/Ubuntu release, inside
# that release's container -- an unofficial backport.
#   Usage: build/build-deb.sh <out-dir> [releasenum [source-dir]]
#
# Source: the .dsc pinned in source.dsc.sha256 (Debian's own upload, fetched
# from the Debian archive); dpkg-source then checks every file the .dsc lists.
# Local changes, applied with patch -p1 on top of the unpacked source:
#   backport/all/*.patch        every target (e.g. a CVE fix not yet in Debian)
#   backport/<codename>/*.patch this release only (toolchain adaptations)
#
# With a source-dir (made by build/prepare-source.sh) the build is of an
# upstream tree instead -- a snapshot of main, a preview, or a release Debian
# has not packaged yet: Debian's debian/ directory, from the same pinned
# .dsc, on top of that tree.
# Debian's packaging was written for the release it packages, so what it
# needs to fit a later upstream is in prerelease/, applied before backport/:
#   prerelease/debian/          files that replace Debian's, e.g. a rebased patch
#   prerelease/*.patch          changes to the rest of debian/
# Its version is <upstream>-0~~xymon<VERSION_ID>+<packaging id>, both halves
# from prepare-source.sh, e.g.
# 4.3.32~git202611250108.dc9c799-0~~xymon13+202611251000pab12cd3. The "~"
# puts a pre-release below 4.3.32 itself, whoever builds that. A release
# built here is 4.3.32-0~~xymon13+...: above every pre-release of it, and
# below Debian's 4.3.32-1, which replaces it when it comes.
#
# Version: <debian-version>~~xymon<VERSION_ID>+<releasenum>, e.g.
# 4.3.31-1~~xymon13+1. "~~" sorts below the official backport
# (4.3.31-1~bpo13+1) and below Debian's own 4.3.31-1, so either replaces it
# cleanly; VERSION_ID (12, 13, 24.04) grows on a dist-upgrade.
set -eu
OUT=$(realpath -m "$1") REL=${2:-1} SRC=${3:-}
[ -z "$SRC" ] || SRC=$(realpath "$SRC")
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
DEBVER=$(dpkg-parsechangelog -l src/debian/changelog -S Version)

PRE= QUILT=
if [ -n "$SRC" ]; then
    read -r UPSTREAM < "$SRC/upstream-version"
    read -r PKGID < "$SRC/packaging-id"
    # Debian's debian/ alone, on the upstream tree. Upstream carries a
    # debian/ of its own, from 2019, which is not what is built.
    mv src debian-src
    cp -a "$SRC/tree" src
    rm -rf src/debian
    cp -a debian-src/debian src/debian
    # dpkg-source -x applied Debian's patches to its own tree and left this
    # marker saying so. Carried over, it would make the build skip them on
    # the upstream tree, which has none applied: a package that builds, and
    # has none of Debian's paths.
    rm -f src/debian/patches/.dpkg-source-applied
    QUILT=1
    cp -a "$HERE/prerelease/debian/." src/debian/
    PRE="$HERE/prerelease/*.patch"
fi
cd src

# shellcheck disable=SC2086
for p in $PRE "$HERE"/backport/all/*.patch "$HERE/backport/$CODENAME"/*.patch; do
    [ -e "$p" ] || continue
    echo "applying ${p#"$HERE"/}"
    patch -p1 --no-backup-if-mismatch < "$p"
done

if [ -n "$SRC" ]; then
    # Upstream tests known to fail for a reason upstream has to fix
    # (prerelease/skip-tests). Its runner runs executables only.
    grep -v '^[[:space:]]*#' "$HERE/prerelease/skip-tests" | while read -r t why; do
        [ -n "$t" ] || continue
        if [ -e "$t" ]; then
            chmod -x "$t"
            echo "not running upstream test $t (until $why)"
        else
            echo "prerelease/skip-tests: $t is not in this tree; remove the line"
        fi
    done
    VER="$UPSTREAM-0~~xymon${VERSION_ID:?}+$PKGID"
    MSG="Build of upstream $UPSTREAM with the packaging of Debian's $DEBVER, for $CODENAME, by xymon-apt."
else
    VER="$DEBVER~~xymon${VERSION_ID:?}+$REL"
    MSG="Rebuild of Debian's $DEBVER for $CODENAME by xymon-apt."
fi
DEBEMAIL=noreply@github.com DEBFULLNAME="xymon-apt CI" \
    dch -b -v "$VER" -D "$CODENAME" "$MSG"

# Build-deps from the release's official backports, where the patches above
# do not lower them (backport/<codename>/{sources.list,preferences}).
if [ -e "$HERE/backport/$CODENAME/sources.list" ]; then
    cp "$HERE/backport/$CODENAME/sources.list" /etc/apt/sources.list.d/xymon-apt-build.list
    [ ! -e "$HERE/backport/$CODENAME/preferences" ] ||
        cp "$HERE/backport/$CODENAME/preferences" /etc/apt/preferences.d/xymon-apt-build
    apt-get update
fi
mk-build-deps -i -r -t 'apt-get -y --no-install-recommends' debian/control
if [ -n "$QUILT" ]; then
    # Apply Debian's patches here, and fail if one does not apply. Left to
    # dpkg-buildpackage they can be skipped in silence: when the first patch
    # of the series does not apply, dpkg-source concludes the series is
    # applied already and builds the tree as it is.
    apt-get install -y --no-install-recommends quilt
    QUILT_PATCHES=debian/patches quilt push -a --fuzz=0
fi
dpkg-buildpackage -b -us -uc
mkdir -p "$OUT"
mv ../*.deb "$OUT"/
