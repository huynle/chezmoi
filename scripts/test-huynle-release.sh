#!/bin/sh

set -eu

root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

if "$root/scripts/huynle-release.sh" build v2.73.3-huynle.1 "$root" 1 "$tmp/bad" 2> "$tmp/error"; then
	echo 'invalid commit unexpectedly accepted' >&2
	exit 1
fi
grep -q 'invalid commit' "$tmp/error"

if "$root/scripts/huynle-release.sh" build 2.73.3-huynle.1 deadbeef 1 "$tmp/bad" 2> "$tmp/error"; then
	echo 'invalid tag unexpectedly accepted' >&2
	exit 1
fi
grep -q 'invalid release tag' "$tmp/error"

commit=$(git -C "$root" rev-parse HEAD)
epoch=$(git -C "$root" show -s --format=%ct "$commit")
cd "$root"
./scripts/huynle-release.sh build v2.73.3-huynle.1 "$commit" "$epoch" "$tmp/one"
./scripts/huynle-release.sh build v2.73.3-huynle.1 "$commit" "$epoch" "$tmp/two"
diff -ru "$tmp/one" "$tmp/two"
(cd "$tmp/one" && sha256sum -c SHA256SUMS)
test "$(find "$tmp/one" -type f | wc -l)" -eq 15
grep -q '"windows/arm64"' "$tmp/one/manifest.json"

minisign -G -W -p "$tmp/test.pub" -s "$tmp/test.key" >/dev/null 2>&1
pubkey=$(tail -n 1 "$tmp/test.pub")
for file in "$tmp/one"/*; do
	minisign -S -s "$tmp/test.key" -m "$file" -x "$file.minisig" -t 'throwaway test signature' < /dev/null
	minisign -V -q -P "$pubkey" -m "$file" -x "$file.minisig"
done
