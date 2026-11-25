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

echo "== regenerating metadata =="
for dir in "$repodir"/pool/*/; do
	[ -d "$dir" ] || continue
	c=$(basename "$dir")
	archs=
	for f in "$dir"*.deb; do
		[ -e "$f" ] || continue
		a=${f##*_}
		a=${a%.deb}
		case " $archs all " in *" $a "*) ;; *) archs="$archs $a" ;; esac
	done
	archs=${archs# }
	[ -n "$archs" ] || continue

	# Rebuilt whole from the pool: an index that lists a file the pool
	# lacks, or the reverse, is the one state apt cannot recover from.
	rm -rf "${repodir:?}/dists/$c"
	for a in $archs; do
		b="dists/$c/main/binary-$a"
		mkdir -p "$repodir/$b"
		# -a keeps *_<arch>.deb and *_all.deb.
		(cd "$repodir" && apt-ftparchive -a "$a" packages "pool/$c" > "$b/Packages")
		gzip -9kf "$repodir/$b/Packages"
	done
	# Written outside the suite, then moved in: apt-ftparchive hashes
	# every index under the directory it is given, a Release file included.
	(cd "$repodir/dists/$c" && apt-ftparchive \
		-o APT::FTPArchive::Release::Origin=xymon-apt \
		-o APT::FTPArchive::Release::Label=Xymon \
		-o APT::FTPArchive::Release::Suite="$c" \
		-o APT::FTPArchive::Release::Codename="$c" \
		-o APT::FTPArchive::Release::Components=main \
		-o APT::FTPArchive::Release::Architectures="$archs" \
		release . > ../Release."$c".tmp && mv ../Release."$c".tmp Release)
	# The index is what is signed, not each .deb: apt trusts a package
	# because the signed Release names the Packages file that names its hash.
	# InRelease is what apt reads; Release.gpg is for older clients.
	# shellcheck disable=SC2086
	gpg --batch --yes ${key:+-u "$key"} --clearsign \
		-o "$repodir/dists/$c/InRelease" "$repodir/dists/$c/Release"
	# shellcheck disable=SC2086
	gpg --batch --yes ${key:+-u "$key"} --armor --detach-sign \
		-o "$repodir/dists/$c/Release.gpg" "$repodir/dists/$c/Release"
	echo "  dists/$c ($archs)"
done

echo "== published tree =="
(cd "$repodir" && find pool -name '*.deb' | sort)
