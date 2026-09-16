#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone

set -euo pipefail

if [[ $# -ne 3 ]]; then
	echo "usage: $0 <sdk-directory> <aether-binary> <output-directory>" >&2
	exit 2
fi

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
sdk_dir=$(cd "$1" && pwd)
binary=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
output=$3

[[ -x "$binary" ]] || { echo "aether binary is not executable: $binary" >&2; exit 1; }
mkdir -p "$output" "$sdk_dir/package"
rm -rf "$sdk_dir/package/aether" "$sdk_dir/package/luci-app-aether"
cp -a "$repo_dir/openwrt" "$sdk_dir/package/aether"
cp -a "$repo_dir/luci-app-aether" "$sdk_dir/package/luci-app-aether"
rm -f "$sdk_dir/tmp/.packageinfo" "$sdk_dir/tmp/.packagedeps"

make -C "$sdk_dir" defconfig
arch=$(awk -F= '/^CONFIG_TARGET_ARCH_PACKAGES=/{gsub(/"/, "", $2); print $2}' "$sdk_dir/.config")
mkdir -p "$sdk_dir/package/aether/prebuilt/$arch"
cp "$binary" "$sdk_dir/package/aether/prebuilt/$arch/aether"

make -C "$sdk_dir" defconfig
# AETHER_OBFUSCATE=1 in the environment strips the shipped scripts before they
# are installed into the packages.
obfuscate=${AETHER_OBFUSCATE:-0}
make -C "$sdk_dir" package/aether/compile V=s AETHER_OBFUSCATE="$obfuscate"
make -C "$sdk_dir" package/luci-app-aether/compile V=s AETHER_OBFUSCATE="$obfuscate"
find "$sdk_dir/bin/packages" -type f \( -name 'aether-*.apk' -o -name 'luci-app-aether-*.apk' -o -name 'aether_*.ipk' -o -name 'luci-app-aether_*.ipk' \) -exec cp -f {} "$output/" \;
