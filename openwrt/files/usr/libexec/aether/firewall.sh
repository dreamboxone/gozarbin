#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone

set -e
. /lib/functions.sh

run_dir=/var/run/aether
nft_file="$run_dir/aether.nft"
singbox_file="$run_dir/sing-box.json"
ruleset_dir="$run_dir/rulesets"
geo_dir=/etc/aether/geo
table_name=aether_proxy
singbox=$(/usr/libexec/aether/singbox.sh --path 2>/dev/null)

# "all" builds the table transparent mode needs; "accounting" builds only the
# byte counters. The second is what runs when transparent mode stands down —
# for Passwall2, for a missing dependency, or because the mode is SOCKS5-only —
# so the page still reports what left through the proxy without this touching
# anybody else's prerouting rules.
wanted_rules=all

load_config() {
	config_load aether
	config_get mode main mode tproxy
	config_get mark main mark 0x0aff
	config_get route_table main route_table 103
	config_get socks_address main socks_address 127.0.0.1
	config_get socks_port main socks_port 1819
	config_get tproxy_port main tproxy_port 1821
	config_get tproxy_mark main tproxy_mark 0x0a38
	config_get tun_name main tun_name aether-tun
	config_get tun_address main tun_address 172.19.0.1/30
	config_get tun_address6 main tun_address6 'fdfe:dcba:9876::1/126'
	config_get tun_mtu main tun_mtu 9000
	config_get singbox_log main singbox_log_level warn
	config_get geo_action main geo_action direct
	config_get_bool iran_bypass main iran_bypass 1
	config_get_bool accounting main accounting 1
	config_get_bool geo_enabled main geo_enabled 0
	config_get_bool block_ads main block_ads 0
	lan_interfaces=
	config_list_foreach main lan_interface add_lan
	[ -n "$lan_interfaces" ] || lan_interfaces='"br-lan"'
}

add_lan() {
	local escaped
	escaped=$(printf '%s' "$1" | sed 's/["\\]/\\&/g')
	lan_interfaces="${lan_interfaces}${lan_interfaces:+, }\"${escaped}\""
}

cidr_list() {
	local file="$1" family="$2"
	[ -r "$file" ] || return 0
	if [ "$family" = 4 ]; then
		sed -n '/^[0-9][0-9.]*\/[0-9][0-9]*$/p' "$file"
	else
		sed -n '/^[0-9a-fA-F:][0-9a-fA-F:]*\/[0-9][0-9]*$/p' "$file"
	fi
}

cidr_elements() {
	cidr_list "$1" "$2" | awk 'BEGIN { sep = "" } { printf "%s%s", sep, $0; sep = "," } END { print "" }'
}

# Both counters sit on the hop between sing-box (or any other SOCKS5 client) and
# the Aether proxy, so they measure what really left through the tunnel in either
# mode, and they keep counting for clients that speak SOCKS5 directly.
accounting_rules() {
	[ "$accounting" = 1 ] || return 0
	# Written the way nft dumps a counter object, so the file reloads verbatim.
	echo "	counter upload {"
	echo "		packets 0 bytes 0"
	echo "	}"
	echo "	counter download {"
	echo "		packets 0 bytes 0"
	echo "	}"
	echo "	chain accounting_output {"
	echo "		type filter hook output priority filter; policy accept;"
	echo "		oifname \"lo\" meta l4proto { tcp, udp } th dport $socks_port counter name \"upload\""
	echo "		oifname \"lo\" meta l4proto { tcp, udp } th sport $socks_port counter name \"download\""
	echo "		oifname != \"lo\" meta l4proto { tcp, udp } th sport $socks_port counter name \"download\""
	echo "	}"
	echo "	chain accounting_input {"
	echo "		type filter hook input priority filter; policy accept;"
	echo "		iifname != \"lo\" meta l4proto { tcp, udp } th dport $socks_port counter name \"upload\""
	echo "	}"
}

tproxy_rules() {
	local iran4 iran6
	[ "$wanted_rules" = all ] || return 0
	[ "$mode" = tproxy ] || return 0
	iran4=
	iran6=
	if [ "$iran_bypass" = 1 ]; then
		iran4=$(cidr_elements /etc/aether/iran4.txt 4)
		iran6=$(cidr_elements /etc/aether/iran6.txt 6)
	fi
	echo "	set lan_ifaces { type ifname; elements = { $lan_interfaces } }"
	echo "	set bypass4 { type ipv4_addr; flags interval; auto-merge; elements = { 0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.0.0.0/24, 192.168.0.0/16, 198.18.0.0/15, 224.0.0.0/3${iran4:+, $iran4} } }"
	echo "	set bypass6 { type ipv6_addr; flags interval; auto-merge; elements = { ::/128, ::1/128, fc00::/7, fe80::/10, ff00::/8${iran6:+, $iran6} } }"
	echo "	chain prerouting {"
	echo "		type filter hook prerouting priority mangle; policy accept;"
	echo "		iifname != @lan_ifaces return"
	echo "		meta mark $mark return"
	echo "		fib daddr type local return"
	echo "		meta nfproto ipv4 ip daddr @bypass4 return"
	echo "		meta nfproto ipv6 ip6 daddr @bypass6 return"
	echo "		meta l4proto { tcp, udp } meta mark set $tproxy_mark tproxy to :$tproxy_port accept"
	echo "	}"
}

write_rules() {
	mkdir -p "$run_dir"
	{
		echo "table inet $table_name {"
		accounting_rules
		tproxy_rules
		echo "}"
	} > "$nft_file"
}

# A rule set built from the downloaded Iran ranges. TProxy mode bypasses them in
# nftables already; TUN mode has no prerouting hook of its own, so sing-box has
# to be told the same ranges.
write_iran_ruleset() {
	local out="$ruleset_dir/iran.json" count
	mkdir -p "$ruleset_dir"
	count=$({ cidr_list /etc/aether/iran4.txt 4; cidr_list /etc/aether/iran6.txt 6; } | wc -l)
	[ "$count" -gt 0 ] || return 1
	{
		printf '{"version":1,"rules":[{"ip_cidr":['
		{ cidr_list /etc/aether/iran4.txt 4; cidr_list /etc/aether/iran6.txt 6; } |
			awk 'BEGIN { sep = "" } { printf "%s\"%s\"", sep, $0; sep = "," }'
		printf ']}]}\n'
	} > "$out"
}

# A downloaded rule set is kept under the name it was fetched as: .srs for the
# compiled form sing-box publishes, .json for a source list someone wrote by hand.
geo_file() {
	local name="$1"
	[ -s "$geo_dir/$name.srs" ] && { printf '%s' "$geo_dir/$name.srs"; return 0; }
	[ -s "$geo_dir/$name.json" ] && { printf '%s' "$geo_dir/$name.json"; return 0; }
	return 1
}

geo_set() {
	local name="$1" path
	path=$(geo_file "$name") || return 1
	case "$path" in
		*.json) printf '{"type":"local","tag":"%s","format":"source","path":"%s"}' "$name" "$path" ;;
		*) printf '{"type":"local","tag":"%s","format":"binary","path":"%s"}' "$name" "$path" ;;
	esac
}

rule_sets() {
	local sets= entry
	if [ "$iran_bypass" = 1 ] && write_iran_ruleset; then
		sets="{\"type\":\"local\",\"tag\":\"iran-ip\",\"format\":\"source\",\"path\":\"$ruleset_dir/iran.json\"}"
	fi
	if [ "$geo_enabled" = 1 ]; then
		entry=$(geo_set geoip-ir) && sets="${sets}${sets:+,}$entry"
		entry=$(geo_set geosite-ir) && sets="${sets}${sets:+,}$entry"
	fi
	if [ "$block_ads" = 1 ]; then
		entry=$(geo_set geosite-ads) && sets="${sets}${sets:+,}$entry"
	fi
	printf '%s' "$sets"
}

# sing-box 1.11 replaced the "block" outbound with a reject action on the rule
# itself, and the outbound goes away for good in 1.13. Both spellings are still
# in the wild, so the installed version decides which one is written.
reject_actions() {
	local version major minor
	# Aether's own core, never whatever sing-box happens to be on PATH: on a
	# router with Passwall2 that one is Passwall2's, and its version is not the
	# version this config will be read by.
	version=$(/usr/libexec/aether/singbox.sh --version 2>/dev/null | cut -d. -f1-2)
	[ -n "$version" ] || return 1
	major=${version%%.*}
	minor=${version#*.}
	[ "$major" -gt 1 ] 2>/dev/null && return 0
	[ "$major" -eq 1 ] 2>/dev/null && [ "$minor" -ge 11 ] 2>/dev/null
}

# One route rule, with the destination written the way this sing-box expects.
route_to() {
	local match="$1" target="$2"
	if [ "$target" = block ]; then
		if reject_actions; then printf '{%s,"action":"reject"}' "$match"
		else printf '{%s,"outbound":"block"}' "$match"; fi
	else
		printf '{%s,"outbound":"%s"}' "$match" "$target"
	fi
}

route_rules() {
	local rules= geo=
	[ "$block_ads" = 1 ] && geo_file geosite-ads >/dev/null &&
		rules=$(route_to '"rule_set":["geosite-ads"]' block)
	if [ "$mode" = tun ]; then
		rules="${rules}${rules:+,}{\"ip_is_private\":true,\"outbound\":\"direct\"}"
		[ "$iran_bypass" = 1 ] && [ -s "$ruleset_dir/iran.json" ] &&
			rules="${rules}${rules:+,}{\"rule_set\":[\"iran-ip\"],\"outbound\":\"direct\"}"
	fi
	if [ "$geo_enabled" = 1 ]; then
		geo_file geoip-ir >/dev/null && geo="\"geoip-ir\""
		geo_file geosite-ir >/dev/null && geo="${geo}${geo:+,}\"geosite-ir\""
		[ -n "$geo" ] && rules="${rules}${rules:+,}$(route_to "\"rule_set\":[$geo]" "$geo_action")"
	fi
	printf '%s' "$rules"
}

# The legacy block outbound is only declared when something still refers to it.
outbounds() {
	local list='{ "type": "socks", "tag": "aether", "server": "'"$socks_address"'", "server_port": '"$socks_port"', "version": "5" }, { "type": "direct", "tag": "direct" }'
	if ! reject_actions && { [ "$block_ads" = 1 ] || [ "$geo_action" = block ]; }; then
		list="$list, { \"type\": \"block\", \"tag\": \"block\" }"
	fi
	printf '%s' "$list"
}

inbound() {
	local addresses
	if [ "$mode" = tun ]; then
		addresses="\"$tun_address\""
		[ -n "$tun_address6" ] && addresses="$addresses,\"$tun_address6\""
		printf '{"type":"tun","tag":"aether-tun","interface_name":"%s","address":[%s],"mtu":%s,"auto_route":true,"strict_route":true,"stack":"system"}' \
			"$tun_name" "$addresses" "$tun_mtu"
	else
		printf '{"type":"tproxy","tag":"aether-tproxy","listen":"::","listen_port":%s}' "$tproxy_port"
	fi
}

write_singbox() {
	local sets rules
	mkdir -p "$run_dir"
	sets=$(rule_sets)
	rules=$(route_rules)
	cat > "$singbox_file" <<EOF
{
  "log": { "level": "$singbox_log", "timestamp": true },
  "inbounds": [$(inbound)],
  "outbounds": [$(outbounds)],
  "route": {
    "auto_detect_interface": true,
    "rule_set": [$sets],
    "rules": [$rules],
    "final": "aether"
  }
}
EOF
	[ -n "$singbox" ] || { echo "no sing-box core for Aether" >&2; return 1; }
	"$singbox" check -c "$singbox_file"
}

start_rules() {
	stop_rules
	write_rules
	# Accounting is a convenience; proxying is not. If an older nftables rejects
	# the counter rules, drop them and put the proxy up regardless.
	if ! nft -c -f "$nft_file" 2>/dev/null; then
		logger -t aether 'traffic accounting rules were rejected; continuing without them'
		accounting=0
		write_rules
	fi
	nft -c -f "$nft_file"
	nft -f "$nft_file"
	[ "$wanted_rules" = all ] && [ "$mode" = tproxy ] || return 0
	# The TProxy mark, not Aether's own: this rule sends whatever carries it to
	# loopback, which is right for intercepted traffic and fatal for the tunnel.
	ip rule add fwmark "$tproxy_mark" lookup "$route_table" priority 100 2>/dev/null || true
	ip route add local 0.0.0.0/0 dev lo table "$route_table" 2>/dev/null || true
	ip -6 rule add fwmark "$tproxy_mark" lookup "$route_table" priority 100 2>/dev/null || true
	ip -6 route add local ::/0 dev lo table "$route_table" 2>/dev/null || true
}

# sing-box installs its own policy routing for the TUN device. Aether marks every
# socket it opens to the internet, so this rule hands those back to the main table
# before sing-box's rules can pull them into the tunnel they came from.
start_tun_escape() {
	ip rule add fwmark "$mark" lookup main priority 50 2>/dev/null || true
	ip -6 rule add fwmark "$mark" lookup main priority 50 2>/dev/null || true
}

stop_tun_escape() {
	while ip rule del fwmark "$mark" lookup main priority 50 2>/dev/null; do :; done
	while ip -6 rule del fwmark "$mark" lookup main priority 50 2>/dev/null; do :; done
}

stop_rules() {
	nft delete table inet "$table_name" 2>/dev/null || true
	if [ -n "${mark:-}" ]; then
		stop_tun_escape
	fi
	if [ -n "${tproxy_mark:-}" ] && [ -n "${route_table:-}" ]; then
		while ip rule del fwmark "$tproxy_mark" lookup "$route_table" priority 100 2>/dev/null; do :; done
		while ip -6 rule del fwmark "$tproxy_mark" lookup "$route_table" priority 100 2>/dev/null; do :; done
		# Older installs put Aether's own mark on this rule; take that out too.
		while ip rule del fwmark "$mark" lookup "$route_table" priority 100 2>/dev/null; do :; done
		while ip -6 rule del fwmark "$mark" lookup "$route_table" priority 100 2>/dev/null; do :; done
		ip route flush table "$route_table" 2>/dev/null || true
		ip -6 route flush table "$route_table" 2>/dev/null || true
	fi
	# Only the nft file. The sing-box config and the rule sets it points at are
	# written by the singbox-config that runs immediately before start_rules, and
	# start_rules calls this first — so removing either here left sing-box being
	# started against files that no longer existed. It died in under a second,
	# procd gave up after five tries, and the redirect rules stayed in front of a
	# port with nothing behind them. Both belong to the explicit stop.
	rm -f "$nft_file"
}

load_config
case "${1:-}" in
	start)
		start_rules
		[ "$mode" = tun ] && start_tun_escape || true
		;;
	accounting)
		wanted_rules=accounting
		[ "$accounting" = 1 ] && start_rules || stop_rules
		;;
	stop) stop_rules; rm -f "$singbox_file"; rm -rf "$ruleset_dir" ;;
	reload)
		start_rules
		[ "$mode" = tun ] && start_tun_escape || true
		;;
	singbox-config) write_singbox ;;
	check) write_singbox; write_rules; nft -c -f "$nft_file" ;;
	*) echo 'Usage: firewall.sh {start|accounting|stop|reload|singbox-config|check}' >&2; exit 2 ;;
esac
