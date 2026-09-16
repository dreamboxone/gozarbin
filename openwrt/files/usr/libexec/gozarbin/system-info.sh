#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
#
# Everything the settings page shows once, at load: versions, kernel support and
# which transparent modes this router can actually run.

version_file=/usr/share/gozarbin/version

. /usr/libexec/gozarbin/packages.sh
pkg_snapshot

json_bool() { [ "$1" = 1 ] && echo true || echo false; }

# The package manager is the second source, not the first: the version stamped
# into the package at build time is there even when the database is unreadable.
gozarbin_version=$([ -r "$version_file" ] && head -n 1 "$version_file")
[ -n "$gozarbin_version" ] || gozarbin_version=$(pkg_version gozarbin)
core_version=$(/usr/bin/gozarbin --version 2>/dev/null | head -n 1 | tr -d '\r')
# Never the package version: on a router running Passwall2 that is Passwall2's
# core, which Gozarbin does not use.
singbox_version=$(/usr/libexec/gozarbin/singbox.sh --version 2>/dev/null)
singbox_origin=$(/usr/libexec/gozarbin/singbox.sh --origin 2>/dev/null)

pkg_installed kmod-nft-tproxy && tproxy=1 || tproxy=0
pkg_installed kmod-nft-socket && socket=1 || socket=0
command -v nft >/dev/null 2>&1 && nftables=1 || nftables=0
[ -n "$singbox_version" ] && singbox=1 || singbox=0
{ [ -c /dev/net/tun ] || pkg_installed kmod-tun; } >/dev/null 2>&1 && tun=1 || tun=0
ip rule list >/dev/null 2>&1 && iprule=1 || iprule=0

quoteless() { tr -d '"\\' ; }

model=$(head -n 1 /tmp/sysinfo/model 2>/dev/null | quoteless)
release=$(sed -n "s/^DISTRIB_DESCRIPTION='\(.*\)'$/\1/p" /etc/openwrt_release 2>/dev/null | head -n 1 | quoteless)
arch=$(sed -n "s/^DISTRIB_ARCH='\(.*\)'$/\1/p" /etc/openwrt_release 2>/dev/null | head -n 1 | quoteless)
core_version=$(printf '%s' "$core_version" | quoteless)

printf '{"gozarbin_version":"%s","core_version":"%s","singbox_version":"%s","singbox_origin":"%s","singbox":%s,"tproxy":%s,"socket":%s,"nftables":%s,"tun":%s,"iprule":%s,"socks":true,"model":"%s","release":"%s","arch":"%s"}\n' \
	"$gozarbin_version" "$core_version" "$singbox_version" "$singbox_origin" \
	"$(json_bool "$singbox")" "$(json_bool "$tproxy")" "$(json_bool "$socket")" \
	"$(json_bool "$nftables")" "$(json_bool "$tun")" "$(json_bool "$iprule")" \
	"$model" "$release" "$arch"
