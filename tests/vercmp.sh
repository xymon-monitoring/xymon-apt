#!/bin/sh
#
# The version ordering is the one thing in this repo that silently does the
# wrong thing when it breaks: a bad version string either keeps a host on
# this rebuild after Debian ships the same version officially, or leaves a
# rebuilt package below the one it should replace. Neither shows up as a
# failed build, so assert it explicitly.
#
#   Usage: tests/vercmp.sh [deb-dir]
#
# With a deb-dir, the version actually built is checked as well.

set -eu

command -v dpkg >/dev/null || { echo "NOT OK   dpkg not found"; exit 1; }

fail=0

# want: $1 sorts strictly below $2
below() {
	if dpkg --compare-versions "$1" lt "$2"; then
		echo "ok       $1  <  $2"
	else
		echo "NOT OK   $1  is not below  $2"
		fail=1
	fi
}

# The distro's own, older package upgrades to the rebuild.
below "4.3.30-1+b2" "4.3.31-1~~xymon12+1"
below "4.3.30-4" "4.3.31-1~~xymon13+1"
below "4.3.30-99ubuntu9" "4.3.31-1~~xymon24.04+1"

# A rebuild of the same Debian version (releasenum, e.g. a security fix)
# supersedes the earlier one -- numerically, so +10 follows +9.
below "4.3.31-1~~xymon13+1" "4.3.31-1~~xymon13+2"
below "4.3.31-1~~xymon13+9" "4.3.31-1~~xymon13+10"

# A release upgrade moves forward: VERSION_ID grows.
below "4.3.31-1~~xymon12+9" "4.3.31-1~~xymon13+1"
below "4.3.31-1~~xymon24.04+9" "4.3.31-1~~xymon26.04+1"

# The official packages of the same Debian version win, so apt moves to
# them with no downgrade: the backport, the upload itself, a stable update,
# an Ubuntu rebuild.
below "4.3.31-1~~xymon12+9" "4.3.31-1~bpo12+1"
below "4.3.31-1~~xymon13+9" "4.3.31-1~bpo13+1"
below "4.3.31-1~~xymon13+9" "4.3.31-1"
below "4.3.31-1~~xymon13+9" "4.3.31-1+deb13u1"
below "4.3.31-1~~xymon24.04+9" "4.3.31-1build1"

# The next Debian revision's rebuild supersedes every rebuild of this one,
# which is what lets releasenum go back to 1 on a new Debian upload.
below "4.3.31-1~~xymon13+9" "4.3.31-2~~xymon13+1"
below "4.3.31-2~~xymon13+9" "4.3.32-1~~xymon13+1"

# Pre-release channels are not built yet, but the versions above must leave
# room for them: a snapshot or a preview of the next upstream version is
# X.Y.Z~<something>, which has to sort above everything of the current
# version, official packages included, and below the rebuild of X.Y.Z itself.
# The exact strings are illustrations; the "~" after the upstream version is
# the commitment.
below "4.3.31-1~~xymon13+9" "4.3.32~git202611091355.2dcad5d-1~~xymon13+1"
below "4.3.31-1+deb13u1" "4.3.32~git202611091355.2dcad5d-1~~xymon13+1"
below "4.3.32~git202611091355.2dcad5d-1~~xymon13+1" "4.3.32~git202611102200.fd64efe-1~~xymon13+1"
below "4.3.32~git209912312359.fffffff-1~~xymon13+9" "4.3.32-1~~xymon13+1"
below "4.3.31-1~~xymon13+9" "4.3.32~preview1-1~~xymon13+1"
below "4.3.32~preview9-1~~xymon13+1" "4.3.32~preview10-1~~xymon13+1"
below "4.3.32~preview10-1~~xymon13+9" "4.3.32-1~~xymon13+1"

if [ -n "${1:-}" ]; then
	. /etc/os-release
	set -- "$1"/xymon_*.deb
	[ -e "$1" ] || { echo "NOT OK   no xymon_*.deb to read the built version from"; exit 1; }
	built=$(dpkg-deb -f "$1" Version)
	deb=${built%%~~xymon*}
	case "$built" in
	"$deb~~xymon${VERSION_ID:?}+"[0-9]*) echo "ok       built version $built" ;;
	*) echo "NOT OK   built version $built is not $deb~~xymon$VERSION_ID+<n>"; fail=1 ;;
	esac
	below "$built" "$deb~bpo${VERSION_ID%%.*}+1"
	below "$built" "$deb"
fi

exit "$fail"
