# The build pipeline

One workflow, `.github/workflows/build.yml`, builds every target, gates on the
tests, and publishes on request. It runs on:

- every push and pull request that changes more than documentation;
- a weekly cron, which catches a distribution update that breaks the build or
  the install. Weekly rather than nightly as in xymon-rpm, because the source
  is a pinned Debian upload, not a moving branch;
- manual dispatch, which is also the only way to publish.

`attribution.yml` is separate: a credit line says nothing about whether the
packages are good, so it does not stand between a tested build and its signing.

## The job graph

```
lint                                (no container; publish waits on it too)

deb (matrix: bookworm, trixie, noble × amd64, arm64)
 └─ systemd (trixie-amd64) ── publish ── pages   (dispatch with publish=1, from main)
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

1. **build** — `build/build-deb.sh`: fetch the `.dsc` pinned in
   `source.dsc.sha256` from the Debian archive, verify it and the files it
   lists, apply `backport/all/*.patch` then `backport/<codename>/*.patch`, set
   the version, install the build dependencies and run `dpkg-buildpackage`.
   Debian's own test suite runs as part of that build.
2. **test** — `vercmp`, `packages`, `publish`, `install` fresh, `install`
   upgrade ([testing.md](testing.md)).
3. **upload artifacts** — `pub-<codename>-<arch>`: the two packages, without
   their `dbgsym`.

## Publishing

The `publish` job runs only for a dispatch from `main` with `publish=1`. Not on
a push or the cron: those rebuild a version that may be published already, and
a rebuild has different bytes under the same name, which `publish.sh` leaves
out. In order, the job:

1. checks out `main`'s tip, not the run's sha. A run queued behind a newer one
   would otherwise regenerate the index pages from an older tree and push them
   over it;
2. stops, green, when `GPG_PRIVATE_KEY` or `ARCHIVE_DEPLOY_KEY` is not
   configured (a fork): build and test, publish nothing;
3. imports the signing key and refuses to go on unless it is the key the
   `fingerprint` file names. The generated `xymon.sources` embeds the public
   key committed here, so signing with another would publish a repository
   every host refuses;
4. downloads every `pub-*` artifact and clones the published tree from
   `xymon-monitoring/xymon-apt-archive`;
5. runs `build/publish.sh`, which adds the packages to `pool/<codename>/`,
   never replacing one, then rebuilds and signs each suite's indexes. The job
   then adds the key, one `xymon.sources` per suite and the index pages;
6. replaces the archive's `main` with one orphan commit, force-pushed, then
   uploads the tree as the Pages artifact.

A `concurrency` group serialises overlapping runs, so two publishes cannot race
the push.

**Every published version stays.** A rebuild (`releasenum` 2) is added beside
the one it supersedes, and a suite whose target has left the matrix keeps
being served as it was. Nothing is pruned.

**The pre-release channels are published empty.** For every stable suite,
`publish.sh` also writes `<codename>-snapshot`, `-preview` and
`-preview-next`: a signed `Release` over an empty `Packages`. Nothing builds
into them yet (README *Channels*). They exist so that the `xymon.sources` a
host fetched today, which names them, keeps working unchanged when they fill:
a suite with no `Release` file fails `apt update` on this repository, an
empty one finds nothing. They get no `xymon.sources` of their own.

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
