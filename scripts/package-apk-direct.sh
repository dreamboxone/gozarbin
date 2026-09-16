#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone

set -euo pipefail

if [ "$#" -ne 5 ]; then
	echo "Usage: $0 <sdk-dir> <arch> <aether-binary> <source-dir> <output-dir>" >&2
	exit 2
fi

sdk_dir=$1
arch=$2
binary=$3
source_dir=$4
output_dir=$5
apk_tool="$sdk_dir/staging_dir/host/bin/apk"
fakeroot_tool=$(command -v fakeroot)
fakeroot_lib="$sdk_dir/staging_dir/host/lib/libfakeroot.so"
faked_tool="$sdk_dir/staging_dir/host/bin/faked"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

test -x "$apk_tool"
test -x "$fakeroot_tool"
test -f "$fakeroot_lib"
test -x "$faked_tool"
test -f "$binary"
mkdir -p "$output_dir" "$work_dir/aether" "$work_dir/luci"

install -Dm0755 "$binary" "$work_dir/aether/usr/bin/aether"
install -Dm0755 "$source_dir/openwrt/files/usr/bin/aetherctl" "$work_dir/aether/usr/bin/aetherctl"
install -Dm0755 "$source_dir/openwrt/files/usr/libexec/aether/firewall.sh" "$work_dir/aether/usr/libexec/aether/firewall.sh"
install -Dm0755 "$source_dir/openwrt/files/usr/libexec/aether/passwall2-detect.sh" "$work_dir/aether/usr/libexec/aether/passwall2-detect.sh"
install -Dm0755 "$source_dir/openwrt/files/usr/libexec/aether/system-info.sh" "$work_dir/aether/usr/libexec/aether/system-info.sh"
install -Dm0755 "$source_dir/openwrt/files/usr/libexec/aether/update-iran.sh" "$work_dir/aether/usr/libexec/aether/update-iran.sh"
install -Dm0755 "$source_dir/openwrt/files/etc/init.d/aether" "$work_dir/aether/etc/init.d/aether"
install -Dm0644 "$source_dir/openwrt/files/etc/config/aether" "$work_dir/aether/etc/config/aether"
install -Dm0644 "$source_dir/openwrt/files/etc/aether/iran4.txt" "$work_dir/aether/etc/aether/iran4.txt"
install -Dm0644 "$source_dir/openwrt/files/etc/aether/iran6.txt" "$work_dir/aether/etc/aether/iran6.txt"
install -Dm0755 "$source_dir/openwrt/files/etc/uci-defaults/90-aether" "$work_dir/aether/etc/uci-defaults/90-aether"

cp -a "$source_dir/luci-app-aether/root/." "$work_dir/luci/"
mkdir -p "$work_dir/luci/www"
cp -a "$source_dir/luci-app-aether/htdocs/." "$work_dir/luci/www/"
find "$work_dir/luci" -type d -exec chmod 0755 {} +
find "$work_dir/luci" -type f -exec chmod 0644 {} +

"$fakeroot_tool" -l "$fakeroot_lib" -f "$faked_tool" "$apk_tool" mkpkg \
	--info name:aether --info version:2.0.0-r4 --info arch:"$arch" \
	--info license:AGPL-3.0-only --info origin:aether \
	--info url:https://github.com/dreamboxone/aether \
	--info description:'Aether SOCKS5 service with transparent LAN proxying and Iran bypass.' \
	--info 'depends:ca-bundle kmod-nft-tproxy kmod-nft-socket nftables sing-box' \
	--files "$work_dir/aether" --output "$output_dir/aether-2.0.0-r4.apk"

"$fakeroot_tool" -l "$fakeroot_lib" -f "$faked_tool" "$apk_tool" mkpkg \
	--info name:luci-app-aether --info version:2.0.0-r4 --info arch:noarch \
	--info license:AGPL-3.0-only --info origin:luci-app-aether \
	--info url:https://github.com/dreamboxone/aether \
	--info description:'LuCI interface for Aether.' \
	--info 'depends:aether luci-base rpcd-mod-file' \
	--files "$work_dir/luci" --output "$output_dir/luci-app-aether-2.0.0-r4.apk"

sha256sum "$output_dir/aether-2.0.0-r4.apk" "$output_dir/luci-app-aether-2.0.0-r4.apk"
