#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
#
# The package manager pulls these in when Gozarbin is installed. They are checked
# again at runtime because a router can be flashed, restored from a backup, or
# have a package removed by hand, and transparent mode fails in confusing ways
# when one of them is missing.
#
# sing-box is not in this list. Gozarbin keeps its own core and installs it from
# SagerNet's releases; a sing-box that belongs to Passwall2 is neither used nor
# upgraded here. See singbox.sh.

packages='kmod-nft-tproxy kmod-nft-socket nftables ip-full ca-bundle'
tun_packages='kmod-tun'

. /usr/libexec/gozarbin/packages.sh
# Taken here, in the top-level shell, so the command substitutions below inherit
# it instead of each re-reading the database in a subshell of its own.
pkg_snapshot

wanted() {
	local list="$packages"
	[ "$(uci -q get gozarbin.main.mode)" = tun ] && list="$list $tun_packages"
	echo "$list"
}

missing() {
	local name out=
	for name in $(wanted); do
		# nftables is a virtual package on fw4 releases. The installed provider
		# can be nftables-json or nftables-nojson, so test its actual executable.
		[ "$name" = nftables ] && command -v nft >/dev/null 2>&1 && continue
		pkg_installed "$name" || out="$out $name"
	done
	echo "${out# }"
}

report_json() {
	local name sep= gone
	gone=$(missing)
	printf '{"manager":"%s","packages":[' "$(pkg_manager)"
	for name in $(wanted); do
		printf '%s{"name":"%s","installed":%s,"version":"%s"}' \
			"$sep" "$name" "$(if [ "$name" = nftables ]; then command -v nft >/dev/null 2>&1; else pkg_installed "$name"; fi && echo true || echo false)" "$(pkg_version "$name")"
		sep=,
	done
	printf '],"missing":"%s","complete":%s}\n' "$gone" "$([ -z "$gone" ] && echo true || echo false)"
}

install_missing() {
	local gone
	gone=$(missing)
	[ -n "$gone" ] || { echo 'All dependencies are already installed.'; return 0; }
	echo "Installing:$gone"
	case "$(pkg_manager)" in
		apk) apk update && apk add $gone ;;
		opkg) opkg update && opkg install $gone ;;
		*) echo 'No supported package manager found.' >&2; return 1 ;;
	esac
}

case "${1:-}" in
	--json) report_json ;;
	--install) install_missing ;;
	--check) [ -z "$(missing)" ] ;;
	--missing) missing ;;
	*) printf 'missing:%s\n' " $(missing)" ;;
esac
