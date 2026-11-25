# The regression tests

The suites live in `tests/`, and each header says what it asserts and why.
This file is the shape: which suite runs where, and how to run one yourself.
The design is a net from cheap to expensive: a break should fail at the
cheapest suite that can see it.

## Layered from cheap to expensive

| Suite | Reads / needs | Runs in |
| --- | --- | --- |
| `vercmp.sh` | version strings, and the built version | every `deb` build |
| `packages.sh` | the packages, uninstalled | every `deb` build |
| `publish.sh` | a throwaway tree and key; `apt` against it | every `deb` build |
| `install.sh fresh` | installs into the container, starts a server | every `deb` build |
| `install.sh upgrade` | the distribution's own xymon, then this one | every `deb` build |
| `systemd.sh` | a real PID 1 | `systemd` job, trixie-amd64 |
| `attribution.sh` | one text file | `attribution.yml`: pull requests, pushes to `main` |

Debian's own test suite also runs in every build, inside `dpkg-buildpackage`.

## What each is for

- **`vercmp.sh`** pins the ordering in README *Versions and the official
  packages*. A wrong version fails no build: it keeps a host on this rebuild
  after Debian ships the same version, or leaves a security rebuild below the
  package it should replace.
- **`packages.sh`** checks the packages are still Debian's two, with one
  version, the right architecture, Debian's maintainer and both units.
- **`publish.sh`** is the only place `build/publish.sh` and
  `build/mksources.sh` run before they meet the real tree, since the `publish`
  job never runs from a pull request. It asserts that a published version is
  never overwritten, that a rebuild lands beside the version it supersedes,
  that a suite with nothing new stays served and signed, and that `apt`
  accepts the result through the generated `xymon.sources` and refuses it
  under another key.
- **`install.sh`** is the only suite that checks the thing *monitors*: it
  starts the server and waits until its own client's data is analysed into
  `cpu`, `disk`, `memory` and `procs`. In `upgrade` mode it starts from the
  distribution's official xymon, which is the compatibility promise this
  repository makes.
- **`systemd.sh`** runs under a real init, the only place the maintainer
  scripts' `systemctl` calls do anything: the client alone runs
  `xymon-client.service`, and on a server that unit is skipped so the host
  does not report twice.

## What nothing covers

- The workflow's own publish steps: the archive clone, the push, the Pages
  upload. `tests/publish.sh` covers the two scripts they call.
- An upgrade from one published rebuild to the next, and a release upgrade
  (bookworm to trixie) with these packages installed. `vercmp.sh` asserts the
  versions order; nothing installs them in sequence.
- A booted host: the matrix is containers.

## Running one locally

Each suite is a self-contained script over the built packages. Build first
(README *Build locally*), then run a suite in a container of the same release:

```sh
docker run --rm -v "$PWD:/w:ro" debian:trixie /w/tests/packages.sh /w/out
docker run --rm -v "$PWD:/w:ro" debian:trixie /w/tests/publish.sh /w/out
```

`publish.sh` and `install.sh` run as root and change the container (packages,
a file in `/etc/apt/sources.list.d`), so use a throwaway one. `systemd.sh`
wants a real init; the `systemd` job in `build.yml` has a container recipe
that works outside CI too.
