#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone

set -e
. /lib/functions.sh

config_load aether
config_get url4 main iran4_url
config_get url6 main iran6_url
tmp4="/tmp/aether-iran4.$$"
tmp6="/tmp/aether-iran6.$$"
trap 'rm -f "$tmp4" "$tmp6"' EXIT

fetch() {
	local url="$1" output="$2"
	uclient-fetch -q -T 30 -O "$output" "$url"
	grep -Eq '^[0-9a-fA-F:.]+/[0-9]+$' "$output"
}

fetch "$url4" "$tmp4"
fetch "$url6" "$tmp6"
sed -n '/^[0-9][0-9.]*\/[0-9][0-9]*$/p' "$tmp4" > /etc/aether/iran4.txt
sed -n '/^[0-9a-fA-F:][0-9a-fA-F:]*\/[0-9][0-9]*$/p' "$tmp6" > /etc/aether/iran6.txt
[ "$(uci -q get aether.main.enabled)" = 1 ] && /etc/init.d/aether reload || true
logger -t aether 'Iran IP ranges updated'
