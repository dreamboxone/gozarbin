#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
#
# Downloads the sing-box rule sets named in /etc/config/gozarbin. Every source is a
# plain URL the user can change, so a mirror can be used when the default host is
# unreachable. A rule set is only moved into place once it looks like one.

set -e
. /lib/functions.sh

geo_dir=/etc/gozarbin/geo
mkdir -p "$geo_dir"

# The defaults live here as well as in /etc/config/gozarbin, so a config that was
# hand-edited or trimmed still has somewhere to fetch from.
rules=https://raw.githubusercontent.com/Chocolate4U/Iran-sing-box-rules/rule-set

config_load gozarbin
config_get geoip_url main geoip_url "$rules/geoip-ir.srs"
config_get geosite_url main geosite_url "$rules/geosite-ir.srs"
config_get ads_url main geosite_ads_url "$rules/geosite-category-ads-all.srs"
config_get_bool block_ads main block_ads 0

fetch() {
	local url="$1" name="$2" tmp ext
	[ -n "$url" ] || { echo "no source configured for $name" >&2; return 1; }
	case "$url" in
		*.json) ext=json ;;
		*) ext=srs ;;
	esac
	tmp="/tmp/gozarbin-$name.$$"
	uclient-fetch -q -T 60 -O "$tmp" "$url" || { rm -f "$tmp"; echo "download failed: $url" >&2; return 1; }
	[ -s "$tmp" ] || { rm -f "$tmp"; echo "empty download: $url" >&2; return 1; }
	if [ "$ext" = srs ]; then
		# Every compiled sing-box rule set starts with the same three bytes.
		[ "$(dd if="$tmp" bs=1 count=3 2>/dev/null)" = SRS ] || {
			rm -f "$tmp"; echo "not a sing-box rule set: $url" >&2; return 1; }
	else
		grep -q '"rules"' "$tmp" || { rm -f "$tmp"; echo "not a rule set source: $url" >&2; return 1; }
	fi
	rm -f "$geo_dir/$name.srs" "$geo_dir/$name.json"
	mv "$tmp" "$geo_dir/$name.$ext"
	echo "updated $name.$ext ($(wc -c < "$geo_dir/$name.$ext") bytes)"
}

status=0
fetch "$geoip_url" geoip-ir || status=1
fetch "$geosite_url" geosite-ir || status=1
[ "$block_ads" = 1 ] && { fetch "$ads_url" geosite-ads || status=1; }

date +%s > "$geo_dir/.updated"
[ "$(uci -q get gozarbin.main.enabled)" = 1 ] && /etc/init.d/gozarbin reload >/dev/null 2>&1 || true
logger -t gozarbin 'geo rule sets updated'
exit "$status"
