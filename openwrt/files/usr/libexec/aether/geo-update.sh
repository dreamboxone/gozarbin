#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
#
# Downloads the sing-box rule sets named in /etc/config/aether. Every source is a
# plain URL the user can change, so a mirror can be used when the default host is
# unreachable. A rule set is only moved into place once it looks like one.

set -e
. /lib/functions.sh

geo_dir=/etc/aether/geo
mkdir -p "$geo_dir"

config_load aether
config_get geoip_url main geoip_url
config_get geosite_url main geosite_url
config_get ads_url main geosite_ads_url
config_get_bool block_ads main block_ads 0

fetch() {
	local url="$1" name="$2" tmp ext
	[ -n "$url" ] || return 0
	case "$url" in
		*.json) ext=json ;;
		*) ext=srs ;;
	esac
	tmp="/tmp/aether-$name.$$"
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
[ "$(uci -q get aether.main.enabled)" = 1 ] && /etc/init.d/aether reload >/dev/null 2>&1 || true
logger -t aether 'geo rule sets updated'
exit "$status"
