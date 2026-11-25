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

client=$(find "$debs" -maxdepth 1 -name 'xymon-client_*.deb' | head -1)
[ -n "$client" ] || { echo "NOT OK   no xymon-client_*.deb in $debs"; exit 1; }

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

# --- a first publish, from artifacts named as the workflow names them ---
mkdir -p "$work/a1/pub-$c-$arch"
cp "$debs"/xymon_*.deb "$debs"/xymon-client_*.deb "$work/a1/pub-$c-$arch/"
"$root/build/publish.sh" "$work/a1" "$tree" > "$work/log1" 2>&1 ||
	{ echo "NOT OK   publish.sh failed:"; cat "$work/log1"; exit 1; }

cb=$(basename "$client")
check "the packages are filed under pool/$c" '[ -e "$tree/pool/$c/$cb" ]'
check "the suite has a Packages index for $arch" \
	'grep -q "^Package: xymon-client$" "$tree/dists/$c/main/binary-$arch/Packages"'
check "the index names the file where it is" \
	'grep -q "^Filename: pool/$c/$cb$" "$tree/dists/$c/main/binary-$arch/Packages"'
check "InRelease verifies against the signing key" \
	'gpg --batch --verify "$tree/dists/$c/InRelease"'
check "Release.gpg verifies against the signing key" \
	'gpg --batch --verify "$tree/dists/$c/Release.gpg" "$tree/dists/$c/Release"'
check "Release names the suite $c" 'grep -q "^Codename: $c$" "$tree/dists/$c/Release"'

# --- a published version is never overwritten ---
mkdir -p "$work/a2/pub-$c-$arch"
cp "$client" "$work/a2/pub-$c-$arch/"
echo tampered >> "$work/a2/pub-$c-$arch/$cb"
"$root/build/publish.sh" "$work/a2" "$tree" > "$work/log2" 2>&1 || cat "$work/log2"
check "a second build of a published version does not replace it" \
	'cmp -s "$client" "$tree/pool/$c/$cb"'
check "and the log says so" 'grep -q "already published, leaving alone: pool/$c/$cb" "$work/log2"'

# --- a later rebuild is added beside the earlier one ---
# The same package with its version bumped, as a releasenum rebuild would be.
old=$(dpkg-deb -f "$client" Version)
new="${old%+*}+99"
dpkg-deb -R "$client" "$work/unpacked"
sed -i "s/^Version: .*/Version: $new/" "$work/unpacked/DEBIAN/control"
mkdir -p "$work/a3/pub-$c-$arch"
dpkg-deb -b "$work/unpacked" "$work/a3/pub-$c-$arch/xymon-client_${new}_$arch.deb" >/dev/null
"$root/build/publish.sh" "$work/a3" "$tree" > "$work/log3" 2>&1 || cat "$work/log3"
check "a rebuild is published beside the version it supersedes" \
	'[ -e "$tree/pool/$c/$cb" ] && [ -e "$tree/pool/$c/xymon-client_${new}_$arch.deb" ]'
check "the index lists both versions of xymon-client" \
	'[ "$(grep -A8 "^Package: xymon-client$" "$tree/dists/$c/main/binary-$arch/Packages" | grep -c "^Version: ")" = 2 ]'

# --- a publish that brings nothing for a suite leaves it served ---
mkdir -p "$work/a4"
"$root/build/publish.sh" "$work/a4" "$tree" > "$work/log4" 2>&1 || cat "$work/log4"
check "a publish with no package for $c keeps the suite" \
	'grep -q "^Package: xymon$" "$tree/dists/$c/main/binary-$arch/Packages"'
check "and it is still signed" 'gpg --batch --verify "$tree/dists/$c/InRelease"'

# --- apt can use it, through the file mksources.sh generates ---
XYMON_REPO_BASEURL="file://$tree" XYMON_KEY_FILE="$work/key.asc" \
	"$root/build/mksources.sh" "$c" > "$list"
check "apt-get update accepts the repository and its signature" \
	'apt-get update -o Dir::Etc::sourcelist="$list" -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0 2>&1 | tee "$work/update.log"; ! grep -Eq "^(E|W):" "$work/update.log"'
check "apt's candidate for xymon-client is the newest published rebuild" \
	'[ "$(apt-cache policy xymon-client | awk "/Candidate:/{print \$2}")" = "$new" ]'
check "apt can still see the superseded version" \
	'apt-cache madison xymon-client | grep -qF "$old"'

# --- the pre-release channels exist, empty, from the first publish ---
for ch in snapshot preview preview-next; do
	check "the suite $c-$ch exists, signed" 'gpg --batch --verify "$tree/dists/$c-$ch/InRelease"'
	check "and lists no package" '[ ! -s "$tree/dists/$c-$ch/main/binary-$arch/Packages" ]'
done
check "the generated file names the channels a host can add" 'grep -q "^#   $c-snapshot " "$list"'
# Enabled the way the file says: appended to Suites.
sed -i "s/^Suites: .*/Suites: $c $c-snapshot $c-preview-next/" "$list"
check "apt-get update accepts the empty channels beside the stable suite" \
	'apt-get update -o Dir::Etc::sourcelist="$list" -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0 2>&1 | tee "$work/update2.log"; ! grep -Eq "^(E|W):" "$work/update2.log"'
check "and the candidate is still the stable suite's" \
	'[ "$(apt-cache policy xymon-client | awk "/Candidate:/{print \$2}")" = "$new" ]'

# A repository signed by another key is refused: the Signed-By in the
# generated file is what binds it, not a key the host happens to trust.
XYMON_REPO_BASEURL="file://$tree" "$root/build/mksources.sh" "$c" > "$list"
check "apt refuses the tree when the file carries a different key" \
	'apt-get update -o Dir::Etc::sourcelist="$list" -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0 2>&1 | grep -Eq "NO_PUBKEY|not signed|Missing key|no public key"'

# --- the index pages ---
"$root/build/mkindex.sh" "$tree" >/dev/null
check "the landing page links the suite $c" 'grep -q "dists/$c/" "$tree/index.html"'
check "every directory gets a listing" '[ -e "$tree/pool/$c/index.html" ]'

[ "$fail" = 0 ] || { echo; echo "--- apt-get update ---"; cat "$work/update.log" 2>/dev/null || true; }
exit "$fail"
