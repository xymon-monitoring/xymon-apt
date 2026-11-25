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
# One suite per codename, component "main". Every package ever published
# stays: people pin a version and roll back, and a suite whose target left
# the build matrix keeps being served as it was.
#
# XYMON_GPG_KEY names the signing key (default: gpg's default key).

set -eu

artifacts=${1:?usage: publish.sh <artifacts-dir> <repo-dir>}
repodir=${2:?usage: publish.sh <artifacts-dir> <repo-dir>}
key=${XYMON_GPG_KEY:-}

command -v apt-ftparchive >/dev/null ||
	{ echo "apt-ftparchive not found -- install apt-utils" >&2; exit 1; }

echo "== filing packages =="
new=0
for dir in "$artifacts"/*/; do
	[ -d "$dir" ] || continue
	# pub-trixie-arm64 -> trixie; a codename holds no hyphen.
	c=$(basename "$dir")
	c=${c#pub-}
	c=${c%-*}
	for pkg in "$dir"*.deb; do
		[ -e "$pkg" ] || continue
		base=$(basename "$pkg")
		# dbgsym packages: ten times the size, rarely wanted.
		case "$base" in *-dbgsym_*) continue ;; esac
		dest="$repodir/pool/$c"
		mkdir -p "$dest"
		# Never overwrite: a published version is immutable. apt compares
		# the file it downloads with the hash in the index it already
		# trusts, and a mirror or a cache holding the first copy would
		# refuse the second. A changed package needs a new version: bump
		# releasenum.
		if [ -e "$dest/$base" ]; then
			echo "  already published, leaving alone: pool/$c/$base"
		else
			cp -p "$pkg" "$dest/$base"
			echo "  + pool/$c/$base"
			new=$((new + 1))
		fi
	done
done
echo "  $new new package(s)"

# The pre-release channels, each a suite of its own beside the stable one:
# <codename>-snapshot, <codename>-preview, <codename>-preview-next, named as
# xymon-rpm names its channels. Nothing builds into them yet.
channels="snapshot preview preview-next"

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
