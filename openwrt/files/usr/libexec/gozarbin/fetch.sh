#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
#
# Getting a file off the internet from a router in Iran. Sourced, not run.
#
# GitHub answers directly on some Iranian networks and not on others, and on a
# third kind it answers and then delivers at a trickle. So: try direct, abandon
# it the moment it stalls, and go out through the tunnel this router already
# has. The tunnel is the slower road and the one that works, which is the right
# order to try them in.
#
# A caller that wants to know when the tunnel took over defines fetch_notice;
# it is called with the proxy address just before the second attempt.

socks_endpoint() {
	local port
	port=$(uci -q get gozarbin.main.socks_port)
	[ -n "$port" ] || port=1819
	netstat -ln 2>/dev/null | grep -q "127[.]0[.]0[.]1:$port[[:space:]]" || return 1
	printf '127.0.0.1:%s' "$port"
}

# fetch <url> <destination|-> <seconds>
fetch() {
	local url="$1" dest="$2" timeout="$3" socks
	if ! command -v curl >/dev/null 2>&1; then
		# No curl means no SOCKS, so there is only the direct road.
		if [ "$dest" = - ]; then
			uclient-fetch -q -T "$timeout" -O - "$url" 2>/dev/null
		else
			uclient-fetch -q -T "$timeout" -O "$dest" "$url" 2>/dev/null
		fi
		return
	fi
	# Under 5 kB/s for half a minute is throttling, not a slow link, and waiting
	# it out is not a plan. Into a file first, not straight to the destination:
	# a direct attempt that dies halfway must not leave half a body in front of
	# the second one. The file sits beside the destination, because /tmp is RAM
	# and a sing-box core is tens of megabytes.
	local body
	if [ "$dest" = - ]; then
		body=$(mktemp /tmp/gozarbin-fetch.XXXXXX) || return 1
	else
		body="$dest.part"
		rm -f "$body"
	fi
	if curl -fsSL --max-time "$timeout" --speed-limit 5000 --speed-time 30 -o "$body" "$url"; then
		fetch_deliver "$body" "$dest"
		return
	fi
	if socks=$(socks_endpoint); then
		command -v fetch_notice >/dev/null 2>&1 && fetch_notice "$socks"
		# stderr: when the destination is stdout, stdout is the file.
		echo "  direct fetch failed; going through the tunnel at $socks" >&2
		if curl -fsSL --max-time "$timeout" -x "socks5h://$socks" -o "$body" "$url"; then
			fetch_deliver "$body" "$dest"
			return
		fi
	fi
	rm -f "$body"
	return 1
}

fetch_deliver() {
	if [ "$2" = - ]; then
		cat "$1"
		rm -f "$1"
	else
		mv -f "$1" "$2"
	fi
}
