#!/bin/sh
#
# Fold the built packages into the published APT repository and sign it.
#
#   publish.sh <artifacts-dir> <repo-dir>
#
# <artifacts-dir> holds one subdirectory per build, named <codename> or
# pub-<codename>-<arch> (what the workflow's artifacts are called), each
# containing that build's .deb files. <repo-dir> is a checkout of the
# published repository, updated in place; the caller commits and pushes it.
#
#   <repo-dir>/pool/<codename>/*.deb
#   <repo-dir>/dists/<codename>/{InRelease,Release,Release.gpg,main/binary-<arch>/Packages*}
#
# One stable suite per codename, component "main". Every package ever
# published there stays: people pin a version and roll back, and a suite whose
# target left the build matrix keeps being served as it was.
#
# A pre-release goes to a suite of its own beside it, by its version:
#   X.Y.Z~git...      <codename>-snapshot      a build of upstream main
#   X.Y.Z~preview<N>  <codename>-preview       a xymon-experimental preview
# and <codename>-preview-next is rebuilt on every run from the previews of
# the next release alone. Those three are bounded by the retention below.
#
# XYMON_GPG_KEY names the signing key (default: gpg's default key).
# XYMON_SNAPSHOT_KEEP and XYMON_PREVIEW_KEEP override the retention.

set -eu

artifacts=${1:?usage: publish.sh <artifacts-dir> <repo-dir>}
repodir=${2:?usage: publish.sh <artifacts-dir> <repo-dir>}
key=${XYMON_GPG_KEY:-}

command -v apt-ftparchive >/dev/null ||
	{ echo "apt-ftparchive not found -- install apt-utils" >&2; exit 1; }

# Keeping the lines in separate suites is what stops a stable host being
# moved onto a nightly build, and a snapshot host onto a preview. Decided by
# the version in the file name, not by which run built it, so a package
# cannot be filed where its version does not belong.
suite_for() {
	case "$2" in
	*~git*)     echo "$1-snapshot" ;;
	*~preview*) echo "$1-preview" ;;
	*)          echo "$1" ;;
	esac
}

# xymon-client_4.3.31-1~~xymon13+1_arm64.deb -> 4.3.31-1~~xymon13+1
version_of() {
	v=${1##*/}
	v=${v#*_}
	echo "${v%_*}"
}

echo "== filing packages =="
new=0
for dir in "$artifacts"/*/; do
	[ -d "$dir" ] || continue
	# pub-trixie-arm64, pre-trixie-arm64 -> trixie; a codename holds no
	# hyphen.
	c=$(basename "$dir")
	c=${c#pub-}
	c=${c#pre-}
	c=${c%-*}
	for pkg in "$dir"*.deb; do
		[ -e "$pkg" ] || continue
		base=$(basename "$pkg")
		# dbgsym packages: ten times the size, rarely wanted.
		case "$base" in *-dbgsym_*) continue ;; esac
		suite=$(suite_for "$c" "$base")
		dest="$repodir/pool/$suite"
		mkdir -p "$dest"
		# Never overwrite: a published version is immutable. apt compares
		# the file it downloads with the hash in the index it already
		# trusts, and a mirror or a cache holding the first copy would
		# refuse the second. A changed package needs a new version: bump
		# releasenum.
		if [ -e "$dest/$base" ]; then
			echo "  already published, leaving alone: pool/$suite/$base"
		else
			cp -p "$pkg" "$dest/$base"
			echo "  + pool/$suite/$base"
			new=$((new + 1))
		fi
	done
done
echo "  $new new package(s)"

# The pre-release channels, each a suite of its own beside the stable one:
# <codename>-snapshot, <codename>-preview, <codename>-preview-next, named as
# xymon-rpm names its channels.
channels="snapshot preview preview-next"

# drop_except <pool-dir> <kept-versions> <why>: remove every package whose
# version is not in the list. Whole builds go, never single files: the server
# depends on the client of its own version, so half a build left behind is a
# package apt cannot install. Named, not silent: a repository that quietly
# loses builds looks like one that never had them.
drop_except() {
	for f in "$1"/*.deb; do
		[ -e "$f" ] || continue
		printf '%s\n' "$2" | grep -qxF "$(version_of "$f")" && continue
		rm -f "$f"
		echo "  - ${f#"$repodir"/} ($3)"
	done
}

# The versions in a pool directory, newest first. sort -V orders these as
# dpkg does: they differ only in digit runs, and in a sha that follows one.
versions_in() {
	for f in "$1"/*.deb; do
		[ -e "$f" ] || continue
		version_of "$f"
	done | sort -u | sort -rV
}

# --- snapshot retention ------------------------------------------------
#
# What is counted is upstream commits, and each keeps only its newest
# packaging rebuild: rolling back on a snapshot suite means going back to a
# different state of Xymon, and an older packaging of the state you already
# have is not that. xymon-rpm's rule, for its reason.
keep=${XYMON_SNAPSHOT_KEEP:-10}
for dir in "$repodir"/pool/*-snapshot; do
	[ -d "$dir" ] || continue
	echo "== pruning ${dir#"$repodir"/} (keeping $keep upstream builds, newest packaging of each) =="
	# 4.3.32~git202611250108.dc9c799-0~~xymon13+202611251000pab12cd3:
	# the upstream commit is what precedes the last "-".
	kept=$(versions_in "$dir" | awk -v k="$keep" '{ u = $0; sub(/-[^-]*$/, "", u) }
		!(u in seen) { seen[u] = 1; if (++n <= k) print }')
	drop_except "$dir" "$kept" "superseded packaging, or past the newest $keep upstream builds"
done

# --- preview retention -------------------------------------------------
#
# A preview suite holds every unreleased milestone at once; what is bounded
# is the history of each. Per milestone the newest $pkeep previews stay,
# each in its newest packaging rebuild. A released milestone keeps none: the
# rebuild of X.Y.Z in the stable suite outranks every preview of it.
pkeep=${XYMON_PREVIEW_KEEP:-2}
for dir in "$repodir"/pool/*-preview; do
	[ -d "$dir" ] || continue
	c=$(basename "$dir")
	c=${c%-preview}
	echo "== pruning ${dir#"$repodir"/} (keeping $pkeep previews per unreleased milestone) =="
	# The milestones the stable suite holds: X.Y.Z-..., with no "~" before
	# the revision.
	released=$(versions_in "$repodir/pool/$c" | sed -n 's/^\([0-9][0-9.]*\)-.*/\1/p' | sort -u)
	# 4.3.32~preview5-0~~xymon13+202611251000pab12cd3 -> milestone 4.3.32,
	# preview 4.3.32~preview5.
	kept=$(versions_in "$dir" | awk -v k="$pkeep" -v rel="$released" '
		BEGIN { n = split(rel, r, "\n"); for (i = 1; i <= n; i++) isrel[r[i]] = 1 }
		{ p = $0; sub(/-[^-]*$/, "", p); m = p; sub(/~.*/, "", m) }
		isrel[m] { next }
		!(p in seen) { seen[p] = 1; if (++count[m] <= k) print }')
	drop_except "$dir" "$kept" "its milestone is released, or past its newest $pkeep previews, or superseded packaging"

	# --- the next release's previews -----------------------------------
	#
	# <codename>-preview-next holds the previews of the next release alone:
	# the lowest milestone with a preview and no release in the stable suite.
	# A host that follows only the release that is coming enables it. Rebuilt
	# from the preview suite on every run, so a release moves it on to the
	# following milestone by itself.
	next=$(printf '%s\n' "$kept" | sed -n 's/~.*//p' | sort -uV | head -1)
	rm -rf "${repodir:?}/pool/$c-preview-next"
	if [ -n "$next" ]; then
		mkdir -p "$repodir/pool/$c-preview-next"
		for f in "$dir"/*.deb; do
			[ -e "$f" ] || continue
			case "$(version_of "$f")" in "$next~"*) cp -p "$f" "$repodir/pool/$c-preview-next/" ;; esac
		done
	fi
	echo "  $c-preview-next: ${next:-no unreleased milestone}"
done

# The architectures a suite's pool holds, space-separated.
archs_of() {
	found=
	for f in "$repodir/pool/$1"/*.deb; do
		[ -e "$f" ] || continue
		a=${f##*_}
		a=${a%.deb}
		case " $found all " in *" $a "*) ;; *) found="$found $a" ;; esac
	done
	echo "${found# }"
}

# mksuite <suite> <archs>: rebuild and sign one suite's indexes.
mksuite() {
	s=$1
	# Rebuilt whole from the pool: an index that lists a file the pool
	# lacks, or the reverse, is the one state apt cannot recover from.
	rm -rf "${repodir:?}/dists/$s"
	for a in $2; do
		b="dists/$s/main/binary-$a"
		mkdir -p "$repodir/$b"
		if [ -d "$repodir/pool/$s" ]; then
			# -a keeps *_<arch>.deb and *_all.deb.
			(cd "$repodir" && apt-ftparchive -a "$a" packages "pool/$s" > "$b/Packages")
		else
			: > "$repodir/$b/Packages"
		fi
		gzip -9kf "$repodir/$b/Packages"
	done
	# Written outside the suite, then moved in: apt-ftparchive hashes
	# every index under the directory it is given, a Release file included.
	(cd "$repodir/dists/$s" && apt-ftparchive \
		-o APT::FTPArchive::Release::Origin=xymon-apt \
		-o APT::FTPArchive::Release::Label=Xymon \
		-o APT::FTPArchive::Release::Suite="$s" \
		-o APT::FTPArchive::Release::Codename="$s" \
		-o APT::FTPArchive::Release::Components=main \
		-o APT::FTPArchive::Release::Architectures="$2" \
		release . > ../Release."$s".tmp && mv ../Release."$s".tmp Release)
	# The index is what is signed, not each .deb: apt trusts a package
	# because the signed Release names the Packages file that names its hash.
	# InRelease is what apt reads; Release.gpg is for older clients.
	# shellcheck disable=SC2086
	gpg --batch --yes ${key:+-u "$key"} --clearsign \
		-o "$repodir/dists/$s/InRelease" "$repodir/dists/$s/Release"
	# shellcheck disable=SC2086
	gpg --batch --yes ${key:+-u "$key"} --armor --detach-sign \
		-o "$repodir/dists/$s/Release.gpg" "$repodir/dists/$s/Release"
	echo "  dists/$s ($2)"
}

echo "== regenerating metadata =="
for dir in "$repodir"/pool/*/; do
	[ -d "$dir" ] || continue
	c=$(basename "$dir")
	archs=$(archs_of "$c")
	[ -n "$archs" ] || continue
	mksuite "$c" "$archs"

	# A channel with no package yet still gets a suite, signed and empty,
	# for every stable suite. The xymon.sources a host fetched names its
	# channels in a comment, to be enabled by adding them to Suites; with
	# no Release file there, that edit fails apt update on this repository
	# instead of finding nothing. So the suites exist from the first
	# publish, and the file never has to be fetched again when a channel
	# starts.
	case "$c" in *-snapshot|*-preview|*-preview-next) continue ;; esac
	for ch in $channels; do
		[ -z "$(archs_of "$c-$ch")" ] || continue
		mksuite "$c-$ch" "$archs"
	done
done

echo "== published tree =="
(cd "$repodir" && find pool -name '*.deb' | sort)
