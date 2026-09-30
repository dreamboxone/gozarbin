#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2025-2026 CluvexStudio contributors
set -euo pipefail

goos="${1:-}"
goarch="${2:-}"
out="${3:-}"
goarm="${4:-}"

if [ -z "$goos" ] || [ -z "$goarch" ] || [ -z "$out" ]; then
    echo "usage: psiphon-build.sh <goos> <goarch> <outdir> [goarm]" >&2
    exit 2
fi

repo="https://github.com/CluvexStudio/psiphon-tunnel-core.git"
branch="shirokhorshid"
commit="83aa73b9b982e7421e00117f5b0c5aceb5dda452"

if ! command -v go >/dev/null 2>&1; then
    echo "psiphon-build: no go toolchain on PATH" >&2
    exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

src="$work/psiphon"
if ! git -c core.longpaths=true clone --quiet --depth 50 --branch "$branch" "$repo" "$src"; then
    echo "psiphon-build: cannot reach github" >&2
    exit 1
fi

git -C "$src" checkout --quiet "$commit" 2>/dev/null ||
    echo "psiphon-build: pinned commit is gone, using $branch as it stands" >&2

ext=""
if [ "$goos" = "windows" ]; then
    ext=".exe"
fi

mkdir -p "$out"

# psiphon's tls fork reaches into crypto/tls and checks at startup that the
# struct it copies matches field for field. Built with any other go release than
# the one its go.mod names, the binary compiles fine and then panics before it
# does anything, so that exact release is fetched and used, newer or older than
# the go on PATH.
toolchain="$(sed -n 's/^toolchain \(go[0-9.]*\)[[:space:]]*$/\1/p' "$src/go.mod" | head -n 1)"
if [ -z "$toolchain" ]; then
    toolchain="$(sed -n 's/^go \([0-9.]*\)[[:space:]]*$/go\1/p' "$src/go.mod" | head -n 1)"
fi
if [ -z "$toolchain" ]; then
    echo "psiphon-build: no go release named in go.mod" >&2
    exit 1
fi
echo "psiphon-build: using $toolchain"

(
    cd "$src"
    GOTOOLCHAIN="$toolchain" \
    GOOS="$goos" GOARCH="$goarch" GOARM="$goarm" CGO_ENABLED=0 GOFLAGS=-mod=vendor \
        go build -trimpath -ldflags "-s -w" -o "$out/psiphon-tunnel-core$ext" ./ConsoleClient
)

echo "psiphon-build: $goos/$goarch ->"
ls -l "$out/psiphon-tunnel-core$ext"
