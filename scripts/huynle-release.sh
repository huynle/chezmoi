#!/bin/sh

set -eu

usage() {
	printf 'usage: %s build <tag> <commit> <source-date-epoch> <output-dir>\n' "$0" >&2
	exit 2
}

[ "$#" -eq 5 ] || usage
[ "$1" = build ] || usage

tag=$2
commit=$3
source_date_epoch=$4
output_dir=$5

case "$tag" in
	v[0-9]*.[0-9]*.[0-9]*-huynle.[0-9]*) ;;
	*)
		printf 'invalid release tag: %s (expected vX.Y.Z-huynle.N)\n' "$tag" >&2
		exit 1
		;;
esac
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
	tar --sort=name --mtime="@$source_date_epoch" --owner=0 --group=0 --numeric-owner \
		-C "$stage" -cf - . | gzip -n > "$output_dir/$name.tar.gz"
	rm -rf "$stage"
	trap - EXIT HUP INT TERM
done

git archive --format=tar --prefix="chezmoi-$version/" "$commit" | gzip -n > "$output_dir/chezmoi-$version-source.tar.gz"
(
	cd "$output_dir"
	sha256sum chezmoi-* > SHA256SUMS
)

cat > "$output_dir/manifest.json" <<EOF
{"schema":1,"project":"chezmoi","version":"$version","tag":"$tag","commit":"$commit","source_date_epoch":$source_date_epoch,"targets":["linux/amd64","linux/arm64","darwin/amd64","darwin/arm64","windows/amd64","windows/arm64"],"checksums":"SHA256SUMS"}
EOF
