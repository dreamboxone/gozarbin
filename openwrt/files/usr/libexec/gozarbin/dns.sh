#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
#
# Sends the router's DNS through the tunnel while transparent mode is up, and
# puts it back the moment it is not.
#
# The filtering answers DNS itself. www.youtube.com comes back as the address of
# the block page — from the ISP's resolver, and from 8.8.8.8 as well, because
# port 53 is intercepted on the way there. Proxying the connection afterwards
# cannot help: by then it is a connection to the wrong address. So the question
# has to go through the tunnel too.
#
# Devices that ask the router get there through dnsmasq, which this points at
# sing-box's DNS listener; sing-box answers Iranian names from the ISP's
# resolver and everything else over DNS-over-HTTPS through the tunnel. Devices
# with a resolver of their own — a TV that asks 8.8.8.8 directly — never reach
# dnsmasq, and are caught by sing-box's DNS hijack instead.
#
# The file lives in dnsmasq's runtime directory under /tmp and never in
# /etc/config/dhcp. A reboot or a crash has to leave ordinary DNS behind, not DNS
# pointed at a sing-box that is no longer running.

snippet=gozarbin.conf
wanted=/var/run/gozarbin/dns-wanted

confdirs() { ls -d /tmp/dnsmasq*.d 2>/dev/null; }

restart_dnsmasq() {
	[ -x /etc/init.d/dnsmasq ] && /etc/init.d/dnsmasq restart >/dev/null 2>&1
	return 0
}

# Only while the service says it wants this, checked at the moment of writing and
# again after dnsmasq has restarted. A stop can land between the monitor deciding
# to turn DNS on and the file being written; the second look is what notices.
on() {
	local port dir changed=0 content
	[ -e "$wanted" ] || { echo 'not wanted: the service is stopping or DNS is off' >&2; return 1; }
	port=$(uci -q get gozarbin.main.dns_port)
	[ -n "$port" ] || port=1822
	content=$(printf 'no-resolv\nserver=127.0.0.1#%s' "$port")
	for dir in $(confdirs); do
		[ "$(cat "$dir/$snippet" 2>/dev/null)" = "$content" ] && continue
		printf '%s\n' "$content" > "$dir/$snippet"
		changed=1
	done
	[ "$changed" = 1 ] && restart_dnsmasq
	[ -e "$wanted" ] || { off; return 1; }
	return 0
}

off() {
	local dir changed=0
	for dir in $(confdirs); do
		[ -e "$dir/$snippet" ] || continue
		rm -f "$dir/$snippet"
		changed=1
	done
	[ "$changed" = 1 ] && restart_dnsmasq
	return 0
}

state() {
	local dir
	for dir in $(confdirs); do
		[ -e "$dir/$snippet" ] && { echo on; return 0; }
	done
	echo off
}

case "${1:-}" in
	on) on ;;
	off) off ;;
	state) state ;;
	*) echo 'Usage: dns.sh {on|off|state}' >&2; exit 2 ;;
esac
