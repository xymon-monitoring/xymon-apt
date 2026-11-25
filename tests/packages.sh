#!/bin/sh
#
# What the built packages are, read without installing them. A break here
# is cheaper to see than in install.sh, which needs the network and a
# running server to say the same thing.
#
#   Usage: tests/packages.sh [deb-dir]
#
# Runs in the container of the release the packages were built for.

set -eu

debs=${1:-out}
fail=0
check() {
	if eval "$2" >/dev/null 2>&1; then
		echo "ok       $1"
	else
		echo "NOT OK   $1"
		fail=1
	fi
}

server=$(find "$debs" -maxdepth 1 -name 'xymon_*.deb' | head -1)
client=$(find "$debs" -maxdepth 1 -name 'xymon-client_*.deb' | head -1)
[ -n "$server" ] && [ -n "$client" ] ||
	{ echo "NOT OK   need xymon_*.deb and xymon-client_*.deb in $debs"; exit 1; }

field() { dpkg-deb -f "$1" "$2"; }

check "the server package is named xymon" '[ "$(field "$server" Package)" = xymon ]'
check "the client package is named xymon-client" '[ "$(field "$client" Package)" = xymon-client ]'

# One build, one version: a server installed beside a client of another
# rebuild is a combination nothing here has tested.
check "server and client carry the same version" \
	'[ "$(field "$server" Version)" = "$(field "$client" Version)" ]'

# A package built on the wrong runner would install nowhere it was meant to.
arch=$(dpkg --print-architecture)
check "the server is built for $arch" '[ "$(field "$server" Architecture)" = "$arch" ]'
check "the client is built for $arch" '[ "$(field "$client" Architecture)" = "$arch" ]'

# What the README promises: installing the server brings its client.
check "the server depends on xymon-client" \
	'field "$server" Depends | grep -qw xymon-client'

# The maintainer stays Debian's: this is their package rebuilt, and the
# changelog entry dch adds is what says who rebuilt it.
check "the Maintainer field is Debian's, untouched" \
	'field "$server" Maintainer | grep -qi "debian\.org"'

# tests/systemd.sh asserts how these two units behave; this asserts they
# are there to behave at all.
check "the server ships xymon.service" \
	'dpkg-deb -c "$server" | grep -q "systemd/system/xymon\.service$"'
check "the client ships xymon-client.service" \
	'dpkg-deb -c "$client" | grep -q "systemd/system/xymon-client\.service$"'

# Nothing under /usr/local or the build directory: either means the
# upstream build escaped Debian's install rules.
check "the server installs nothing under /usr/local" \
	'! dpkg-deb -c "$server" | grep -q " \./usr/local/."'
check "the client installs nothing under /usr/local" \
	'! dpkg-deb -c "$client" | grep -q " \./usr/local/."'

exit "$fail"
