# The build pipeline

One workflow, `.github/workflows/build.yml`, builds every target, gates on the
tests, and publishes. It builds two lines: **stable**, the rebuild of Debian's
package, and **pre**, the same packaging on an upstream tree (README
*Channels*). It runs on:

- every push and pull request that changes more than documentation: both
  lines, so a change is tested against the snapshot source too;
- a nightly cron, `17 0 * * *`: both lines. For the snapshot it is the build;
  for both it is the drift detector, of upstream against Debian's packaging
  and of the distributions against the install;
- manual dispatch. With `xymon_ref` empty it builds the stable line alone;
  with `main`, a branch or sha of xymon, or `preview-X.Y.Z-N`, the pre-release
  line alone from that source.

The nightly `previews.yml` (`47 1 * * *`) dispatches it too: for each
xymon-experimental milestone with no `rel-<milestone>` tag in xymon, its
newest published preview, unless the archive already holds it. A failed build
is dispatched again the next day, as the archive records successes alone.

`attribution.yml` is separate: a credit line says nothing about whether the
packages are good, so it does not stand between a tested build and its signing.

## The job graph

```
plan                                (which lines this run builds)
lint                                (no container; publish waits on it too)

deb (matrix: stable, pre × bookworm, trixie, noble × amd64, arm64)
 └─ systemd (trixie-amd64, per line) ── publish ── pages
```

`lint` runs `shellcheck -S error` over every shell script this repository
owns, found by shebang. `publish` waits on it for the sake of
`build/publish.sh`, not the packages: `sh` executes a file as it reads it, so a
syntax error half way down signs and copies part of a tree before it stops.

`systemd` runs outside the matrix because it needs PID 1. One target is enough:
the units are Debian's and the same on every release.

Every job stops after 30 minutes. The slowest takes about 10; GitHub's own
limit is 6 hours, which is how long a hung mirror could hold a job.

## What the `deb` job does, per target

Each step is a fresh container of the release, so no test can pass on what an
earlier one installed.

0. **fetch the upstream source**, pre-release line only —
   `build/prepare-source.sh` on the runner: clone xymon, check out the ref (a
   preview tag comes from xymon-experimental), export it with `git archive`
   and name the build: the upstream half of the version from the commit, the
   packaging half from the last commit here that touched `build/`,
   `backport/`, `prerelease/`, `source.dsc.sha256` or `.github/`.
1. **build** — `build/build-deb.sh`: fetch the `.dsc` pinned in
   `source.dsc.sha256` from the Debian archive, verify it and the files it
   lists, apply `backport/all/*.patch` then `backport/<codename>/*.patch`, set
   the version, install the build dependencies and run `dpkg-buildpackage`.
   Debian's own test suite runs as part of that build. For a pre-release the
   tree is the upstream export with Debian's `debian/` put in place of
   upstream's own, and `prerelease/` is applied before `backport/`.
2. **test** — `vercmp`, `packages`, `publish`, `install` fresh, `install`
   upgrade ([testing.md](testing.md)).
3. **upload artifacts** — `pub-<codename>-<arch>` for the stable line,
   `pre-<codename>-<arch>` for the pre-release one: the two packages, without
   their `dbgsym`.

## Publishing

The `publish` job never runs from a pull request, and only from `main`. It
publishes one line per run:

- **stable**, for a dispatch with `xymon_ref` empty and `publish=1`. Not on a
  push or the cron: those rebuild a version that may be published already,
  and a rebuild has different bytes under the same name, which `publish.sh`
  leaves out;
- **pre-release**, for every build of xymon's `main` (the cron, a push, a
  dispatch naming `main`) and for a dispatched `preview-*` tag. The version
  names the upstream commit and the packaging commit, so a run that changes
  neither publishes nothing. A push or cron run built the stable line too;
  those packages are tests and are not downloaded.

A dispatched `preview-*` tag is refused when its xymon-experimental release
is a draft or missing. In order, the job:

1. checks out `main`'s tip, not the run's sha. A run queued behind a newer one
   would otherwise regenerate the index pages from an older tree and push them
   over it;
2. stops, green, when `GPG_PRIVATE_KEY` or `ARCHIVE_DEPLOY_KEY` is not
   configured (a fork): build and test, publish nothing;
3. imports the signing key and refuses to go on unless it is the key the
   `fingerprint` file names. The generated `xymon.sources` embeds the public
   key committed here, so signing with another would publish a repository
   every host refuses;
4. downloads the `pub-*` or the `pre-*` artifacts and clones the published
   tree from
   `xymon-monitoring/xymon-apt-archive`;
5. runs `build/publish.sh`, which files each package by its version, into
   `pool/<codename>/`, `-snapshot` or `-preview`, never replacing one; prunes
   the pre-release suites and rebuilds `-preview-next`; then rebuilds and
   signs each suite's indexes. The job
   then adds the key, one `xymon.sources` per suite and the index pages;
6. replaces the archive's `main` with one orphan commit, force-pushed, then
   uploads the tree as the Pages artifact.

A `concurrency` group serialises overlapping runs, so two publishes cannot race
the push.

**Every published stable version stays.** A rebuild (`releasenum` 2) is added
beside the one it supersedes, and a suite whose target has left the matrix
keeps being served as it was. The pre-release suites are pruned (README
*Retention*).

**The pre-release suites always exist.** For every stable suite, `publish.sh`
writes `<codename>-snapshot`, `-preview` and `-preview-next` even when one
holds no package: a signed `Release` over an empty `Packages`. `xymon.sources`
names them, and a host that added one must not get a failed `apt update` on
the day its last preview is pruned: a suite with no `Release` file is an
error, an empty one finds nothing. They get no `xymon.sources` of their own.

### The archive

The published tree lives in `xymon-monitoring/xymon-apt-archive`, as
xymon-rpm's does in `xymon-rpm-archive`, and for the same reasons
([its build-pipeline.md](https://github.com/xymon-monitoring/xymon-rpm/blob/main/docs/build-pipeline.md),
*The archive*): a clone of the packaging fetches no packages, and the tree has
a copy a person can check out and restore. It serves nothing: the publish job
clones it, and Pages serves the artifact the job uploads.

The clone has no fallback that starts empty. The archive is seeded
([signing.md](signing.md) *Maintainer setup*), so a failed clone is a failure;
publishing on top of nothing would serve one run's packages and drop every
earlier version.

The archive is pushed before the Pages artifact is uploaded, on purpose. If a
deployment fails, the tree is already saved and the next publish resumes from
it. Reversed, a failed push would leave the site ahead of the state store, and
the next publish would unpublish packages.

### Serving the tree

The deploy is its own `pages` job, because the `github-pages` environment can
refuse a deployment, and a refusal blocks a whole job rather than a step. Two
repository settings govern it: the Pages source must be GitHub Actions, and
the `github-pages` environment's deployment branch policy must allow `main`.
If either is changed back, the symptom is a failing `pages` job and a site
that stops being updated.
