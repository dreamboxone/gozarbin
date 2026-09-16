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
# they stop holding. Nothing else installs it, so a tunnel that takes three
# minutes to find a gateway costs three minutes of direct traffic rather than
# three minutes of a LAN that refuses every connection.
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

reconcile() {
	local tproxy socks
	[ "$(cat /var/run/gozarbin/wanted 2>/dev/null)" = transparent ] || return 0
	tproxy=$(port_of tproxy_port 1821)
	socks=$(port_of socks_port 1819)

	if ! redirect_up; then
		missing=0
		listening "$tproxy" || return 0
		listening "$socks" || return 0
		logger -t gozarbin "tunnel and sing-box are both up; turning transparent mode on"
		/usr/libexec/gozarbin/firewall.sh start >/dev/null 2>&1 || true
		return 0
	fi

	if listening "$tproxy"; then
		missing=0
		return 0
	fi
	# sing-box takes a moment to bind after the rules go in, and tearing the
	# redirect down in that window is the watchdog breaking what it guards.
	# Three checks in a row means it is really gone, not merely still starting.
	missing=$((missing + 1))
	[ "$missing" -ge 3 ] || return 0
	missing=0
	logger -t gozarbin "nothing is listening on TProxy port $tproxy; removing the redirect so the LAN keeps working"
	/usr/libexec/gozarbin/firewall.sh accounting >/dev/null 2>&1 || true
}

# Ten seconds, not thirty: this loop is now what switches transparent mode on,
# and the wait between a working tunnel and a working LAN is this number.
ticks=0
while :; do
	reconcile
	# The version check decides for itself when a day has passed; asking it every
	# twenty minutes costs nothing and keeps the traffic total current.
	if [ $((ticks % 120)) -eq 0 ]; then
		/usr/libexec/gozarbin/singbox.sh --sample >/dev/null 2>&1
		/usr/libexec/gozarbin/singbox.sh --check >/dev/null 2>&1
	fi
	ticks=$((ticks + 1))
	sleep 10
done
