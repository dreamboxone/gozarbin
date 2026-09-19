#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone

set -euo pipefail

sdk=$(realpath "${1:?Usage: package-router-ipq40xx.sh <SDK path> <aether binary> <lyrebird binary> <output dir>}")
core=$(realpath "${2:?Missing core binary}")
pt=$(realpath "${3:?Missing lyrebird binary}")
out=${4:?Missing output directory}
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test -f "$sdk/rules.mk" -a -d "$sdk/package" -a -f "$core" -a -f "$pt"
arch=arm_cortex-a7_neon-vfpv4
backup=$(mktemp -d)

restore_sources() {
	for name in gozarbin luci-app-gozarbin; do
		if [ -d "$sdk/package/$name" ]; then
			mv "$sdk/package/$name" "$backup/built-$name"
		fi
		if [ -d "$backup/$name" ]; then
			mv "$backup/$name" "$sdk/package/$name"
		fi
	done
	printf 'SDK source backup: %s\n' "$backup"
}
trap restore_sources EXIT

for name in gozarbin luci-app-gozarbin; do
	if [ -d "$sdk/package/$name" ]; then
		mv "$sdk/package/$name" "$backup/$name"
	fi
done
cp -a "$repo/openwrt" "$sdk/package/gozarbin"
cp -a "$repo/luci-app-gozarbin" "$sdk/package/luci-app-gozarbin"
mkdir -p "$sdk/package/gozarbin/prebuilt/$arch/pt"
cp "$core" "$sdk/package/gozarbin/prebuilt/$arch/aether"
cp "$pt" "$sdk/package/gozarbin/prebuilt/$arch/pt/lyrebird"

cd "$sdk"
make defconfig >/dev/null
found=$(sed -n 's/^CONFIG_TARGET_ARCH_PACKAGES="\(.*\)"/\1/p' .config)
test "$found" = "$arch"
sed -i 's/^CONFIG_ALL=y/# CONFIG_ALL is not set/' .config
sed -i 's/^CONFIG_ALL_KMODS=y/# CONFIG_ALL_KMODS is not set/' .config
sed -i 's/^CONFIG_ALL_NONSHARED=y/# CONFIG_ALL_NONSHARED is not set/' .config
sed -i 's/^CONFIG_TARGET_ALL_PROFILES=y/# CONFIG_TARGET_ALL_PROFILES is not set/' .config
sed -i -E 's/^CONFIG_PACKAGE_([^=]+)=[ym]/# CONFIG_PACKAGE_\1 is not set/' .config
printf '\nCONFIG_PACKAGE_gozarbin=m\nCONFIG_PACKAGE_luci-app-gozarbin=m\n' >> .config
make defconfig >/dev/null
make package/gozarbin/clean package/luci-app-gozarbin/clean >/dev/null
make package/gozarbin/compile -j2 V=sc
make package/luci-app-gozarbin/compile -j2 V=sc
mkdir -p "$out"
find bin/packages -type f \( -name 'gozarbin-*.apk' -o -name 'luci-app-gozarbin-*.apk' \) -exec cp -f {} "$out"/ \;
find "$out" -maxdepth 1 -type f -name '*.apk' -print
