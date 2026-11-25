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

# Pre-releases: <upstream>-0~~xymon<VERSION_ID>+<packaging id>, where the
# upstream half is X.Y.Z~git<datetime>.<sha> for a snapshot of main and
# X.Y.Z~preview<N> for a preview, and the packaging id <datetime>p<sha>
# (build/prepare-source.sh). The "~" after X.Y.Z is what places them: above
# everything of the current version, official packages included, and below
# X.Y.Z itself, whoever builds it.
snap="4.3.32~git202611250108.dc9c799-0~~xymon13+202611251000pab12cd3"
below "4.3.31-1~~xymon13+9" "$snap"
below "4.3.31-1+deb13u1" "$snap"
below "$snap" "4.3.32-1~~xymon13+1"
below "$snap" "4.3.32-1"
below "$snap" "4.3.32-1~bpo13+1"

# Snapshots advance by the upstream commit's time, whatever the shas: dpkg
# compares the digits as a number before it reaches the sha.
below "4.3.32~git202611250108.fffffff-0~~xymon13+202611251000pab12cd3" \
      "4.3.32~git202611252200.0000000-0~~xymon13+202611251000pab12cd3"

# A packaging-only change republishes the same upstream commit: the
# packaging datetime advances it.
below "$snap" "4.3.32~git202611250108.dc9c799-0~~xymon13+202611261000p0000000"

# A newer upstream commit outranks any packaging rebuild of an older one.
below "4.3.32~git202611250108.dc9c799-0~~xymon13+209912312359pfffffff" \
      "4.3.32~git202611260108.aaaaaaa-0~~xymon13+202611010000p1111111"

# The next version's snapshots follow this version's release.
below "4.3.32-1~~xymon13+9" "4.3.33~git202701010000.abcdefa-0~~xymon13+202701010000p1234abc"

# Previews advance by preview number -- numerically, so preview10 follows
# preview9 -- then by packaging, and the release supersedes them all.
below "4.3.31-1~~xymon13+9" "4.3.32~preview1-0~~xymon13+202611251000pab12cd3"
below "4.3.32~preview1-0~~xymon13+202611251000pab12cd3" "4.3.32~preview2-0~~xymon13+202611251000pab12cd3"
below "4.3.32~preview9-0~~xymon13+202611251000pab12cd3" "4.3.32~preview10-0~~xymon13+202611251000pab12cd3"
below "4.3.32~preview1-0~~xymon13+202611251000pab12cd3" "4.3.32~preview1-0~~xymon13+202611261000pdeadbee"
below "4.3.32~preview10-0~~xymon13+209912312359pfffffff" "4.3.32-1~~xymon13+1"
# A later milestone's preview outranks an earlier one's release, so a host
# following a preview suite moves forward when a milestone ships.
below "4.3.32-1~~xymon13+9" "4.3.33~preview1-0~~xymon13+202611251000pab12cd3"

# A preview sorts above a snapshot of the same version ("~p" after "~g"),
# the reverse of xymon-rpm. Either way the two are not to be enabled
# together; this pins which one would win, so a change of scheme shows.
below "4.3.32~git209912312359.fffffff-0~~xymon13+209912312359pfffffff" \
      "4.3.32~preview1-0~~xymon13+202611010000p1111111"

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
	case "$built" in
	*"~git"*|*"~preview"*)
		# A pre-release: below the version it leads to, however built.
		x=${built%%~*}
		below "$built" "$x-1~~xymon$VERSION_ID+1"
		below "$built" "$x-1"
		;;
	*)
		below "$built" "$deb~bpo${VERSION_ID%%.*}+1"
		below "$built" "$deb"
		;;
	esac
fi

exit "$fail"
