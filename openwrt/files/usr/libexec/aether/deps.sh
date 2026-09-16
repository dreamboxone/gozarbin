#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
#
# The package manager pulls these in when Aether is installed. They are checked
# again at runtime because a router can be flashed, restored from a backup, or
# have a package removed by hand, and transparent mode fails in confusing ways
# when one of them is missing.

packages='sing-box kmod-nft-tproxy kmod-nft-socket nftables ip-full ca-bundle'
tun_packages='kmod-tun'

pm() {
	if command -v apk >/dev/null 2>&1; then echo apk
	elif command -v opkg >/dev/null 2>&1; then echo opkg
	fi
}

installed() {
	case "$(pm)" in
		apk) apk info -e "$1" >/dev/null 2>&1 ;;
		opkg) opkg status "$1" 2>/dev/null | grep -q '^Status:.* installed' ;;
		*) return 1 ;;
	esac
}

version_of() {
	case "$(pm)" in
		apk) apk list --installed "$1" 2>/dev/null | sed -n "s/^$1-\([^ ]*\).*/\1/p" | head -n 1 ;;
		opkg) opkg status "$1" 2>/dev/null | sed -n 's/^Version: //p' | head -n 1 ;;
	esac
}

wanted() {
	local list="$packages"
	[ "$(uci -q get aether.main.mode)" = tun ] && list="$list $tun_packages"
	echo "$list"
}

missing() {
	local name out=
	for name in $(wanted); do
		installed "$name" || out="$out $name"
	done
	echo "${out# }"
}

report_json() {
	local name sep= gone
	gone=$(missing)
	printf '{"manager":"%s","packages":[' "$(pm)"
	for name in $(wanted); do
		printf '%s{"name":"%s","installed":%s,"version":"%s"}' \
			"$sep" "$name" "$(installed "$name" && echo true || echo false)" "$(version_of "$name")"
		sep=,
	done
	printf '],"missing":"%s","complete":%s}\n' "$gone" "$([ -z "$gone" ] && echo true || echo false)"
}

install_missing() {
	local gone
	gone=$(missing)
	[ -n "$gone" ] || { echo 'All dependencies are already installed.'; return 0; }
	echo "Installing:$gone"
	case "$(pm)" in
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
