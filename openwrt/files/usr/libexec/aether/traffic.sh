#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
#
# One JSON line describing what the service is doing right now: whether the two
# processes are up, how long the proxy has been up, and how many bytes have
# crossed the SOCKS5 hop in each direction. The LuCI page polls this.

table=aether_proxy

json_bool() { [ "$1" = 1 ] && echo true || echo false; }

first_pid() {
	local pid
	pid=$(pidof "$1" 2>/dev/null | awk '{ print $1 }')
	printf '%s' "$pid"
}

# Seconds since the process was forked, from its start time in clock ticks.
process_uptime() {
	local pid="$1" boot ticks start
	[ -n "$pid" ] && [ -r "/proc/$pid/stat" ] || { echo 0; return; }
	boot=$(awk '{ print int($1) }' /proc/uptime 2>/dev/null)
	ticks=$(getconf CLK_TCK 2>/dev/null)
	[ -n "$ticks" ] && [ "$ticks" -gt 0 ] 2>/dev/null || ticks=100
	start=$(awk '{ print $22 }' "/proc/$pid/stat" 2>/dev/null)
	[ -n "$start" ] || { echo 0; return; }
	echo $((boot - start / ticks))
}

counters=$(nft list counters table inet "$table" 2>/dev/null | awk '
	/^[\t ]*counter[\t ]/ { name = $2; next }
	/packets/ {
		for (i = 1; i < NF; i++) {
			if ($i == "packets") packets = $(i + 1)
			if ($i == "bytes") bytes = $(i + 1)
		}
		if (name != "") printf "%s_packets=%s %s_bytes=%s ", name, packets, name, bytes
		name = ""
	}
')

upload_bytes=0
download_bytes=0
upload_packets=0
download_packets=0
accounting=0
for pair in $counters; do
	case "$pair" in
		upload_bytes=*) upload_bytes=${pair#*=}; accounting=1 ;;
		download_bytes=*) download_bytes=${pair#*=}; accounting=1 ;;
		upload_packets=*) upload_packets=${pair#*=} ;;
		download_packets=*) download_packets=${pair#*=} ;;
	esac
done

aether_pid=$(first_pid aether)
singbox_pid=$(first_pid sing-box)
[ -n "$aether_pid" ] && running=1 || running=0
[ -n "$singbox_pid" ] && singbox=1 || singbox=0
mode=$(uci -q get aether.main.mode)
[ -n "$mode" ] && [ "$mode" != tproxy ] || mode=tproxy
enabled=$(uci -q get aether.main.enabled)
[ "$enabled" = 1 ] || enabled=0

printf '{"enabled":%s,"running":%s,"singbox":%s,"mode":"%s","uptime":%s,"accounting":%s,"upload":%s,"download":%s,"upload_packets":%s,"download_packets":%s,"time":%s}\n' \
	"$(json_bool "$enabled")" "$(json_bool "$running")" "$(json_bool "$singbox")" "$mode" \
	"$(process_uptime "$aether_pid")" "$(json_bool "$accounting")" \
	"$upload_bytes" "$download_bytes" "$upload_packets" "$download_packets" \
	"$(date +%s)"
