#!/bin/sh
#
#   mkindex.sh <repo-dir>
#
# Generate browsable index pages for the published tree.
#
# apt never needs these -- it fetches dists/<suite>/InRelease by exact path
# and never asks for a listing. They exist because GitHub Pages has no
# autoindex, so without them a person opening any directory in a browser
# gets a bare 404 and reasonably concludes the repository is broken.

set -eu

repodir=${1:?usage: mkindex.sh <repo-dir>}
base=${XYMON_REPO_BASEURL:-https://xymon-monitoring.github.io/xymon-apt}
fpr=$(sed -n 's/^ *FINGERPRINT=//p' "$(dirname "$0")/../fingerprint" 2>/dev/null || true)

html_head() {
	cat <<EOF
<!doctype html>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$1</title>
<style>
  body { font-family: system-ui, sans-serif; line-height: 1.5;
         max-width: 52rem; margin: 2rem auto; padding: 0 1rem; }
  code, pre { font-family: ui-monospace, monospace; }
  pre { background: #f6f8fa; padding: .75rem 1rem; overflow-x: auto; }
  table { border-collapse: collapse; width: 100%; }
  td { padding: .2rem .6rem .2rem 0; white-space: nowrap; }
  td.size { text-align: right; color: #666; }
  a.up { color: #666; }
  @media (prefers-color-scheme: dark) {
    body { background: #0d1117; color: #e6edf3; }
    pre { background: #161b22; }
    a { color: #6cb6ff; } td.size, a.up { color: #9aa4ae; }
  }
</style>
<h1>$1</h1>
EOF
}

# --- per-directory listings -------------------------------------------
find "$repodir" -type d ! -path '*/.git' ! -path '*/.git/*' | while read -r dir; do
	rel=${dir#"$repodir"}
	rel=${rel#/}
	{
		html_head "${rel:-Xymon APT repository}/"
		[ -z "$rel" ] || echo '<p><a class="up" href="../">&#8592; parent directory</a></p>'
		echo '<table>'
		for entry in "$dir"/*/; do
			[ -d "$entry" ] || continue
			name=$(basename "$entry")
			printf '<tr><td><a href="%s/">%s/</a></td><td class="size"></td></tr>\n' \
				"$name" "$name"
		done
		for entry in "$dir"/*; do
			[ -f "$entry" ] || continue
			name=$(basename "$entry")
			case "$name" in index.html|.nojekyll) continue ;; esac
			size=$(( ($(wc -c < "$entry") + 1023) / 1024 ))
			printf '<tr><td><a href="%s">%s</a></td><td class="size">%s KB</td></tr>\n' \
				"$name" "$name" "$size"
		done
		echo '</table>'
	} > "$dir/index.html"
done

# --- root landing page ------------------------------------------------

# The suites actually in the tree, so the page cannot name one that 404s.
suites=
for d in "$repodir"/dists/*/; do
	[ -d "$d" ] || continue
	case "$(basename "$d")" in *-snapshot|*-preview|*-preview-next) continue ;; esac
	suites="$suites $(basename "$d")"
done
suites=${suites# }

{
	html_head "Xymon APT packages"
	cat <<EOF
<p>Packages of <a href="https://github.com/xymon-monitoring/xymon">Xymon</a>
for Debian and Ubuntu: an unofficial rebuild of
<a href="https://tracker.debian.org/pkg/xymon">Debian's own xymon package</a>
for releases that do not carry that version. Packaging lives in
<a href="https://github.com/xymon-monitoring/xymon-apt">xymon-apt</a>.</p>

<p><strong>&#9888;&#65039; Highly experimental.</strong> This packaging is
new and has seen no production use; versioning, suites and repository
structure may still change without notice. Do not point production
machines at it yet.</p>

<h2>Install</h2>
<pre>curl -fsSLo /etc/apt/sources.list.d/xymon.sources \\
  $base/\$(. /etc/os-release; echo \$VERSION_CODENAME)/xymon.sources
apt update
apt install xymon          # server (pulls in xymon-client)
apt install xymon-client   # client only</pre>
<p>The file names the repository and carries the signing key, which then
vouches for this repository alone.</p>

<h2 id="suites">Suites</h2>
<table>
EOF
	for s in $suites; do
		printf '  <tr><td><a href="dists/%s/">%s</a></td><td><a href="%s/xymon.sources">xymon.sources</a></td><td><a href="pool/%s/">packages</a></td></tr>\n' \
			"$s" "$s" "$s" "$s"
	done
	cat <<EOF
</table>
<p>One suite per release, component <code>main</code>. Every published
version stays available; <code>apt list -a xymon</code> shows them.</p>

<h2 id="channels">Channels</h2>
<p>Each release also has three pre-release suites, named as
<a href="https://github.com/xymon-monitoring/xymon-rpm">xymon-rpm</a> names
its channels: <code>&lt;release&gt;-snapshot</code>,
<code>&lt;release&gt;-preview</code> and
<code>&lt;release&gt;-preview-next</code>. <strong>They are empty
today</strong>: nothing is built into them yet. <code>xymon.sources</code>
says how to enable one.</p>

<h2>Signing</h2>
<p>The repository metadata is signed. Verify the
<a href="xymon-archive-keyring.asc">public key</a> against this fingerprint,
which is also published in the
<a href="https://github.com/xymon-monitoring/xymon-apt#install">repository README</a>
&mdash; a fingerprint served only from here would prove nothing.</p>
<pre>${fpr:-see the repository README}</pre>
EOF
} > "$repodir/index.html"

echo "index pages written"
