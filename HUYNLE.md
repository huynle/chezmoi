# huynle/chezmoi fork

This public fork preserves chezmoi's upstream Git history and MIT license. It
exists so the Huynle fleet can install a reviewed, version-pinned build rather
than an upstream binary or package-manager build.

## Patch list

- A Huynle release workflow builds from source for Linux, macOS, and Windows on
  amd64 and arm64.
- Release binaries, archives, checksums, and the release manifest are signed
  with the fleet release minisign key.
- `scripts/huynle-release.sh` provides the reproducible release build used by
  CI. It uses `-trimpath`, an empty Go build ID, the tag commit timestamp,
  normalized archive metadata, and gzip without timestamps.

No product behavior differs from upstream. Add every future local patch to
this list and keep patches small enough to review during upstream merges.

## Release trust and configuration

The `fleet-release` GitHub environment must protect release approval and limit
deployment to the default branch and Huynle release tags. Configure:

- repository variable `FLEET_RELEASE_PUBKEY`: the single-line minisign public
  key (`RW...`); this is public and is included in each release;
- environment secret `FLEET_RELEASE_MINISIGN_KEY`: the matching unencrypted
  minisign secret-key file content.

The secret belongs only in the protected environment, never in repository or
organization variables. Do not use the production key for local tests.

## Review and merge an upstream release

There is deliberately no scheduled or automatic upstream synchronization.
Once a month, review upstream releases and security notices, then explicitly:

1. Fetch tags without changing the working branch: `git fetch upstream --tags`.
2. Create a branch from `origin/master`, for example
   `upstream/v2.74.0`: `git switch -c upstream/v2.74.0 origin/master`.
3. Merge the exact, verified upstream tag with a merge commit:
   `git merge --no-ff v2.74.0`. Do not merge a moving branch name.
4. Reconcile conflicts while preserving this file and the Huynle release
   workflow. Update the patch list if the fork delta changes.
5. Run `go test ./...`, `scripts/test-huynle-release.sh`, `actionlint`, and
   `shellcheck scripts/*.sh`.
6. Push the branch and open a pull request to `master`. Review the upstream
   changelog, commit range, license changes, CI changes, and local diff. Merge
   only after required tests and review pass.
7. On the reviewed merge commit, create `vX.Y.Z-huynle.N` (start at `.1` for a
   new upstream version), then push that exact tag. The tag starts the protected
   release workflow. Never retag or overwrite a published version.
8. Verify the GitHub Release checksums and minisign signatures with the public
   key before updating any fleet bundle pin.

If a release fails, fix it by pull request and increment `N`; do not move or
replace the failed tag.
