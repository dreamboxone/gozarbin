#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
set -eu
umask 077
run=${GOZARBIN_CONNECT_RUN:-/var/run/gozarbin/connectivity}
mkdir -p "$run"
empty() { printf '{"ping":null,"country":""}\n'; }
pid=${GOZARBIN_CONNECT_PID:-$(ubus call service list '{"name":"gozarbin"}' 2>/dev/null | jsonfilter -e '@.gozarbin.instances.gozarbin.pid' 2>/dev/null || true)}
case "$pid" in ''|*[!0-9]*) empty; exit ;; esac
port=$(uci -q get gozarbin.main.socks_port 2>/dev/null || true)
case "$port" in ''|*[!0-9]*) port=1819 ;; esac
address=$(uci -q get gozarbin.main.socks_address 2>/dev/null || true)
case "$address" in ''|0.0.0.0|::) address=127.0.0.1 ;; *:*) address="[$address]" ;; esac
key="$pid:$address:$port"
case "${1:-status}" in
	status)
		stored=$(cat "$run/key" 2>/dev/null || true)
		if [ "$stored" = "$key" ] && [ -s "$run/state.json" ]; then cat "$run/state.json"; else empty; fi
		checked=$(cat "$run/checked" 2>/dev/null || true)
		case "$checked" in ''|*[!0-9]*) checked=0 ;; esac
		if [ -d "$run/lock" ] && [ -s "$run/pid" ]; then
			kill -0 "$(cat "$run/pid")" 2>/dev/null || { rm -f "$run/pid"; rmdir "$run/lock" 2>/dev/null || true; }
		fi
		if [ "$stored" != "$key" ] || [ $(( $(date +%s) - checked )) -ge 30 ]; then
			if mkdir "$run/lock" 2>/dev/null; then
				setsid "$0" worker > "$run/log" 2>&1 < /dev/null &
				echo "$!" > "$run/pid"
			fi
		fi
		exit ;;
	worker) ;;
	*) exit 2 ;;
esac
echo "$$" > "$run/pid"
cleanup() { rm -f "$run/pid" "$run/trace"; rmdir "$run/lock" 2>/dev/null || true; }
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
proxy="socks5h://$address:$port"
ping=null
# No direct fallback: this is an HTTP URL-test through Gozarbin, never ICMP.
if result=$(curl -fsS --noproxy '' --proxy "$proxy" --connect-timeout 4 --max-time 8 \
	-o /dev/null -w '%{http_code} %{time_total}' https://www.gstatic.com/generate_204); then
	ping=$(printf '%s\n' "$result" | awk '$1 == 204 && $2 > 0 {printf "%.0f", $2 * 1000}')
	[ -n "$ping" ] || ping=null
fi
country=
if curl -fsS --noproxy '' --proxy "$proxy" --connect-timeout 4 --max-time 8 \
	--max-filesize 65536 https://www.cloudflare.com/cdn-cgi/trace -o "$run/trace"; then
	country=$(sed -n 's/^loc=\([A-Z][A-Z]\)$/\1/p' "$run/trace" | head -n 1)
fi
printf '{"ping":%s,"country":"%s"}\n' "$ping" "$country" > "$run/state.new"
mv "$run/state.new" "$run/state.json"
printf '%s' "$key" > "$run/key"
date +%s > "$run/checked"
