#!/bin/sh
#
# Emit the file users drop into /etc/apt/sources.list.d as xymon.sources.
#
#   mksources.sh <codename>
#
# One file per release: apt has no variable for the codename, unlike dnf's
# $releasever, so the suite is written out and the publish job generates one
# file per suite it serves.
#
# The signing key is inside the file (Signed-By takes an armored key since
# apt 2.3.10, older than every release built here). So adding the repository
# is one file to fetch, and the key trusts this repository alone, not every
# source on the host as a key in /etc/apt/trusted.gpg.d would.
#
# XYMON_REPO_BASEURL and XYMON_KEY_FILE override where the repository is and
# which key is embedded; tests/publish.sh uses both.

set -eu

codename=${1:?usage: mksources.sh <codename>}
base=${XYMON_REPO_BASEURL:-https://xymon-monitoring.github.io/xymon-apt}
keyfile=${XYMON_KEY_FILE:-$(dirname "$0")/../xymon-archive-keyring.asc}

[ -r "$keyfile" ] || { echo "mksources.sh: cannot read $keyfile" >&2; exit 1; }

# The caveat is inside the generated file, not above this heredoc: it is for
# whoever reads the installed file, and a comment here never reaches them.
cat <<EOF
# HIGHLY EXPERIMENTAL: an unofficial rebuild of Debian's xymon package, new
# and with no production use. Versioning, suites and repository structure
# may still change without notice -- do not point production machines at it
# yet.
#
# After a release upgrade, fetch this file again for the new release:
# the suite below is $codename and nothing moves it.
#
# Pre-release channels are suites of their own, to add to Suites below
# deliberately, per host. For testing, not production:
#
#   $codename-snapshot      builds of upstream main, with no release testing
#   $codename-preview       previews of every unreleased milestone
#   $codename-preview-next  previews of the next release alone
#
# e.g. "Suites: $codename $codename-snapshot". Add one of them, not a
# snapshot together with a preview: they are different lines of code.
Types: deb
URIs: $base
Suites: $codename
Components: main
Signed-By:
EOF
# A deb822 continuation line starts with a space, and an empty one is " .".
sed -e 's/^$/./' -e 's/^/ /' "$keyfile"
