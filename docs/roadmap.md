# Roadmap

Decisions to make, and packaging work nothing else tracks. Keep it short;
move anything actionable to a GitHub issue.

## Before the first publish

[signing.md](signing.md) *Maintainer setup* has the four steps: the two
secrets, the seeded archive repository, and Pages.

## Decisions

- **Retire trixie.** Debian ships `4.3.31-1~bpo13+1` in trixie-backports, so
  the trixie target rebuilds what a trixie host can install officially. The
  README's own rule is to retire a target once its official backport exists.
  Retiring means dropping it from the matrix and saying where to go instead;
  a suite already published stays served. Decide before the first publish:
  a suite never published has nobody to move.
- **bookworm and noble through official channels.** Ask the Debian
  maintainers (Roland Rosenfeld, Axel Beckert) about
  `bookworm-backports-sloppy`, offering the delta in `backport/bookworm/` as a
  starting point. Ubuntu has no equivalent path for noble short of a PPA.
- **Review policy for this repo.** `main` is unprotected, as in xymon-rpm,
  whose [roadmap](https://github.com/xymon-monitoring/xymon-rpm/blob/main/docs/roadmap.md)
  weighs the options. Decide the two together.
- **A release before Debian uploads it.** When xymon tags `rel-X.Y.Z`, its
  previews stop, and the stable suite gets X.Y.Z only once Debian uploads it
  and `source.dsc.sha256` is bumped by hand. Until then a preview host stays
  on the last preview and a stable host on the previous version. xymon-rpm
  builds the tag the same night. The counterpart here would be the pre-release
  recipe on the tag, as `X.Y.Z-0~~xymon…`, which sorts below Debian's
  `X.Y.Z-1` and so yields to it. It would also put this repository's reading
  of the packaging (`prerelease/`) in the stable suite, which today holds
  Debian's package and nothing else. Decide when 4.3.32 is close.
- **A keyring package**, the counterpart of xymon-rpm's `xymon-release`: a
  small `.deb` carrying the key and the sources file, so a key renewal reaches
  hosts through `apt upgrade` instead of a file fetched again by hand
  ([signing.md](signing.md) *When the key changes*). The sources file names a
  suite, so it is one package per release or a maintainer script that writes
  it.
- **Upstream's stale `debian/`** (2019) in xymon-monitoring/xymon: remove it or
  point to salsa.debian.org/debian/xymon. xymon-rpm's roadmap carries the same
  question for `rpm/`.

## Packaging work

- **`prerelease/` against a moving `main`.** Each upstream commit that touches
  a line a Debian patch touches breaks the nightly build until the patch is
  rebased ([prerelease/README.md](../prerelease/README.md)). Send upstream
  what would shrink that surface: most of `12_hobbitvars.patch` is paths that
  a configure variable could carry, as `XYMONRUNDIR` now does for pidfiles.
- **Remove `prerelease/skip-tests` lines as their upstream fixes merge.**
  One today: `tests/web/showgraph-rrd-error-exit.sh`, until xymon#1024.
- **One preview needing what `main` does not.** `prerelease/` is shared; a
  pull request in a preview that touches the same lines needs its own rebase
  and there is nowhere to put it.
- **The pre-release suites grow the Pages site.** Six targets, ten snapshots
  and a few previews each: watch the size against GitHub Pages limits, and
  lower `XYMON_SNAPSHOT_KEEP` if it comes near.

- **Source URL.** The `.dsc` is fetched from deb.debian.org's pool, falling
  back to incoming. Once Debian supersedes 4.3.31-1 it leaves the pool; add
  snapshot.debian.org as a fallback then, or bump to the new version.
- **A new Ubuntu LTS or Debian release** is a new row in the matrix and, if
  its toolchain needs it, a directory in `backport/`. Check first what xymon
  version the release carries: a target is worth building only below 4.3.31.
- **Tests the pipeline lacks** are listed in [testing.md](testing.md) *What
  nothing covers*.
- **Watch the signing key expiry**
  ([xymon-rpm's signing.md](https://github.com/xymon-monitoring/xymon-rpm/blob/main/docs/signing.md)
  *Renewing before expiry*), and follow a renewal here.
