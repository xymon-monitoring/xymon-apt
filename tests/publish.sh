#!/bin/sh
#
# What build/publish.sh does to the published tree, and whether apt can use
# the result. Nothing here touches the real repository: it publishes into a
# temporary directory with a throwaway signing key.
#
# The publish job never runs from a pull request, so this is the only place
# publish.sh and mksources.sh are exercised before they meet the real tree.
#
#   Usage: tests/publish.sh [deb-dir]
#
# Run as root in a fresh Debian/Ubuntu container: it installs apt-utils and
# gnupg, and adds then removes a file in /etc/apt/sources.list.d.

set -eu

debs=$(realpath "${1:-out}")
root=$(dirname "$(dirname "$(realpath "$0")")")

fail=0
check() {
	if eval "$2" >/dev/null 2>&1; then
		echo "ok       $1"
	else
		echo "NOT OK   $1"
		fail=1
	fi
}

[ -n "$(find "$debs" -maxdepth 1 -name 'xymon-client_*.deb')" ] &&
	[ -n "$(find "$debs" -maxdepth 1 -name 'xymon_*.deb')" ] ||
	{ echo "NOT OK   need xymon_*.deb and xymon-client_*.deb in $debs"; exit 1; }

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends apt-utils gnupg >/dev/null

. /etc/os-release
c=${VERSION_CODENAME:?}
arch=$(dpkg --print-architecture)

work=$(mktemp -d)
list=/etc/apt/sources.list.d/xymon-publish-test.sources
trap 'rm -rf "$work" "$list"' EXIT
# apt fetches as the _apt user, which must be able to read a file:// tree.
chmod 755 "$work"
export GNUPGHOME="$work/gnupg"
mkdir -p "$GNUPGHOME"
chmod 700 "$GNUPGHOME"

# The key the repository is signed with is the one this tree publishes.
want=$(sed -n 's/^ *FINGERPRINT=//p' "$root/fingerprint" | tr -d ' ')
have=$(gpg --batch --show-keys --with-colons "$root/xymon-archive-keyring.asc" 2>/dev/null |
	awk -F: '/^fpr:/{print $10; exit}')
check "xymon-archive-keyring.asc is the key the fingerprint file names" \
	'[ -n "$want" ] && [ "$want" = "$have" ]'

cat > "$work/keyparams" <<'EOF'
Key-Type: RSA
Key-Length: 2048
Key-Usage: sign
Name-Real: xymon-apt test key
Expire-Date: 0
%no-protection
%commit
EOF
gpg --batch --generate-key "$work/keyparams" >/dev/null 2>&1
gpg --batch --armor --export "xymon-apt test key" > "$work/key.asc"
export XYMON_GPG_KEY="xymon-apt test key"

tree="$work/tree"
mkdir -p "$tree"
v=${VERSION_ID:?}

# fake <artifact-dir> <version>: the build's own two packages, given another
# version. publish.sh files and prunes by the version in the file name, so
# every kind of build -- a rebuild, a snapshot, a preview, a later release --
# is exercised whatever kind produced the packages under test. Uncompressed:
# these are read once and thrown away.
fake() {
	mkdir -p "$1"
	for pkg in xymon xymon-client; do
		rm -rf "$work/unpacked"
		dpkg-deb -R "$(find "$debs" -maxdepth 1 -name "${pkg}_*.deb" | head -1)" "$work/unpacked"
		sed -i "s/^Version: .*/Version: $2/" "$work/unpacked/DEBIAN/control"
		dpkg-deb -Znone -b "$work/unpacked" "$1/${pkg}_$2_$arch.deb" >/dev/null
	done
}
publish() {
	"$root/build/publish.sh" "$1" "$tree" > "$work/log" 2>&1 ||
		{ echo "NOT OK   publish.sh failed on $1:"; cat "$work/log"; exit 1; }
}
has() { [ -e "$tree/pool/$1/xymon_$2_$arch.deb" ] && [ -e "$tree/pool/$1/xymon-client_$2_$arch.deb" ]; }
gone() { [ ! -e "$tree/pool/$1/xymon_$2_$arch.deb" ] && [ ! -e "$tree/pool/$1/xymon-client_$2_$arch.deb" ]; }
listed() { grep -q "^Version: $2$" "$tree/dists/$1/main/binary-$arch/Packages"; }
# apt against the tree, with the given suites enabled the way xymon.sources
# says: written into its Suites field.
update() {
	XYMON_REPO_BASEURL="file://$tree" XYMON_KEY_FILE="$work/key.asc" \
		"$root/build/mksources.sh" "$c" > "$list"
	sed -i "s/^Suites: .*/Suites: $*/" "$list"
	apt-get update -o Dir::Etc::sourcelist="$list" -o Dir::Etc::sourceparts=- \
		-o APT::Get::List-Cleanup=0 > "$work/update.log" 2>&1
	! grep -Eq "^(E|W):" "$work/update.log"
}
candidate() { apt-cache policy xymon-client | awk '/Candidate:/{print $2}'; }

s1="4.3.31-1~~xymon$v+1"
s2="4.3.31-1~~xymon$v+2"

# --- a first publish, from artifacts named as the workflow names them ---
fake "$work/a1/pub-$c-$arch" "$s1"
publish "$work/a1"
check "the packages are filed under pool/$c" 'has "$c" "$s1"'
check "the suite has a Packages index for $arch" \
	'grep -q "^Package: xymon-client$" "$tree/dists/$c/main/binary-$arch/Packages"'
check "the index names the file where it is" \
	'grep -q "^Filename: pool/$c/xymon-client_${s1}_$arch.deb$" "$tree/dists/$c/main/binary-$arch/Packages"'
check "InRelease verifies against the signing key" \
	'gpg --batch --verify "$tree/dists/$c/InRelease"'
check "Release.gpg verifies against the signing key" \
	'gpg --batch --verify "$tree/dists/$c/Release.gpg" "$tree/dists/$c/Release"'
check "Release names the suite $c" 'grep -q "^Codename: $c$" "$tree/dists/$c/Release"'

# --- a published version is never overwritten ---
mkdir -p "$work/a2/pub-$c-$arch"
cp "$work/a1/pub-$c-$arch/xymon-client_${s1}_$arch.deb" "$work/a2/pub-$c-$arch/"
echo tampered >> "$work/a2/pub-$c-$arch/xymon-client_${s1}_$arch.deb"
publish "$work/a2"
check "a second build of a published version does not replace it" \
	'cmp -s "$work/a1/pub-$c-$arch/xymon-client_${s1}_$arch.deb" "$tree/pool/$c/xymon-client_${s1}_$arch.deb"'
check "and the log says so" \
	'grep -q "already published, leaving alone: pool/$c/xymon-client_${s1}_$arch.deb" "$work/log"'

# --- a later rebuild is added beside the earlier one ---
fake "$work/a3/pub-$c-$arch" "$s2"
publish "$work/a3"
check "a rebuild is published beside the version it supersedes" 'has "$c" "$s1" && has "$c" "$s2"'
check "the index lists both versions" 'listed "$c" "$s1" && listed "$c" "$s2"'

# --- a publish that brings nothing for a suite leaves it served ---
mkdir -p "$work/a4"
publish "$work/a4"
check "a publish with no package for $c keeps the suite" 'listed "$c" "$s2"'
check "and it is still signed" 'gpg --batch --verify "$tree/dists/$c/InRelease"'

# --- the pre-release channels exist, empty, before anything is built ---
for ch in snapshot preview preview-next; do
	check "the suite $c-$ch exists, signed" 'gpg --batch --verify "$tree/dists/$c-$ch/InRelease"'
	check "and lists no package" '[ ! -s "$tree/dists/$c-$ch/main/binary-$arch/Packages" ]'
done

# --- apt can use it, through the file mksources.sh generates ---
check "apt-get update accepts the repository and its signature" 'update "$c"'
check "apt's candidate is the newest published rebuild" '[ "$(candidate)" = "$s2" ]'
check "apt can still see the superseded version" 'apt-cache madison xymon-client | grep -qF "$s1"'
check "the generated file names the channels a host can add" 'grep -q "^#   $c-snapshot " "$list"'
check "apt-get update accepts the empty channels beside the stable suite" \
	'update "$c $c-snapshot $c-preview $c-preview-next"'
check "and the candidate is still the stable suite's" '[ "$(candidate)" = "$s2" ]'

# --- snapshots: their own suite, and a retention that counts upstream ---
# Three upstream commits; the first built twice, by two packaging commits.
u1="4.3.32~git202611010000.aaaaaaa-0~~xymon$v"
u2="4.3.32~git202611020000.bbbbbbb-0~~xymon$v"
u3="4.3.32~git202611030000.ccccccc-0~~xymon$v"
p1="202611010000p1111111"
p2="202611050000p2222222"
for sv in "$u1+$p1" "$u1+$p2" "$u2+$p1" "$u3+$p1"; do fake "$work/a5/pre-$c-$arch" "$sv"; done
( export XYMON_SNAPSHOT_KEEP=2; publish "$work/a5" )
check "a snapshot is filed in $c-snapshot" 'has "$c-snapshot" "$u3+$p1"'
check "and never in the stable suite" 'gone "$c" "$u3+$p1" && ! listed "$c" "$u3+$p1"'
check "retention keeps the newest upstream builds" 'has "$c-snapshot" "$u2+$p1" && listed "$c-snapshot" "$u3+$p1"'
check "and drops whole builds past them, server and client" \
	'gone "$c-snapshot" "$u1+$p1" && gone "$c-snapshot" "$u1+$p2"'
check "the stable suite is untouched by it" 'has "$c" "$s1" && has "$c" "$s2"'
# A packaging-only change rebuilds the newest upstream commit.
fake "$work/a6/pre-$c-$arch" "$u3+$p2"
( export XYMON_SNAPSHOT_KEEP=2; publish "$work/a6" )
check "a packaging rebuild replaces the build of the same upstream commit" \
	'has "$c-snapshot" "$u3+$p2" && gone "$c-snapshot" "$u3+$p1"'
check "without spending a slot: the previous upstream build stays" 'has "$c-snapshot" "$u2+$p1"'
check "a host on the stable suite alone is not offered a snapshot" \
	'update "$c" && [ "$(candidate)" = "$s2" ]'
check "a host that added $c-snapshot gets the newest one" \
	'update "$c $c-snapshot" && [ "$(candidate)" = "$u3+$p2" ]'

# --- previews: two per unreleased milestone, and the next release's alone ---
for pv in "4.3.32~preview1" "4.3.32~preview2" "4.3.32~preview3" "4.3.33~preview1"; do
	fake "$work/a7/pre-$c-$arch" "$pv-0~~xymon$v+$p1"
done
pre() { echo "$1-0~~xymon$v+$p1"; }
publish "$work/a7"
check "previews are filed in $c-preview" 'has "$c-preview" "$(pre 4.3.32~preview3)"'
check "the newest two of a milestone stay" \
	'has "$c-preview" "$(pre 4.3.32~preview2)" && gone "$c-preview" "$(pre 4.3.32~preview1)"'
check "every unreleased milestone is there" 'has "$c-preview" "$(pre 4.3.33~preview1)"'
check "$c-preview-next holds the next release's previews" \
	'listed "$c-preview-next" "$(pre 4.3.32~preview3)" && listed "$c-preview-next" "$(pre 4.3.32~preview2)"'
check "and not a later milestone's" '! listed "$c-preview-next" "$(pre 4.3.33~preview1)"'
check "a host that added $c-preview-next gets the next release's newest preview" \
	'update "$c $c-preview-next" && [ "$(candidate)" = "$(pre 4.3.32~preview3)" ]'
# 4.3.32 is released: it reaches the stable suite.
r32="4.3.32-1~~xymon$v+1"
fake "$work/a8/pub-$c-$arch" "$r32"
publish "$work/a8"
check "a released milestone keeps no preview" \
	'gone "$c-preview" "$(pre 4.3.32~preview3)" && gone "$c-preview" "$(pre 4.3.32~preview2)"'
check "$c-preview-next moves on to the following milestone" \
	'listed "$c-preview-next" "$(pre 4.3.33~preview1)" && ! listed "$c-preview-next" "$(pre 4.3.32~preview3)"'
check "the release outranks the snapshots and previews of its version" \
	'update "$c $c-snapshot" && [ "$(candidate)" = "$r32" ]'
# And 4.3.33: no unreleased milestone is left.
fake "$work/a9/pub-$c-$arch" "4.3.33-1~~xymon$v+1"
publish "$work/a9"
check "with no unreleased milestone, $c-preview-next is empty, and still served" \
	'[ ! -s "$tree/dists/$c-preview-next/main/binary-$arch/Packages" ] && gpg --batch --verify "$tree/dists/$c-preview-next/InRelease"'
check "and so is $c-preview" \
	'[ ! -s "$tree/dists/$c-preview/main/binary-$arch/Packages" ] && gpg --batch --verify "$tree/dists/$c-preview/InRelease"'
check "apt still accepts every suite" 'update "$c $c-snapshot $c-preview $c-preview-next"'

# A repository signed by another key is refused: the Signed-By in the
# generated file is what binds it, not a key the host happens to trust.
XYMON_REPO_BASEURL="file://$tree" "$root/build/mksources.sh" "$c" > "$list"
check "apt refuses the tree when the file carries a different key" \
	'apt-get update -o Dir::Etc::sourcelist="$list" -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0 2>&1 | grep -Eq "NO_PUBKEY|not signed|Missing key|no public key"'

# --- the index pages ---
"$root/build/mkindex.sh" "$tree" >/dev/null
check "the landing page links the suite $c" 'grep -q "dists/$c/" "$tree/index.html"'
check "and offers no xymon.sources for a channel" '! grep -q "$c-snapshot/xymon.sources" "$tree/index.html"'
check "every directory gets a listing" '[ -e "$tree/pool/$c/index.html" ]'

[ "$fail" = 0 ] || { echo; echo "--- last publish ---"; cat "$work/log"; echo "--- last apt-get update ---"; cat "$work/update.log" 2>/dev/null || true; }
exit "$fail"
