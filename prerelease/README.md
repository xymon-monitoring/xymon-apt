# prerelease/

What Debian's packaging needs to build an upstream newer than the one it
packages. Used for every build from an upstream tree: the snapshot and
preview suites, and a release built from upstream's tag before Debian has
packaged it (README *Channels*). The rebuild of a Debian upload never reads
this directory.

A pre-release is Debian's `debian/` directory, from the `.dsc` pinned in
`source.dsc.sha256`, on an upstream tree made by `build/prepare-source.sh`.
`build/build-deb.sh` then applies, in this order:

| Path | What it does |
| --- | --- |
| `debian/` | copied over Debian's `debian/`: a file here replaces Debian's of the same name |
| `*.patch` | `patch -p1` on the assembled tree, for a change to part of a file under `debian/` |
| `../backport/` | as for a stable rebuild: `all/`, then the release's |

Today:

| File | Why |
| --- | --- |
| `debian/patches/12_hobbitvars.patch` | Debian's patch, rebased: upstream rewrote the lines around `XYMSRV` and `XYMONSERVERIP`. Its pidfile hunks and its two `xymonclient.cfg` paths are dropped, done in `debian/rules` by the last row |
| `debian/patches/13_apache_access_local.patch` | Debian's patch, rebased: upstream reordered both Apache files |
| `debian/xymon.install` | Debian's file without `build/renametasks`, `build/renamevars` and `build/upgrade430.sh`: upstream removed the Big Brother and Hobbit upgrade path, and nothing in Debian's maintainer scripts calls them |
| `debian/xymon.docs`, `debian/xymon-client.docs` | Debian's files without `docs/Renaming-430.txt` and `docs/upgrade-to-430.txt`, removed upstream with the same upgrade path |
| `10-rules.patch` | `debian/rules`: sets `XYMONRUNDIR` and `XYMONCLIENTRUNDIR` to `/var/run/xymon`, which upstream now reads at build time; names the client's tmp and log directories at build time too, `INSTALLCLIENTTMPDIR` and `INSTALLCLIENTLOGDIR`, and lets Debian's own two links replace the ones upstream then makes; sets `XYMONTMP` and `XYMONCLIENTLOGS` on the installed `xymonclient.cfg` where the tree does not name them by reference (next section); and no longer expects `man7` to be empty in the server package, since upstream added `xymon-tls.7` |

`skip-tests` is separate from those: it lists upstream tests a pre-release
build does not run, each with the upstream pull request whose merge removes
the line. It is for a test that fails for a reason upstream has to fix, where
no rebase here would help. Today it holds two:
`tests/web/showgraph-rrd-error-exit.sh`, until xymon#1024 is in `main` and in
the newest preview, since `showgraph`
crashes on about one failed graph in two hundred on Debian 12 and the test
makes two hundred; and `tests/server/serverconfig-local-client.sh`, which
`preview-4.3.32-5` carries in a form that fails on Debian's `XYMSRV`
arrangement, until a newer preview. A preview is cut from `main` at one
moment, so it can lack a test fix `main` already has. Nothing removes a line by itself; the build log says
`not running upstream test ...` every time, and that is the reminder.

## The client's tmp and log directories, and xymon#906

Debian's `12_hobbitvars.patch` writes `/var/lib/xymon/tmp` and
`/var/log/xymon` into `xymonclient.cfg`. Upstream is taking that over, in
steps, and `10-rules.patch` follows whichever step the tree it builds has:

| The tree has | `xymonclient.cfg` says | `10-rules.patch` |
| --- | --- | --- |
| xymon#411 only (`main` today, `preview-4.3.32-5`) | `$XYMONHOME/tmp`, or a placeholder in that preview | sets the two lines on the installed file, to Debian's values |
| xymon#906 (not merged yet; then `main`, and any preview that carries it) | `$XYMONCLIENTTMPDIR`, `$XYMONCLIENTLOGDIR`: the programs hold the directories | nothing: the two variables it passes to configure are what the programs hold |

Both rows give the same package to a host: `tests/install.sh` asks the
installed client's programs where they write, and expects Debian's two
directories whatever the file says. Built from xymon#906's head on trixie
and bookworm, the second row is the one taken.

When xymon#906 is merged and every published preview has it, the first row's
branch in `debian/rules` can go: the `else` of the test on
`xymonclient.cfg`. Until then both are needed, as a preview is cut from
`main` at one moment and can be older than a merge.

## This directory is a reading, not a fact

Debian's maintainers have not packaged the version these builds lead to.
What is here is the smallest change that makes their 4.3.31 packaging build
and run on the newer upstream, keeping every choice they made: the same
paths, the same included files, the same access rule. When they package that
version they may choose differently, and theirs then replaces, in the
stable suite, the release built here from upstream's tag.

## When the build goes red

Upstream `main` moves every day, and a commit that touches a line one of
Debian's patches touches breaks the nightly build at `quilt push`, which
`build/build-deb.sh` runs itself so that it fails: `dpkg-buildpackage` would
skip the whole series in silence when its first patch does not apply. That is this directory's job to absorb:

1. `./build/prepare-source.sh main upstream-src`, then in a copy of
   `upstream-src/tree` with Debian's `debian/` in place, apply the series by
   hand to find the patch and the hunk.
2. Re-make that patch against the new upstream, keeping Debian's header and
   saying in it what was rebased, and put it in `debian/patches/` here.
3. A change in upstream that the packaging has to follow, rather than a
   patch that no longer applies, goes in a `*.patch` here.

A preview is `main` plus pull requests, so it can differ from `main` on a
line a patch touches. There is one `prerelease/` for both, so a patch has to
fit both: give the hunk less context, or move the change out of the patch
and onto the installed file in `debian/rules`, as `XYMONTMP` was. If that
ever stops being possible, that is the moment to split the directory.

## When Debian packages the next version

Update `source.dsc.sha256` to it. Everything here was written against the
previous packaging: delete what Debian's new packaging makes unnecessary,
which should be all of it, and start again from what the next `main` breaks.
