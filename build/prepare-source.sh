#!/bin/sh
#
# Fetch the upstream tree a pre-release is built from, and name the build.
#
#   prepare-source.sh <xymon-ref> <source-dir>
#
# <xymon-ref> is a branch or a sha of xymon-monitoring/xymon; a pull request
# of it, as pr/NNN; a preview-X.Y.Z-N tag, which xymon-experimental makes:
# main plus the pull requests of X.Y.Z and of the unreleased milestones
# before it; or a release tag of xymon, rel-X.Y.Z, for a release Debian has
# not packaged yet.
#
# Leaves in <source-dir>, for build/build-deb.sh:
#   tree/              git archive of the ref: nothing modified after the clone
#   upstream-version   X.Y.Z~git<datetime>.<sha>, X.Y.Z~preview<N>, or X.Y.Z
#   packaging-id       <datetime>p<sha> of the packaging
#
# Run on the host, from a full clone of this repository: it needs git, and
# the history to find the packaging commit. The containers that build have
# neither.

set -eu

ref=${1:?usage: prepare-source.sh <xymon-ref> <source-dir>}
dir=${2:?usage: prepare-source.sh <xymon-ref> <source-dir>}
here=$(dirname "$(dirname "$(realpath "$0")")")

rm -rf "$dir"
mkdir -p "$dir/tree"
git clone -q --filter=blob:none https://github.com/xymon-monitoring/xymon.git "$dir/git"

case "$ref" in
rel-*)
	# A release Debian has not packaged yet, built as the pre-releases
	# are. Only an exact tag is one: a branch named rel-... is not, and
	# would otherwise reach the stable suites under a release's version.
	echo "$ref" | grep -Eq '^rel-[0-9]+\.[0-9]+\.[0-9]+$' ||
		{ echo "prepare-source.sh: $ref is not rel-X.Y.Z" >&2; exit 1; }
	git -C "$dir/git" rev-parse -q --verify "refs/tags/$ref" >/dev/null ||
		{ echo "prepare-source.sh: xymon has no tag $ref" >&2; exit 1; }
	git -C "$dir/git" checkout -q "refs/tags/$ref"
	upstream=${ref#rel-}
	;;
preview-*)
	echo "$ref" | grep -Eq '^preview-[0-9]+\.[0-9]+\.[0-9]+-[0-9]+$' ||
		{ echo "prepare-source.sh: $ref is not preview-X.Y.Z-N" >&2; exit 1; }
	git -C "$dir/git" fetch -q https://github.com/xymon-monitoring/xymon-experimental.git \
		"refs/tags/$ref:refs/tags/$ref"
	git -C "$dir/git" checkout -q "$ref"
	m=${ref#preview-}
	upstream="${m%-*}~preview${m##*-}"
	;;
*)
	case "$ref" in
	pr/*)
		# A plain clone does not carry refs/pull/*. The head of a pull
		# request moves, so say which commit this build came from.
		pr=${ref#pr/}
		echo "$pr" | grep -Eq '^[0-9]+$' ||
			{ echo "prepare-source.sh: $ref is not pr/NNN" >&2; exit 1; }
		git -C "$dir/git" fetch -q origin "pull/$pr/head:pr-$pr"
		git -C "$dir/git" checkout -q "pr-$pr"
		echo "pull request #$pr at $(git -C "$dir/git" rev-parse --short=7 HEAD)"
		;;
	*)
		git -C "$dir/git" checkout -q "$ref"
		;;
	esac
	# The version upstream's main is becoming: include/version.h says
	# X.Y.Z-dev from the release before it on; the suffix goes.
	base=$(sed -n 's/^#define VERSION "\([0-9][0-9.]*\).*"$/\1/p' "$dir/git/include/version.h")
	[ -n "$base" ] || { echo "prepare-source.sh: no #define VERSION in include/version.h" >&2; exit 1; }
	# Date and time, in UTC, then the sha: dpkg compares the digits as a
	# number, so builds advance by commit time, and the sha only names.
	date=$(TZ=UTC git -C "$dir/git" log -1 --format=%cd --date=format-local:%Y%m%d%H%M)
	upstream="$base~git$date.$(git -C "$dir/git" rev-parse --short=7 HEAD)"
	;;
esac

# The last commit that can change a package -- not HEAD. A published version
# is immutable, so without this half a packaging-only change would rebuild
# the previous run's version and never ship. Keyed on HEAD instead, a docs
# or test commit would mint a new version for an identical package; so
# would a README under one of these paths, which is left out.
pkgpaths="build backport prerelease source.dsc.sha256 .github"
# shellcheck disable=SC2086
pkgdate=$(TZ=UTC git -C "$here" log -1 --format=%cd --date=format-local:%Y%m%d%H%M -- $pkgpaths ':(exclude)*.md')
# shellcheck disable=SC2086
pkgref=$(git -C "$here" log -1 --format=%h --abbrev=7 -- $pkgpaths ':(exclude)*.md')
[ -n "$pkgdate" ] && [ -n "$pkgref" ] ||
	{ echo "prepare-source.sh: no packaging commit found -- a shallow clone?" >&2; exit 1; }

git -C "$dir/git" archive --format=tar HEAD | tar -x -C "$dir/tree"
echo "$upstream" > "$dir/upstream-version"
echo "${pkgdate}p${pkgref}" > "$dir/packaging-id"
echo "built from $(git -C "$dir/git" rev-parse HEAD)" > "$dir/commit"
rm -rf "$dir/git"

echo "source: $ref -> $upstream, packaging ${pkgdate}p${pkgref}"
