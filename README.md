# xymon-apt

APT repository for [Xymon](https://github.com/xymon-monitoring/xymon) 4.3.31:
**server** (`xymon`) and **client** (`xymon-client`), for Debian 12 `bookworm`,
Debian 13 `trixie` and Ubuntu 24.04 `noble`, on `amd64` and `arm64`. The
Debian/Ubuntu counterpart of
[xymon-rpm](https://github.com/xymon-monitoring/xymon-rpm).

> [!WARNING]
> **Experimental.** Layout and repository structure may change.

## What it ships

An **unofficial backport of Debian's own package**: Debian's `xymon 4.3.31-1`
source (uploaded to unstable on 2026-11-07 by its Debian maintainers), rebuilt
for each release. Nothing is repackaged here:

- `source.dsc.sha256` pins Debian's `.dsc`. `build-deb.sh` fetches it from the
  Debian archive, and `dpkg-source` verifies every file it lists.
- `backport/` holds the only local changes (see `backport/README.md`):
  - **trixie**: none. Built exactly as Debian ships it; debhelper 14 comes
    from trixie-backports.
  - **bookworm, noble**: one patch for their older toolchain: debhelper compat
    14 → 13 (plus the `systemd-sysusers` dependency debhelper 14 would add),
    sysusers `u!` → `u` (systemd < 257), ImageMagick 6, and two upstream
    test-suite workarounds. Files and maintainer scripts are otherwise Debian's.
  - **all**: empty. A security fix Debian has not shipped yet goes here.

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
with no downgrade: same packaging, same files. `tests/install.sh` checks the
backport ordering on every build.

## Install

```sh
sudo curl -fsSLo /usr/share/keyrings/xymon-archive-keyring.gpg \
  https://xymon-monitoring.github.io/xymon-apt/xymon-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/xymon-archive-keyring.gpg] \
https://xymon-monitoring.github.io/xymon-apt $(. /etc/os-release; echo $VERSION_CODENAME) main" \
  | sudo tee /etc/apt/sources.list.d/xymon.list
sudo apt update
sudo apt install xymon          # server (pulls in xymon-client)
sudo apt install xymon-client   # client only
```

The key is xymon-rpm's: check
`gpg --show-keys /usr/share/keyrings/xymon-archive-keyring.gpg` shows
`BD24 FB87 154D 561B 66F6  66DF 639D E923 AA08 904A`.

## How it is built

`.github/workflows/build.yml` follows xymon-rpm's pipeline:

```
lint (shellcheck)
deb (bookworm/trixie/noble × amd64/arm64)
  build-deb.sh                 Debian's .dsc + backport/ → .debs (Debian's test suite runs)
  tests/install.sh fresh       server monitors itself (cpu/disk/memory/procs)
  tests/install.sh upgrade     from the distro's official xymon
 └─ systemd (trixie)           tests/systemd.sh: units, client skipped on a server
     └─ publish ── pages       manual dispatch with publish=1 only
```

Push, pull request and a weekly cron build and test without publishing. A
published version is never overwritten: after a `backport/` change, re-dispatch
with `releasenum` bumped. Each publish replaces the whole site.

**New Debian upload** (e.g. `4.3.31-2`): update `source.dsc.sha256`, re-check
`backport/`, reset `releasenum` to 1.

## Maintainer setup (once)

1. Secret `GPG_PRIVATE_KEY`: the same key as xymon-rpm (see its
   `docs/signing.md`). Without it CI builds and tests, and publishes nothing.
2. Settings → Pages → Source: **GitHub Actions**. The `github-pages`
   environment must allow `main`.

## Build locally

```sh
docker run --rm -v "$PWD:/w" debian:trixie /w/build-deb.sh /w/out
docker run --rm -v "$PWD:/w:ro" debian:trixie /w/tests/install.sh /w/out upgrade
```
