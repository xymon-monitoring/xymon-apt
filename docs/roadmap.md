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
- **A release before Debian uploads it** is built from upstream's tag.
  *Decided 2026-11-25.* The stable suite would otherwise wait for Debian's
  upload and a checksum set here by hand, with preview hosts on the last
  preview meanwhile. README *Channels* has what is published and how it
  yields to Debian's package. Two things follow from it and are not done:
  - **the first one has not been built.** The path is the snapshot's, with
    another version; no `rel-*` tag exists that `prerelease/` fits, so the
    first real run is 4.3.32's. If it fails, `previews` dispatches it again
    each night: fix `prerelease/` as for a red nightly.
  - **the tarball is not checked against the release's `.sha256`**, as
    xymon-rpm does. The packages are built from the tag's tree, by
    `git archive`, and ship no source tarball; the check would tie a build
    to the published release rather than to the tag alone.
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
  Two today: `tests/web/showgraph-rrd-error-exit.sh`, until xymon#1024 is in
  `main` and in the newest preview, and
  `tests/server/serverconfig-local-client.sh`, until a preview newer than
  `preview-4.3.32-5`.
- **Drop the fallback for the client's tmp and log directories** in
  `prerelease/10-rules.patch` once xymon#906 is merged and every published
  preview has it ([prerelease/README.md](../prerelease/README.md) has the
  two cases). Debian's `12_hobbitvars.patch` can lose its two
  `xymonclient.cfg` paths at the same point, by setting
  `INSTALLCLIENTTMPDIR` and `INSTALLCLIENTLOGDIR`: worth telling its
  maintainers, who asked for it in xymon#904.
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
