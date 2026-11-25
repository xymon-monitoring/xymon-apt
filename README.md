# Xymon APT packages

APT repository for [Xymon](https://github.com/xymon-monitoring/xymon) 4.3.31:
**server** (`xymon`) and **client** (`xymon-client`), for Debian 12 `bookworm`,
Debian 13 `trixie` and Ubuntu 24.04 `noble`, on `amd64` and `arm64`. The
Debian/Ubuntu counterpart of
[xymon-rpm](https://github.com/xymon-monitoring/xymon-rpm), built and
published the same way.

> [!WARNING]
> **Highly experimental.** New packaging with no production use. Package
> versioning, suites and repository structure may still change without
> notice — do not point production machines at it yet.

## What it ships

An **unofficial backport of Debian's own package**: Debian's `xymon 4.3.31-1`
source (uploaded to unstable on 2026-11-07 by its Debian maintainers), rebuilt
for each release. Nothing is repackaged here, which is the one place this
repository differs from xymon-rpm by design: Debian already packages Xymon,
so the work is carrying that package to releases that lack this version.
That is the stable suite for a version Debian has packaged. For a release
Debian has not packaged yet, and for the pre-release suites, the same
packaging is put on the upstream tree (*Channels*).

- `source.dsc.sha256` pins Debian's `.dsc`. `build/build-deb.sh` fetches it
  from the Debian archive, and `dpkg-source` verifies every file it lists.
- `backport/` holds the only local changes (see
  [backport/README.md](backport/README.md)):
  - **trixie**: none. Built exactly as Debian ships it; debhelper 14 comes
    from trixie-backports.
  - **bookworm, noble**: one patch for their older toolchain: debhelper compat
    14 → 13 (plus the `systemd-sysusers` dependency debhelper 14 would add),
    sysusers `u!` → `u` (systemd < 257), ImageMagick 6, and two upstream
    test-suite workarounds. Files and maintainer scripts are otherwise Debian's.
  - **all**: empty. A security fix Debian has not shipped yet goes here.

## Install

```sh
sudo curl -fsSLo /etc/apt/sources.list.d/xymon.sources \
  "https://xymon-monitoring.github.io/xymon-apt/$(. /etc/os-release; echo "$VERSION_CODENAME")/xymon.sources"
sudo apt update
sudo apt install xymon          # server (pulls in xymon-client)
sudo apt install xymon-client   # client only
```

That one file names the repository and carries the signing key, which then
vouches for this repository alone. Verify the key against this fingerprint
(see [docs/signing.md](docs/signing.md)); it is xymon-rpm's:

```
Xymon Project (RPM signing key)
BD24 FB87 154D 561B 66F6  66DF 639D E923 AA08 904A
```

The file names one release. After a release upgrade (bookworm to trixie),
fetch it again.

## Targets

| Target | Container | Local changes |
| --- | --- | --- |
| `bookworm` | `debian:bookworm` | `backport/bookworm/` |
| `trixie` | `debian:trixie` | none |
| `noble` | `ubuntu:noble` | `backport/bookworm/`, shared |

Each on `amd64` and `arm64`, built natively. Images are pinned by codename so
a moving tag cannot move a published suite. The repository has one suite per
codename, component `main`.

## Channels

Four suites per release, as xymon-rpm has four channels. `xymon.sources`
enables the first; the others are added by hand, per host.

| Suite | Built from | Version, e.g. |
| --- | --- | --- |
| `<codename>` | Debian's package of a release | `4.3.31-1~~xymon13+1` |
| `<codename>-snapshot` | upstream `main`, nightly | `4.3.32~git202611250108.dc9c799-0~~xymon13+…` |
| `<codename>-preview` | a xymon-experimental preview: the 2 newest of every unreleased milestone | `4.3.32~preview5-0~~xymon13+…` |
| `<codename>-preview-next` | the previews of the next release alone — **the usual choice** | the same |

A **snapshot** is a pre-release of the next version, with no release testing.
A **preview** is a test build of an upcoming release: xymon's `main` plus the
open pull requests of that milestone and of the unreleased ones before it,
most not reviewed yet;
[xymon-experimental](https://github.com/xymon-monitoring/xymon-experimental/releases)
publishes one once its test lanes pass. Both are for testing, not production.

To follow one, add its suite in `/etc/apt/sources.list.d/xymon.sources`:

```
Suites: trixie trixie-preview-next
```

Add **one**, and not a snapshot together with a preview: they are different
lines of code, and `apt` would install whichever sorts higher. Remove the
suite to stop following it; the packages already installed stay until the
release of their version, which outranks them.

**What a pre-release is built with.** Not a Debian package of that version,
which does not exist yet: Debian's packaging of 4.3.31, from the same pinned
`.dsc`, on the upstream tree. Where that packaging does not fit the newer
upstream, [`prerelease/`](prerelease/README.md) carries the difference: today
two of Debian's patches rebased, a few changes to `debian/rules`, and install and docs lists without the upgrade files upstream removed. So a
pre-release is this repository's reading of what Debian's package of the next
version will be, and upgrades to it when it arrives.

**A release Debian has not packaged yet** is built the same way, from
xymon's `rel-X.Y.Z` tag, and goes to the stable suite as
`X.Y.Z-0~~xymon<VERSION_ID>+…`, the night the tag is seen. It sorts above
every snapshot and preview of X.Y.Z, whose hosts move onto it, and below
Debian's `X.Y.Z-1`. When Debian uploads that and `source.dsc.sha256` is set
to it, the stable suite gets Debian's package rebuilt, as for 4.3.31, and
`apt` moves on to it. Between the two, the stable suite holds this
repository's reading of the packaging, not a package Debian made.

## Layout

```
source.dsc.sha256   the Debian source package that is rebuilt, pinned
backport/           the only changes made to it, per release
prerelease/         what Debian's packaging needs to build a newer upstream
build/              build-deb.sh builds a target, prepare-source.sh fetches an
                    upstream tree for it; publish.sh folds packages into the
                    published tree and signs it; mksources.sh and mkindex.sh
                    generate xymon.sources and the index pages
docs/               build-pipeline, testing, signing, roadmap
tests/              see Testing
xymon-archive-keyring.asc, fingerprint   the public signing key
```

## Versions and the official packages

`4.3.31-1~~xymon<VERSION_ID>+<n>`, e.g. `4.3.31-1~~xymon13+1`.

| Lower | | Higher | |
| --- | --- | --- | --- |
| distro `4.3.30-x` | < | `4.3.31-1~~xymon13+1` | installs as an upgrade |
| `4.3.31-1~~xymon13+1` | < | `4.3.31-1~~xymon13+2` | our rebuild, e.g. a CVE fix |
| `4.3.31-1~~xymon12+9` | < | `4.3.31-1~~xymon13+1` | dist-upgrade 12 → 13 |
| `4.3.31-1~~xymon13+9` | < | `4.3.31-1~bpo13+1` | official [backport](https://backports.debian.org/) wins |
| `4.3.31-1~~xymon13+9` | < | `4.3.31-1`, `4.3.31-1+deb13u1` | official Debian wins |
| `4.3.32~git…`, `4.3.32~preview5…` | < | `4.3.32-0~~xymon13+…` | a release built from upstream's tag ends its pre-releases |
| `4.3.32-0~~xymon13+…` | < | `4.3.32-1~~xymon13+1`, `4.3.32-1` | Debian's package of it wins, rebuilt here or official |

Once Debian ships 4.3.31 for a release (backports or archive), `apt` moves to it
with no downgrade: same packaging, same files. `tests/vercmp.sh` asserts the
whole table on every build.

A published version is immutable. A change in `backport/` ships by dispatching
the build with `releasenum` bumped, giving `+2`; `releasenum` goes back to 1
with a new Debian version.

## Retention

The stable suites keep everything: people pin versions and roll back. A
rebuild is added beside the version it supersedes, and `apt list -a xymon`
shows both. A suite whose target is retired keeps being served as it was.

The pre-release suites are pruned, by xymon-rpm's rules. A snapshot suite
keeps the newest **10 upstream commits**, and of each only its newest
packaging rebuild. A preview suite keeps the newest **2 previews** of each
unreleased milestone; a milestone's previews go once its release is in the
stable suite, and `-preview-next` is rebuilt from what is left on every
publish. Pruning removes whole builds, server and client together, and the
publish log names each one.

## Testing

How the suites are layered and how to run one is in
[docs/testing.md](docs/testing.md); the full pipeline is in
[docs/build-pipeline.md](docs/build-pipeline.md).

| | |
| --- | --- |
| `vercmp.sh` | the version ordering above, snapshots and previews included, and that the built version follows the scheme |
| `packages.sh` | the two packages, one version, the right architecture, Debian's maintainer, both units |
| `publish.sh` | publishes into a temporary tree with a throwaway key: a version never overwritten, a rebuild beside the one it supersedes, a suite with nothing new still served, `apt` accepting the result through the generated `xymon.sources` and refusing it under another key; snapshots and previews each in their suite, both retentions dropping whole builds, `-preview-next` moving on after a release, the channels served even when empty |
| `install.sh` | fresh, then as an upgrade from the distribution's official xymon: the server starts and analyses its own client into `cpu`, `disk`, `memory` and `procs` |
| `systemd.sh` | under a real init: the client alone runs its unit, and on a server that unit is skipped so the host does not report twice |

Debian's own test suite runs inside every build as well.

## How it is built

`.github/workflows/build.yml` follows xymon-rpm's pipeline:

```
lint (shellcheck)
deb (bookworm/trixie/noble × amd64/arm64, × stable/pre-release)   build, then the suites above
 └─ systemd (trixie)
     └─ publish ── pages
```

Push, pull request and the nightly cron build both lines. What publishes:

- **stable**: a dispatch of **build** from `main` with `publish=1`, and
  nothing else;
- **snapshot**: every build of xymon's `main` from this repository's `main` —
  the nightly, a push, a dispatch with `xymon_ref=main`. A build that changes
  neither the upstream commit nor the packaging brings nothing new;
- **preview**: a dispatch with `xymon_ref=preview-X.Y.Z-N`, which the nightly
  **previews** workflow sends for each new published preview;
- **a release from upstream's tag**: a dispatch with `xymon_ref=rel-X.Y.Z`,
  which the same workflow sends once xymon has the tag, until the stable
  suites hold that version.

A dispatch of any other ref, a branch, a sha or a pull request of xymon
(`pr/NNN`), builds artifacts
only. The published tree lives in `xymon-monitoring/xymon-apt-archive` and is
deployed to Pages. What a maintainer sets up once is in
[docs/signing.md](docs/signing.md) *Maintainer setup*.

**New Debian upload** (e.g. `4.3.31-2`): update `source.dsc.sha256`, re-check
`backport/` and `prerelease/`, reset `releasenum` to 1.

## Build locally

```sh
docker run --rm -v "$PWD:/w" debian:trixie /w/build/build-deb.sh /w/out
docker run --rm -v "$PWD:/w:ro" debian:trixie /w/tests/install.sh /w/out upgrade
```

A snapshot of `main`, or a preview:

```sh
./build/prepare-source.sh main upstream-src      # or preview-4.3.32-5, or pr/906
docker run --rm -v "$PWD:/w" debian:trixie /w/build/build-deb.sh /w/out 1 /w/upstream-src
```

## Contributing

Changes go through a pull request. The rules are in
[CONTRIBUTING.md](CONTRIBUTING.md). It first settles which repository a change
belongs in, since this one is not always the answer: most changes to the
package itself belong in Debian. [AGENTS.md](AGENTS.md) adds what a coding
agent needs on top of those, and `CLAUDE.md` imports it for Claude Code.
What is undecided or not built yet is in [docs/roadmap.md](docs/roadmap.md).

## License

This repository's own work — the build, publish and test scripts, the
workflows and the documentation — is GPL-2.0-or-later. The `LICENSE` file is
the GPL version 2 text that applies.

Two things keep their own terms:

- **Xymon itself**, which the packages contain, is GPL version 2 with an
  explicit exemption for linking with OpenSSL, and includes a few files under
  BSD-like terms or in the public domain; its `README` and `COPYING` say which.
- **Debian's packaging**, which is rebuilt and which the patches in
  `backport/` and `prerelease/` modify or rebase, keeps the terms in its
  `debian/copyright`.
