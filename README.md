# Xymon APT packages

APT repository for [Xymon](https://github.com/xymon-monitoring/xymon) 4.3.31:
**server** (`xymon`) and **client** (`xymon-client`), for Debian 12 `bookworm`,
Debian 13 `trixie` and Ubuntu 24.04 `noble`, on `amd64` and `arm64`. The
Debian/Ubuntu counterpart of
[xymon-rpm](https://github.com/xymon-monitoring/xymon-rpm), built and
published the same way.

> [!WARNING]
> **Experimental.** Layout and repository structure may change.

## What it ships

An **unofficial backport of Debian's own package**: Debian's `xymon 4.3.31-1`
source (uploaded to unstable on 2026-11-07 by its Debian maintainers), rebuilt
for each release. Nothing is repackaged here, which is the one place this
repository differs from xymon-rpm by design: Debian already packages Xymon,
so the work is carrying that package to releases that lack this version.

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

## Layout

```
source.dsc.sha256   the Debian source package that is rebuilt, pinned
backport/           the only changes made to it, per release
build/              build-deb.sh builds a target; publish.sh folds packages into
                    the published tree and signs it; mksources.sh and mkindex.sh
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

Once Debian ships 4.3.31 for a release (backports or archive), `apt` moves to it
with no downgrade: same packaging, same files. `tests/vercmp.sh` asserts the
whole table on every build.

A published version is immutable. A change in `backport/` ships by dispatching
the build with `releasenum` bumped, giving `+2`; `releasenum` goes back to 1
with a new Debian version.

## Retention

Everything published stays: people pin versions and roll back. A rebuild is
added beside the version it supersedes, and `apt list -a xymon` shows both. A
suite whose target is retired keeps being served as it was. There is one line
of packages here, no snapshots, so nothing is pruned.

## Testing

How the suites are layered and how to run one is in
[docs/testing.md](docs/testing.md); the full pipeline is in
[docs/build-pipeline.md](docs/build-pipeline.md).

| | |
| --- | --- |
| `vercmp.sh` | the version ordering above, and that the built version follows the scheme |
| `packages.sh` | the two packages, one version, the right architecture, Debian's maintainer, both units |
| `publish.sh` | publishes into a temporary tree with a throwaway key: a version never overwritten, a rebuild beside the one it supersedes, a suite with nothing new still served, `apt` accepting the result through the generated `xymon.sources` and refusing it under another key |
| `install.sh` | fresh, then as an upgrade from the distribution's official xymon: the server starts and analyses its own client into `cpu`, `disk`, `memory` and `procs` |
| `systemd.sh` | under a real init: the client alone runs its unit, and on a server that unit is skipped so the host does not report twice |

Debian's own test suite runs inside every build as well.

## How it is built

`.github/workflows/build.yml` follows xymon-rpm's pipeline:

```
lint (shellcheck)
deb (bookworm/trixie/noble × amd64/arm64)   build, then the suites above
 └─ systemd (trixie)
     └─ publish ── pages                    manual dispatch with publish=1 only
```

Push, pull request and a weekly cron build and test without publishing.
Publishing is a dispatch of **build** from `main` with `publish=1`: the
packages are added to the published tree, which lives in
`xymon-monitoring/xymon-apt-archive`, and the tree is deployed to Pages. What
a maintainer sets up once is in [docs/signing.md](docs/signing.md) *Maintainer
setup*.

**New Debian upload** (e.g. `4.3.31-2`): update `source.dsc.sha256`, re-check
`backport/`, reset `releasenum` to 1.

## Build locally

```sh
docker run --rm -v "$PWD:/w" debian:trixie /w/build/build-deb.sh /w/out
docker run --rm -v "$PWD:/w:ro" debian:trixie /w/tests/install.sh /w/out upgrade
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
  `backport/` modify, keeps the terms in its `debian/copyright`.
