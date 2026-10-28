#!/bin/sh

set -eu

usage() {
	printf 'usage: %s build <tag> <commit> <source-date-epoch> <output-dir>\n       %s sign-package <tag> <source-date-epoch> <output-dir> <secret-key> <public-key>\n' "$0" "$0" >&2
	exit 2
}

validate_tag() {
	# Base version components allow leading zeros; the Huynle release does not.
	validated=$(printf '%s\n' "$1" | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+-huynle\.[1-9][0-9]*$' || true)
	if [ "$validated" != "$1" ]; then
		printf 'invalid release tag: %s (expected vX.Y.Z-huynle.N)\n' "$1" >&2
		exit 1
	fi
}

if [ "$#" -eq 5 ] && [ "$1" = merge-native ]; then
 output_dir=$2; mac_dir=$3; win_dir=$4; version=$5
 for arch in amd64 arm64; do
  cp "$mac_dir/chezmoi-darwin-$arch" "$output_dir/chezmoi-darwin-$arch"
  cp "$mac_dir/chezmoi-darwin-$arch" "$output_dir/dl/chezmoi/darwin/$arch"
  cp "$win_dir/chezmoi-windows-$arch.exe" "$output_dir/chezmoi-windows-$arch.exe"
  cp "$win_dir/chezmoi-windows-$arch.exe" "$output_dir/dl/chezmoi/windows/$arch"
 done
 cp "$mac_dir"/*.dmg "$mac_dir/apple-signing.ndjson" "$output_dir/"
 cp "$win_dir/windows-signing.json" "$output_dir/"
 rm -f "$output_dir"/chezmoi-darwin-*.tar.gz "$output_dir"/chezmoi-windows-*.tar.gz
 for target in darwin/amd64 darwin/arm64 windows/amd64 windows/arm64; do os=${target%/*}; arch=${target#*/}; ext=; [ "$os" = windows ] && ext=.exe; stage=$(mktemp -d); cp "$output_dir/chezmoi-$os-$arch$ext" "$stage/chezmoi$ext"; cp LICENSE README.md "$stage/"; tar --sort=name --owner=0 --group=0 --numeric-owner -C "$stage" -cf - . | gzip -n > "$output_dir/chezmoi-$os-$arch.tar.gz"; rm -rf "$stage"; done
 (
  cd "$output_dir"
  : > dl/chezmoi/SHA256SUMS
  for target in darwin/amd64 darwin/arm64 linux/amd64 linux/arm64 windows/amd64 windows/arm64; do os=${target%/*}; arch=${target#*/}; ext=; [ "$os" = windows ] && ext=.exe; digest=$(sha256sum "dl/chezmoi/$target" | cut -d ' ' -f 1); printf '%s  chezmoi-%s-%s%s\n' "$digest" "$os" "$arch" "$ext" >> dl/chezmoi/SHA256SUMS; done
 )
 exit 0
fi

if [ "$#" -eq 6 ] && [ "$1" = sign-package ]; then
	tag=$2
	validate_tag "$tag"
	source_date_epoch=$3
	output_dir=$4
	secret_key=$5
	public_key=$6
	version=${tag#v}
	archive="chezmoi-fleet-dl-$version.tar.gz"

	find "$output_dir/dl/chezmoi" -type f ! -name '*.minisig' -print | LC_ALL=C sort | while IFS= read -r file; do
		minisign -S -s "$secret_key" -m "$file" -x "$file.minisig" -t "chezmoi $version $(basename "$file")" < /dev/null
		minisign -V -q -P "$public_key" -m "$file" -x "$file.minisig"
	done
	tar --sort=name --mtime="@$source_date_epoch" --owner=0 --group=0 --numeric-owner \
		-C "$output_dir" -cf - dl | gzip -n > "$output_dir/$archive"
	minisign -S -s "$secret_key" -m "$output_dir/$archive" -x "$output_dir/$archive.minisig" -t "chezmoi $version $archive" < /dev/null
	minisign -V -q -P "$public_key" -m "$output_dir/$archive" -x "$output_dir/$archive.minisig"

	tmp_manifest="$output_dir/manifest.json.tmp"
	sed "s/}$/,\"fleet_dl_archive\":\"$archive\"}/" "$output_dir/manifest.json" > "$tmp_manifest"
	mv "$tmp_manifest" "$output_dir/manifest.json"
	(
		cd "$output_dir"
		manifest_tmp=$(mktemp)
		find . -maxdepth 1 -type f ! -name '*.minisig' ! -name SHA256SUMS -printf '%f\n' | LC_ALL=C sort | xargs sha256sum > "$manifest_tmp"
		mv "$manifest_tmp" SHA256SUMS
	)
	find "$output_dir" -maxdepth 1 -type f ! -name '*.minisig' -print | LC_ALL=C sort | while IFS= read -r file; do
		minisign -S -s "$secret_key" -m "$file" -x "$file.minisig" -t "chezmoi $version $(basename "$file")" < /dev/null
		minisign -V -q -P "$public_key" -m "$file" -x "$file.minisig"
	done
	exit 0
fi

[ "$#" -eq 5 ] || usage
[ "$1" = build ] || usage

tag=$2
validate_tag "$tag"
commit=$3
source_date_epoch=$4
output_dir=$5

version=${tag#v}

case "$commit" in
	*[!0-9a-f]*|'')
		printf 'invalid commit: %s\n' "$commit" >&2
		exit 1
		;;
esac
case "$source_date_epoch" in
	*[!0-9]*|'')
		printf 'invalid source date epoch: %s\n' "$source_date_epoch" >&2
		exit 1
		;;
esac

rm -rf "$output_dir"
mkdir -p "$output_dir"
output_dir=$(cd "$output_dir" && pwd)
build_date=$(date -u -d "@$source_date_epoch" +%Y-%m-%dT%H:%M:%SZ)
ldflags="-s -w -buildid= -X main.version=$version -X main.commit=$commit -X main.date=$build_date -X main.builtBy=huynle-release"

for target in linux/amd64 linux/arm64 darwin/amd64 darwin/arm64 windows/amd64 windows/arm64; do
	os=${target%/*}
	arch=${target#*/}
	name="chezmoi-$os-$arch"
	ext=
	[ "$os" = windows ] && ext=.exe
	stage=$(mktemp -d)
	trap 'rm -rf "$stage"' EXIT HUP INT TERM
	CGO_ENABLED=0 GOOS=$os GOARCH=$arch go build -trimpath -ldflags "$ldflags" -o "$stage/chezmoi$ext" .
	cp LICENSE README.md "$stage/"
	TZ=UTC find "$stage" -exec touch -h -d "@$source_date_epoch" {} +
	cp "$stage/chezmoi$ext" "$output_dir/$name$ext"
	mkdir -p "$output_dir/dl/chezmoi/$os"
	cp "$stage/chezmoi$ext" "$output_dir/dl/chezmoi/$os/$arch"
	tar --sort=name --mtime="@$source_date_epoch" --owner=0 --group=0 --numeric-owner \
		-C "$stage" -cf - . | gzip -n > "$output_dir/$name.tar.gz"
	rm -rf "$stage"
	trap - EXIT HUP INT TERM
done

git archive --format=tar --prefix="chezmoi-$version/" "$commit" | gzip -n > "$output_dir/chezmoi-$version-source.tar.gz"
(
	cd "$output_dir"
	sha256sum chezmoi-* > SHA256SUMS
	: > dl/chezmoi/SHA256SUMS
	for target in darwin/amd64 darwin/arm64 linux/amd64 linux/arm64 windows/amd64 windows/arm64; do
		os=${target%/*}
		arch=${target#*/}
		ext=
		[ "$os" = windows ] && ext=.exe
		digest=$(sha256sum "dl/chezmoi/$target" | cut -d ' ' -f 1)
		printf '%s  chezmoi-%s-%s%s\n' "$digest" "$os" "$arch" "$ext" >> dl/chezmoi/SHA256SUMS
	done
)

cat > "$output_dir/manifest.json" <<EOF
{"schema":1,"project":"chezmoi","version":"$version","tag":"$tag","commit":"$commit","source_date_epoch":$source_date_epoch,"targets":["linux/amd64","linux/arm64","darwin/amd64","darwin/arm64","windows/amd64","windows/arm64"],"checksums":"SHA256SUMS"}
EOF
