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

assert_invalid_tag() {
	tag=$1
	if "$root/scripts/huynle-release.sh" build "$tag" not-a-commit 1 "$tmp/bad" 2> "$tmp/error"; then
		echo "invalid tag unexpectedly accepted: $tag" >&2
		exit 1
	fi
	grep -q 'invalid release tag' "$tmp/error"

	# Tag validation must also precede filesystem access and signing.
	if "$root/scripts/huynle-release.sh" sign-package "$tag" 1 "$tmp/missing" "$tmp/missing.key" invalid-public-key 2> "$tmp/error"; then
		echo "invalid sign-package tag unexpectedly accepted: $tag" >&2
		exit 1
	fi
	grep -q 'invalid release tag' "$tmp/error"
}

for tag in \
	2.73.3-huynle.1 \
	v2x73.3-huynle.1 \
	v2.73.3-huynle.1-trailing \
	v2.73.3-huynle.-1 \
	v2.73.3-huynle.01 \
	v2.73.3-huynle. \
	"v2.73.3-huynle.1
injected"; do
	assert_invalid_tag "$tag"
done

# Base version components intentionally allow leading zeros; release N does not.
"$root/scripts/huynle-release.sh" build v02.073.003-huynle.1 not-a-commit 1 "$tmp/bad" 2> "$tmp/error" || true
grep -q 'invalid commit' "$tmp/error"

commit=$(git -C "$root" rev-parse HEAD)
epoch=$(git -C "$root" show -s --format=%ct "$commit")
cd "$root"
./scripts/huynle-release.sh build v2.73.3-huynle.1 "$commit" "$epoch" "$tmp/one"
./scripts/huynle-release.sh build v2.73.3-huynle.1 "$commit" "$epoch" "$tmp/two"
diff -ru "$tmp/one" "$tmp/two"
(cd "$tmp/one" && sha256sum -c SHA256SUMS)
test "$(find "$tmp/one" -type f | wc -l)" -eq 22
grep -q '"windows/arm64"' "$tmp/one/manifest.json"

test -f "$tmp/one/dl/chezmoi/SHA256SUMS"
test -f "$tmp/one/dl/chezmoi/linux/amd64"
test -f "$tmp/one/dl/chezmoi/windows/arm64"
grep -q '  chezmoi-linux-amd64$' "$tmp/one/dl/chezmoi/SHA256SUMS"
grep -q '  chezmoi-windows-arm64.exe$' "$tmp/one/dl/chezmoi/SHA256SUMS"
while read -r digest name; do
	target=${name#chezmoi-}
	os=${target%%-*}
	arch=${target#*-}
	arch=${arch%.exe}
	test "$(sha256sum "$tmp/one/dl/chezmoi/$os/$arch" | cut -d ' ' -f 1)" = "$digest"
done < "$tmp/one/dl/chezmoi/SHA256SUMS"

minisign -G -W -p "$tmp/test.pub" -s "$tmp/test.key" >/dev/null 2>&1
pubkey=$(tail -n 1 "$tmp/test.pub")
./scripts/huynle-release.sh sign-package v2.73.3-huynle.1 "$epoch" "$tmp/one" "$tmp/test.key" "$pubkey"
cp "$tmp/test.key" "$tmp/test-two.key"
./scripts/huynle-release.sh sign-package v2.73.3-huynle.1 "$epoch" "$tmp/two" "$tmp/test-two.key" "$pubkey"

archive=chezmoi-fleet-dl-2.73.3-huynle.1.tar.gz
cmp "$tmp/one/$archive" "$tmp/two/$archive"
minisign -V -q -P "$pubkey" -m "$tmp/one/$archive" -x "$tmp/one/$archive.minisig"
(cd "$tmp/one" && sha256sum -c SHA256SUMS)
grep -q "  $archive$" "$tmp/one/SHA256SUMS"
grep -q '"fleet_dl_archive":"chezmoi-fleet-dl-2.73.3-huynle.1.tar.gz"' "$tmp/one/manifest.json"

mkdir "$tmp/web-root"
tar -xzf "$tmp/one/$archive" -C "$tmp/web-root"
test -f "$tmp/web-root/dl/chezmoi/SHA256SUMS"
test -f "$tmp/web-root/dl/chezmoi/SHA256SUMS.minisig"
test -f "$tmp/web-root/dl/chezmoi/linux/amd64"
minisign -V -q -P "$pubkey" -m "$tmp/web-root/dl/chezmoi/SHA256SUMS" -x "$tmp/web-root/dl/chezmoi/SHA256SUMS.minisig"
test -f "$tmp/one/dl/chezmoi/SHA256SUMS.minisig"
