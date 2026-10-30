#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
export GOZARBIN_CORE_RUN=${GOZARBIN_GEO_RUN:-/var/run/gozarbin-geo}
lib=${GOZARBIN_LIB:-/usr/libexec/gozarbin}
geo_dir=${GOZARBIN_GEO_DIR:-/etc/gozarbin/geo}
updated() {
	local value file
	value=$(cat "$geo_dir/.$1.updated" 2>/dev/null || true)
	if [ -z "$value" ]; then
		for file in "$geo_dir/$1.srs" "$geo_dir/$1.json"; do
			[ ! -s "$file" ] || value=$(date -r "$file" +%s 2>/dev/null || true)
		done
	fi
	case "$value" in ''|*[!0-9]*) echo 0 ;; *) echo "$value" ;; esac
}
case "${1:-status}" in
	status)
		state=$("$lib/aether-core.sh" status) || exit $?
		target=$(cat "$GOZARBIN_CORE_RUN/target" 2>/dev/null || true)
		case "$target" in geoip|geosite|ads|all) ;; *) target=all ;; esac
		printf '%s,"target":"%s","files":{"geoip":%s,"geosite":%s,"ads":%s}}\n' \
			"${state%\}}" "$target" "$(updated geoip-ir)" "$(updated geosite-ir)" "$(updated geosite-ads)" ;;
	update)
		target=${2:-all}
		case "$target" in geoip|geosite|ads|all) ;; *) exit 2 ;; esac
		export GOZARBIN_GEO_TARGET="$target"
		"$lib/aether-core.sh" geo-update || exit $?
		printf '%s' "$target" > "$GOZARBIN_CORE_RUN/target" ;;
	*) exit 2 ;;
esac
