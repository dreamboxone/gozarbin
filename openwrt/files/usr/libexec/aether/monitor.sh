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

# Transparent mode points every LAN packet at the TProxy port. If whatever was
# meant to be listening there is gone — sing-box crashed, was killed, never
# started — the rules keep pointing and the whole network loses its internet
# with nothing to show for it. The redirect comes out until a listener is back;
# the byte counters, which harm nothing, stay.
missing=0
watchdog() {
	local port
	nft list chain inet aether_proxy prerouting >/dev/null 2>&1 || { missing=0; return 0; }
	port=$(uci -q get aether.main.tproxy_port)
	[ -n "$port" ] || port=1821
	if netstat -ln 2>/dev/null | grep -q ":$port "; then
		missing=0
		return 0
	fi
	# sing-box takes a moment to bind after the rules go in, and tearing the
	# redirect down in that window is the watchdog breaking what it guards. Two
	# checks in a row means it is really gone, not merely still starting.
	missing=$((missing + 1))
	[ "$missing" -ge 2 ] || return 0
	missing=0
	logger -t aether "nothing is listening on TProxy port $port; removing the redirect so the LAN keeps working"
	/usr/libexec/aether/firewall.sh accounting >/dev/null 2>&1 || true
}

ticks=0
while :; do
	watchdog
	# The version check decides for itself when a day has passed; asking it every
	# half minute costs nothing and keeps the traffic total current.
	if [ $((ticks % 40)) -eq 0 ]; then
		/usr/libexec/aether/singbox.sh --sample >/dev/null 2>&1
		/usr/libexec/aether/singbox.sh --check >/dev/null 2>&1
	fi
	ticks=$((ticks + 1))
	sleep 30
done
