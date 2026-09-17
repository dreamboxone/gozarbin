#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
#
# One JSON line describing what the service is doing right now: whether the two
# processes are up, how long the proxy has been up, and how many bytes have
# crossed the SOCKS5 hop in each direction. The LuCI page polls this.

table=gozarbin_proxy

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
# Whether the counters exist right now, which is not the same question as
# whether the user asked for counting: a stopped service has no counters and has
# not been told to stop counting.
counters_live=0
for pair in $counters; do
	case "$pair" in
		upload_bytes=*) upload_bytes=${pair#*=}; counters_live=1 ;;
		download_bytes=*) download_bytes=${pair#*=}; counters_live=1 ;;
		upload_packets=*) upload_packets=${pair#*=} ;;
		download_packets=*) download_packets=${pair#*=} ;;
	esac
done

# Matched on our own config path, not on the process name: another proxy on this
# router may be running a sing-box of its own, and that one is not ours to count.
gozarbin_singbox() {
	local dir
	for dir in /proc/[0-9]*; do
		grep -qs 'gozarbin/sing-box.json' "$dir/cmdline" && return 0
	done
	return 1
}

gozarbin_pid=$(first_pid gozarbin)
[ -n "$gozarbin_pid" ] && running=1 || running=0
gozarbin_singbox && singbox=1 || singbox=0
reason=$(head -n 1 /var/run/gozarbin/transparent-off 2>/dev/null)
mode=$(uci -q get gozarbin.main.mode)
[ -n "$mode" ] && [ "$mode" != tproxy ] || mode=tproxy
enabled=$(uci -q get gozarbin.main.enabled)
[ "$enabled" = 1 ] || enabled=0
# Unset means on: that is the default the firewall script builds its rules with.
accounting=$(uci -q get gozarbin.main.accounting)
[ "$accounting" = 0 ] || accounting=1
# The non-Iranian exit: off; starting, while Tor and then WARP come up, which
# takes a couple of minutes; ready once its SOCKS port answers; or down, when it
# was meant to run and is not running at all.
unblock=off
if [ "$(uci -q get gozarbin.main.unblock)" = 1 ] && [ "$running" = 1 ] && [ "$singbox" = 1 ]; then
	unblock_port=$(uci -q get gozarbin.main.unblock_port)
	[ -n "$unblock_port" ] || unblock_port=1823
	if netstat -ln 2>/dev/null | grep -q ":$unblock_port "; then
		unblock=ready
	elif [ -n "$(first_pid gozarbin-unblock)" ]; then
		unblock=starting
	else
		unblock=down
	fi
fi

printf '{"enabled":%s,"running":%s,"singbox":%s,"mode":"%s","transparent_off":"%s","uptime":%s,"accounting":%s,"counters":%s,"upload":%s,"download":%s,"upload_packets":%s,"download_packets":%s,"unblock":"%s","time":%s}\n' \
	"$(json_bool "$enabled")" "$(json_bool "$running")" "$(json_bool "$singbox")" \
	"$mode" "$reason" \
	"$(process_uptime "$gozarbin_pid")" "$(json_bool "$accounting")" "$(json_bool "$counters_live")" \
	"$upload_bytes" "$download_bytes" "$upload_packets" "$download_packets" \
	"$unblock" "$(date +%s)"
