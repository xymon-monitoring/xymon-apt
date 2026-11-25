# Signing

The repository metadata is signed, the way every APT repository is: each
suite's `Release` file is signed (`InRelease`, and `Release.gpg` for older
clients), it carries the hash of every `Packages` index, and an index carries
the hash of every package. So `apt` verifies that the package list and each
package came from this project and were not altered in transit. The `.deb`
files carry no signature of their own; `apt` does not look for one.

## The key

The same key as xymon-rpm:

```
Xymon Project (RPM signing key)
RSA 4096, created 2026-07-31, expires 2029-07-30

BD24 FB87 154D 561B 66F6  66DF 639D E923 AA08 904A
```

The name says RPM because the key was made for xymon-rpm first; a user id can
be added without changing the fingerprint. Everything about the key itself —
how it was generated, why it has no passphrase and no email, renewing it
before expiry, rotating it — is in
[xymon-rpm's signing.md](https://github.com/xymon-monitoring/xymon-rpm/blob/main/docs/signing.md)
and is not repeated here. A renewal or a rotation there has to be followed
here: see *When the key changes* below.

The public half is `xymon-archive-keyring.asc` in this repository, and
`fingerprint` records its fingerprint. `tests/publish.sh` fails when the two
disagree. The fingerprint is also in `README.md`, because a fingerprint served
from the same host as the packages proves nothing on its own.

## Verifying as a user

The `xymon.sources` file a user fetches (`build/mksources.sh`) carries the
public key in its `Signed-By` field. So the key vouches for this repository
alone, not for every source on the host, and there is no separate key file to
install. Before trusting it, compare the key in the file with the fingerprint
above:

```sh
sed -n '/BEGIN PGP/,/END PGP/{s/^ //;s/^\.$//;p}' /etc/apt/sources.list.d/xymon.sources \
  | gpg --show-keys
```

The published tree also serves the key alone, as `xymon-archive-keyring.asc`
and `xymon-archive-keyring.gpg`, for a one-line `deb [signed-by=...]` entry.

## How signing happens in CI

The `publish` job in `.github/workflows/build.yml`:

1. imports the private key from the `GPG_PRIVATE_KEY` secret, and stops unless
   its fingerprint is the one the `fingerprint` file names;
2. runs `build/publish.sh`, which regenerates each suite's `Release` and signs
   it twice with `gpg`: `--clearsign` into `InRelease`, `--detach-sign` into
   `Release.gpg`.

## Maintainer setup

Once, before the first publish. All four are needed; without the secrets CI
builds and tests, and publishes nothing.

1. **Secret `GPG_PRIVATE_KEY`**: the same value as xymon-rpm's.
2. **The archive.** Create `xymon-monitoring/xymon-apt-archive` and seed it:
   the publish job refuses to start from a clone that fails.

   ```sh
   git init -b main seed && cd seed
   printf '%s\n' "The published tree of xymon-apt. Written by its publish job; serves nothing." > README.md
   git add README.md && git commit -m "Seed the archive"
   git push git@github.com:xymon-monitoring/xymon-apt-archive.git main
   ```
3. **Secret `ARCHIVE_DEPLOY_KEY`**: a deploy key with write access to the
   archive, and nothing else.

   ```sh
   ssh-keygen -t ed25519 -N '' -C 'xymon-apt publish -> xymon-apt-archive' -f ./archive-key
   gh repo deploy-key add ./archive-key.pub -R xymon-monitoring/xymon-apt-archive -w -t 'xymon-apt publish'
   gh secret set ARCHIVE_DEPLOY_KEY -R xymon-monitoring/xymon-apt < ./archive-key
   rm ./archive-key ./archive-key.pub
   ```

   It signs nothing and cannot put a package in front of a user: Pages serves
   the artifact the workflow uploads, not the archive. It has no expiry;
   rotate it the same way when someone who had access leaves.
4. **Settings → Pages → Source: GitHub Actions**, and the `github-pages`
   environment must allow `main` to deploy.

Then dispatch **build** with `publish=1`.

## When the key changes

- **Renewed** (same fingerprint, later expiry): replace
  `xymon-archive-keyring.asc` with the new export and publish. A host keeps
  the old copy inside its `xymon.sources`, so it has to fetch that file again
  before the old expiry date; say so in the release that carries it.
- **Rotated** (new fingerprint): replace `xymon-archive-keyring.asc`,
  `fingerprint` and the fingerprint in `README.md`, and the secret. Every host
  has to fetch `xymon.sources` again, and until it does `apt update` fails on
  this repository with a missing-key error.
