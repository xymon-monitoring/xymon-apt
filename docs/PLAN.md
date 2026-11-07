# Plan

- **First publish**: set `GPG_PRIVATE_KEY` (xymon-rpm's key), enable Pages
  (GitHub Actions source), then dispatch `build` with `publish=1`.
- **Official backport**: 4.3.31-1 should reach testing about 5 days after the
  2026-11-07 upload, once its autopkgtest passes. Then ask the Debian maintainers
  (Roland Rosenfeld, Axel Beckert) about `trixie-backports`. Offer the
  bookworm/noble delta in `backport/bookworm/` as a starting point for
  `bookworm-backports-sloppy`.
- **Retire a target** once its official backport exists (trixie first).
- **Source URL**: the `.dsc` is fetched from deb.debian.org's pool, falling back
  to incoming. Once Debian supersedes 4.3.31-1, it leaves the pool; add
  snapshot.debian.org as a fallback then, or bump to the new version.
- **Snapshot/preview channels** like xymon-rpm: not needed while 4.3.31 is
  the only version.
- **Upstream's stale `debian/`** (2019) in xymon-monitoring/xymon: remove it or
  point to salsa.debian.org/debian/xymon.
