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
- **Snapshot and preview channels like xymon-rpm.** Wanted, not built yet.
  What is in place so they can be added without touching a host: the suites
  `<codename>-snapshot`, `-preview` and `-preview-next` are published empty,
  `xymon.sources` names them, and `tests/vercmp.sh` pins that `X.Y.Z~…` sorts
  between the current version and the rebuild of `X.Y.Z`. What is left:
  - **the source.** Debian's `debian/` on top of upstream `main` or a
    xymon-experimental preview, instead of a pinned `.dsc`. Debian's patches
    may not apply there, so this is where the rule "nothing is repackaged"
    meets its limit: decide what carries the difference.
  - **the version**, in full. Only the `~` after the upstream version is
    settled. xymon-rpm's has an upstream half and a packaging half, so a
    packaging-only change republishes; the same is needed here.
  - **filing by version** in `build/publish.sh`, which today files by the
    artifact's name alone, and **a retention** per channel: the stable rule,
    keep everything, does not fit a nightly build.
  - **`-preview-next`** rebuilt from `-preview` on every publish, as there.
  - **the triggers**: a nightly build of `main`, and xymon-rpm's
    `previews.yml` for published previews.
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
