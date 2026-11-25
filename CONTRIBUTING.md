# Contributing to the Xymon APT packaging

Patches are welcome. This file covers what is easy to get wrong because it is
not visible from the tree.

Fork, remotes and the pull-request flow are the same across the organisation
and documented once, in the wiki: start with
[first-contribution.md](https://github.com/xymon-monitoring/xymon-wiki/blob/main/docs/contributing/git/first-contribution.md);
[git-setup.md](https://github.com/xymon-monitoring/xymon-wiki/blob/main/docs/contributing/git/git-setup.md)
has the remote configuration.

How a pull request is written is the same as in xymon-rpm and is stated once,
there:
[xymon-rpm's CONTRIBUTING.md](https://github.com/xymon-monitoring/xymon-rpm/blob/main/CONTRIBUTING.md),
sections *Where a change gets written down*, *Shortening*, *Titles*,
*Descriptions* and *The last pass*. They apply here unchanged, reading "the
patch header" for "the spec comment". The title's component is a name this
tree uses: `backport:`, `build:`, `publish:`, `tests:`, `ci:`, `docs:`,
`README:`. What follows is what differs.

## Which repository

This is the first question and the one most often answered wrong, because
here four trees can look like the right place for the same fix.

**The rule: this repository rebuilds Debian's package and changes as little of
it as a release's toolchain forces.**

| what you are changing | where it goes |
|---|---|
| Xymon's behaviour, its build, what `make install` produces | `xymon-monitoring/xymon` |
| what the Debian package installs, requires, starts or migrates | Debian: <https://salsa.debian.org/debian/xymon>, or a bug against the `xymon` package |
| what an older release's toolchain cannot build of that package | here, in `backport/<codename>/` |
| a fix Debian has not uploaded yet, a security fix above all | here, in `backport/all/`, naming the Debian bug or commit that will delete it |
| how the packages are built, tested, signed and published | here |
| the old `debian/` directory inside `xymon-monitoring/xymon` | nowhere — it dates from 2019 and builds nothing anyone ships |

A change in the second row made here instead would work, and that is the
trap. The package would stop being Debian's, and the promise the README makes,
that the official package replaces this one with no downgrade and no
migration, would hold only until the first file that differs.

### A patch names what deletes it

Everything in `backport/` is interim by construction: a toolchain patch goes
when its release leaves the matrix or Debian's package no longer needs the
newer tool, and a fix in `all/` goes when Debian ships it. So **each patch
says in its header what it is for and what makes it removable**, a Debian bug
number or a commit on salsa where there is one. That header lets someone who
was not there remove it. Without it the patch is a permanent divergence
nobody will recognise as removable.

## Where to file an issue

Report where you met the problem, not where the fix belongs — telling those
apart is often the work the issue exists to do.

- It went wrong adding the repository, or installing or upgrading *these*
  packages on bookworm, trixie or noble → **here**.
- The same thing goes wrong with Debian's own package in unstable or testing
  → **Debian's bug tracker**, package `xymon`.
- It went wrong in Xymon itself, however you installed it →
  **`xymon-monitoring/xymon`**.

## Pull requests

Every change goes through a pull request. `main` here is **not** protected:
there is no ruleset and no required review, so nothing stops a direct push.
That is a gap, not a policy. Until it is closed the rule is the social one:
open a pull request, and say in it if you merged your own.

- One change per pull request. A fix and the cleanup you noticed next to it are
  two pull requests.
- Say what you verified, and how. "Built and installed on bookworm arm64" is
  useful; "should work" is not. If you could not test something, say that
  too. It is not held against you, and it tells a reviewer where to look.
- **Name the release and architecture you actually tested on.** CI builds and
  installs in containers, which have no init. That is not a booted host, and
  not a server with years of history upgraded in place, so a report from one
  is worth more than another green matrix.
- If your change fixes something a suite could have caught, adding the
  assertion is worth more than the fix. [docs/testing.md](docs/testing.md) says
  which suite it belongs in. Show that it fails without the fix, and say how;
  an assertion never seen failing may be passing by doing nothing.
- A change to the `publish` job's steps cannot be verified by CI, which never
  publishes from a pull request. Carry the evidence in the pull request: a
  run of the same commands against a scratch tree, or what
  `tests/publish.sh` covers of it.

## Versioning

README *Versions and the official packages* has the scheme and the reason for
it. What it means for you:

- Do not write a version or a `debian/changelog` entry in a patch. The version
  is computed at build time, and `dch` adds the one entry that says who
  rebuilt Debian's package.
- Do not republish a version. `build/publish.sh` will not overwrite a
  published file: it logs that it left the first copy in place and carries
  on, so a second build's package silently never reaches users. A change to
  `backport/` ships by dispatching the build with `releasenum` bumped.
- `releasenum` goes back to 1 only with a new Debian version in
  `source.dsc.sha256`.

## Style

Match the file you are editing. Scripts and the workflow are commented for
*why*, not *what*: a comment says why this and not the obvious alternative.

Shell in `build/` and `tests/` is POSIX `sh` and runs under `set -eu`. All of
it is shellchecked by the `lint` job. Test scripts run in Debian and Ubuntu
containers, so GNU tools are available; a test that depends on one is pinning
the container, not the packaging, and should say so.
