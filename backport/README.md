# backport/

Local changes on top of Debian's source package (`source.dsc.sha256`),
applied by `build-deb.sh` with `patch -p1` in this order:

| Path | Applies to | Use |
| --- | --- | --- |
| `all/*.patch` | every target | a fix Debian has not shipped yet, e.g. a CVE |
| `<codename>/*.patch` | that release | toolchain adaptations |
| `<codename>/sources.list`, `preferences` | that release | build-deps from its official backports |

Today: `all/` is empty, and `trixie` builds Debian's source unchanged, taking
debhelper from trixie-backports. `bookworm` and `noble` (a symlink) share
`10-bookworm-noble.patch`, whose header says what each change is for.

## Shipping a security fix

1. Add `all/NN-<cve>.patch`: a patch against the unpacked source that adds
   `debian/patches/<cve>.patch` and appends it to `debian/patches/series`,
   so the fix shows up in the package the Debian way.
2. Dispatch the workflow with `releasenum` bumped, `publish=1`:
   `4.3.31-1~~xymon13+1` becomes `+2`.
3. When Debian ships the fix (new `source.dsc.sha256`), delete the patch and
   reset `releasenum` to 1.

Debian's own stable versions (bookworm 4.3.30-1+b2, trixie 4.3.30-4) get
security fixes from the Debian security team. This repo covers 4.3.31 only.
