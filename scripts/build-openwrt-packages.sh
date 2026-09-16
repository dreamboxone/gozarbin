#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone

set -euo pipefail

if [[ $# -ne 3 ]]; then
	echo "usage: $0 <sdk-directory> <core-binary> <output-directory>" >&2
	exit 2
fi

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
sdk_dir=$(cd "$1" && pwd)
binary=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
output=$3

[[ -x "$binary" ]] || { echo "core binary is not executable: $binary" >&2; exit 1; }
mkdir -p "$output" "$sdk_dir/package"
rm -rf "$sdk_dir/package/gozarbin" "$sdk_dir/package/luci-app-gozarbin"
cp -a "$repo_dir/openwrt" "$sdk_dir/package/gozarbin"
cp -a "$repo_dir/luci-app-gozarbin" "$sdk_dir/package/luci-app-gozarbin"
rm -f "$sdk_dir/tmp/.packageinfo" "$sdk_dir/tmp/.packagedeps"

make -C "$sdk_dir" defconfig
arch=$(awk -F= '/^CONFIG_TARGET_ARCH_PACKAGES=/{gsub(/"/, "", $2); print $2}' "$sdk_dir/.config")
mkdir -p "$sdk_dir/package/gozarbin/prebuilt/$arch"
cp "$binary" "$sdk_dir/package/gozarbin/prebuilt/$arch/aether"

make -C "$sdk_dir" defconfig
# GOZARBIN_OBFUSCATE=1 in the environment strips the shipped scripts before they
# are installed into the packages.
obfuscate=${GOZARBIN_OBFUSCATE:-0}
make -C "$sdk_dir" package/gozarbin/compile V=s GOZARBIN_OBFUSCATE="$obfuscate"
make -C "$sdk_dir" package/luci-app-gozarbin/compile V=s GOZARBIN_OBFUSCATE="$obfuscate"
find "$sdk_dir/bin/packages" -type f \( -name 'gozarbin-*.apk' -o -name 'luci-app-gozarbin-*.apk' -o -name 'gozarbin_*.ipk' -o -name 'luci-app-gozarbin_*.ipk' \) -exec cp -f {} "$output/" \;
