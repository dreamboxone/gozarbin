#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
#
# The one long-lived background task this package owns. It keeps a running total
# of what has gone through the proxy, which the nftables counters cannot do on
# their own because they start again at zero with every firewall reload, and it
# lets the sing-box version check decide for itself when a day has passed.
#
# procd runs it, so it lives and dies with the service and nothing is written to
# anybody else's crontab.

# Transparent mode points every LAN packet at the TProxy port, and that is only
# safe while two things are true: sing-box is listening on that port, and the
# core is listening on the SOCKS port sing-box hands every connection to. This
# keeps the redirect matched to those two facts — in when they hold, out when
# either stops holding. Nothing else installs it, so a tunnel that takes three
# minutes to find a gateway costs three minutes of direct traffic rather than
# three minutes of a LAN that refuses every connection.
#
# DNS follows the same rule for the same reason, with one more condition of its
# own: sing-box's DNS listener has to be there. dnsmasq pointed at a port with
# nothing behind it is every name on the network failing to resolve.
run_dir=/var/run/gozarbin
missing=0

listening() {
	netstat -ln 2>/dev/null | grep -q ":$1 "
}

port_of() {
	local port
	port=$(uci -q get "gozarbin.main.$1")
	[ -n "$port" ] || port=$2
	echo "$port"
}

redirect_up() { nft list chain inet gozarbin_proxy prerouting >/dev/null 2>&1; }
dns_up() { [ "$(/usr/libexec/gozarbin/dns.sh state)" = on ]; }

reconcile() {
	local tproxy socks dns
	[ "$(cat "$run_dir/wanted" 2>/dev/null)" = transparent ] || return 0
	tproxy=$(port_of tproxy_port 1821)
	socks=$(port_of socks_port 1819)
	dns=$(port_of dns_port 1822)

	if listening "$tproxy" && listening "$socks"; then
		missing=0
		if ! redirect_up; then
			logger -t gozarbin "tunnel and sing-box are both up; turning transparent mode on"
			/usr/libexec/gozarbin/firewall.sh start >/dev/null 2>&1 || true
		fi
		if [ -e "$run_dir/dns-wanted" ] && listening "$dns"; then
			if ! dns_up; then
				logger -t gozarbin "sending the network's DNS through the tunnel"
				/usr/libexec/gozarbin/dns.sh on
			fi
		elif dns_up; then
			logger -t gozarbin "sing-box is not answering DNS on port $dns; giving DNS back to the ISP"
			/usr/libexec/gozarbin/dns.sh off
		fi
		return 0
	fi

	redirect_up || dns_up || { missing=0; return 0; }
	# sing-box takes a moment to bind after the rules go in, and the core drops
	# its SOCKS port for a moment while it reconnects. Tearing everything down in
	# either window is the watchdog breaking what it guards. Three checks in a
	# row means it is really gone.
	missing=$((missing + 1))
	[ "$missing" -ge 3 ] || return 0
	missing=0
	logger -t gozarbin "the tunnel or sing-box stopped listening; taking transparent mode and DNS out so the LAN keeps working"
	/usr/libexec/gozarbin/dns.sh off
	/usr/libexec/gozarbin/firewall.sh accounting >/dev/null 2>&1 || true
}

# "Iran direct" and the ad list are both rule sets that have to be downloaded,
# and until they are, neither does anything — silently. A fresh install has
# none. So once the tunnel is up (GitHub is often only reachable through it),
# the missing ones are fetched, at most once an hour so an unreachable mirror
# does not turn into a download loop. geo-update.sh reloads the service itself.
rule_sets_missing() {
	local geo=/etc/gozarbin/geo
	have() { [ -s "$geo/$1.srs" ] || [ -s "$geo/$1.json" ]; }
	if [ "$(uci -q get gozarbin.main.geo_enabled)" != 0 ]; then
		have geoip-ir && have geosite-ir || return 0
	fi
	if [ "$(uci -q get gozarbin.main.block_ads)" = 1 ]; then
		have geosite-ads || return 0
	fi
	return 1
}

fetch_rule_sets() {
	local stamp="$run_dir/geo-attempt" last now
	rule_sets_missing || return 0
	listening "$(port_of socks_port 1819)" || return 0
	now=$(date +%s)
	last=$(cat "$stamp" 2>/dev/null)
	[ -n "$last" ] && [ $((now - last)) -lt 3600 ] && return 0
	echo "$now" > "$stamp"
	logger -t gozarbin "rule sets are missing; downloading them"
	# Detached: the reload at the end of it restarts this very loop.
	setsid /usr/libexec/gozarbin/geo-update.sh >/dev/null 2>&1 &
}

# Ten seconds, not thirty: this loop is now what switches transparent mode on,
# and the wait between a working tunnel and a working LAN is this number.
ticks=0
while :; do
	reconcile
	fetch_rule_sets
	# The version check decides for itself when a day has passed; asking it every
	# twenty minutes costs nothing and keeps the traffic total current.
	if [ $((ticks % 120)) -eq 0 ]; then
		/usr/libexec/gozarbin/singbox.sh --sample >/dev/null 2>&1
		/usr/libexec/gozarbin/singbox.sh --check >/dev/null 2>&1
	fi
	ticks=$((ticks + 1))
	sleep 10
done
