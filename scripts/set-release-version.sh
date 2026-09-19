#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone

set -euo pipefail
version=${1#v}
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
	echo "Invalid release version: $1" >&2
	exit 2
}

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
sed -i -E "0,/^version = \"[0-9]+\.[0-9]+\.[0-9]+\"/s//version = \"$version\"/" "$repo_dir/aether/Cargo.toml"
sed -i -E "/^name = \"aether\"\r?$/{n;s/^version = \"[0-9]+\.[0-9]+\.[0-9]+\"(\r?)$/version = \"$version\"\1/;}" "$repo_dir/aether/Cargo.lock"
sed -i -E "s/^PKG_VERSION:=.*/PKG_VERSION:=$version/; s/^PKG_RELEASE:=.*/PKG_RELEASE:=1/" \
	"$repo_dir/openwrt/Makefile" "$repo_dir/luci-app-gozarbin/Makefile"

test "$(sed -n 's/^version = "\([0-9.]*\)"/\1/p' "$repo_dir/aether/Cargo.toml" | head -n 1)" = "$version"
test "$(sed -n '/^name = "aether"\r\?$/ { n; s/^version = "\([0-9.]*\)".*/\1/p; }' "$repo_dir/aether/Cargo.lock")" = "$version"
test "$(sed -n 's/^PKG_VERSION:=//p' "$repo_dir/openwrt/Makefile")" = "$version"
test "$(sed -n 's/^PKG_VERSION:=//p' "$repo_dir/luci-app-gozarbin/Makefile")" = "$version"
printf 'Release source and package version: %s\n' "$version"
