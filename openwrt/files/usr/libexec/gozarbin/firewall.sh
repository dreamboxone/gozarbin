#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone

set -e
. /lib/functions.sh

run_dir=/var/run/gozarbin
nft_file="$run_dir/gozarbin.nft"
singbox_file="$run_dir/sing-box.json"
ruleset_dir="$run_dir/rulesets"
geo_dir=/etc/gozarbin/geo
table_name=gozarbin_proxy
singbox=$(/usr/libexec/gozarbin/singbox.sh --path 2>/dev/null)

# "all" builds the table transparent mode needs; "accounting" builds only the
# byte counters. The second is what runs when transparent mode stands down —
# for Passwall2, for a missing dependency, or because the mode is SOCKS5-only —
# so the page still reports what left through the proxy without this touching
# anybody else's prerouting rules.
wanted_rules=all

load_config() {
	config_load gozarbin
	config_get mode main mode tproxy
	config_get mark main mark 0x0aff
	config_get route_table main route_table 103
	config_get socks_address main socks_address 127.0.0.1
	config_get socks_port main socks_port 1819
	config_get tproxy_port main tproxy_port 1821
	config_get tproxy_mark main tproxy_mark 0x0a38
	config_get tun_name main tun_name gozarbin-tun
	config_get tun_address main tun_address 172.19.0.1/30
	config_get tun_address6 main tun_address6 'fdfe:dcba:9876::1/126'
	config_get tun_mtu main tun_mtu 9000
	config_get singbox_log main singbox_log_level warn
	config_get ip_mode main ip_mode v4
	config_get dns_port main dns_port 1822
	config_get dns_server main dns_server 1.1.1.1
	config_get_bool accounting main accounting 1
	config_get_bool geo_enabled main geo_enabled 1
	config_get iran_dns_server main iran_dns_server ''
	iran_domains=
	config_list_foreach main iran_domain add_iran_domain
	[ -n "$iran_domains" ] || iran_domains='"bale.ai","eitaa.com","ir"'
	config_get_bool block_ads main block_ads 0
	config_get_bool unblock main unblock 0
	config_get unblock_port main unblock_port 1823
	lan_interfaces=
	config_list_foreach main lan_interface add_lan
	[ -n "$lan_interfaces" ] || lan_interfaces='"br-lan"'
	unblock_domains=
	config_list_foreach main unblock_domain add_unblock
	[ -n "$unblock_domains" ] || unblock=0
}

# A domain name and nothing else: it goes into JSON unescaped.
add_unblock() {
	case "$1" in
		''|*[!A-Za-z0-9.-]*) return 0 ;;
	esac
	unblock_domains="${unblock_domains}${unblock_domains:+,}\"${1#.}\""
}

add_iran_domain() {
	case "$1" in
		''|*[!A-Za-z0-9.-]*) return 0 ;;
	esac
	iran_domains="${iran_domains}${iran_domains:+,}\"${1#.}\""
}

# What the counters watch: the core's SOCKS port, and the non-Iranian exit's
# too when there is one, since that traffic leaves through a tunnel as well.
proxy_ports() {
	if [ "$unblock" = 1 ]; then
		printf '{ %s, %s }' "$socks_port" "$unblock_port"
	else
		printf '%s' "$socks_port"
	fi
}

add_lan() {
	local escaped
	escaped=$(printf '%s' "$1" | sed 's/["\\]/\\&/g')
	lan_interfaces="${lan_interfaces}${lan_interfaces:+, }\"${escaped}\""
}

# A downloaded rule set is kept under the name it was fetched as: .srs for the
# compiled form sing-box publishes, .json for a source list someone wrote by hand.
geo_file() {
	local name="$1"
	[ -s "$geo_dir/$name.srs" ] && { printf '%s' "$geo_dir/$name.srs"; return 0; }
	[ -s "$geo_dir/$name.json" ] && { printf '%s' "$geo_dir/$name.json"; return 0; }
	return 1
}

# The Iranian address ranges, for nftables. There is one source for them, the
# GeoIP rule set, and it is used twice: here, so traffic to an Iranian address
# is turned back in the kernel before sing-box ever sees it, and in sing-box's
# own rules, which also know Iranian domain names. nftables wants the ranges
# spelt out and the rule set is compiled, so sing-box decompiles it first — the
# two cannot disagree about what counts as Iranian when they read the same file.
iran_ranges() {
	local family="$1" source
	[ "$geo_enabled" = 1 ] || return 0
	source=$(geo_file geoip-ir) || return 0
	case "$source" in
		*.srs)
			[ -n "$singbox" ] || return 0
			mkdir -p "$ruleset_dir"
			"$singbox" rule-set decompile -o "$ruleset_dir/geoip-ir.json" "$source" >/dev/null 2>&1 || return 0
			source="$ruleset_dir/geoip-ir.json"
			;;
	esac
	if [ "$family" = 4 ]; then
		grep -oE '"[0-9]+[.][0-9]+[.][0-9]+[.][0-9]+/[0-9]+"' "$source" || true
	else
		grep -oE '"[0-9a-fA-F]*:[0-9a-fA-F:]*/[0-9]+"' "$source" || true
	fi | tr -d '"' | awk 'BEGIN { sep = "" } { printf "%s%s", sep, $0; sep = "," } END { print "" }'
}

# Both counters sit on the hop between sing-box (or any other SOCKS5 client) and
# the Gozarbin proxy, so they measure what really left through the tunnel in either
# mode, and they keep counting for clients that speak SOCKS5 directly.
accounting_rules() {
	local ports
	[ "$accounting" = 1 ] || return 0
	ports=$(proxy_ports)
	# Written the way nft dumps a counter object, so the file reloads verbatim.
	echo "	counter upload {"
	echo "		packets 0 bytes 0"
	echo "	}"
	echo "	counter download {"
	echo "		packets 0 bytes 0"
	echo "	}"
	echo "	chain accounting_output {"
	echo "		type filter hook output priority filter; policy accept;"
	echo "		oifname \"lo\" meta l4proto { tcp, udp } th dport $ports counter name \"upload\""
	echo "		oifname \"lo\" meta l4proto { tcp, udp } th sport $ports counter name \"download\""
	echo "		oifname != \"lo\" meta l4proto { tcp, udp } th sport $ports counter name \"download\""
	echo "	}"
	echo "	chain accounting_input {"
	echo "		type filter hook input priority filter; policy accept;"
	echo "		iifname != \"lo\" meta l4proto { tcp, udp } th dport $ports counter name \"upload\""
	echo "	}"
}

tproxy_rules() {
	local iran4 iran6
	[ "$wanted_rules" = all ] || return 0
	[ "$mode" = tproxy ] || return 0
	iran4=$(iran_ranges 4)
	iran6=$(iran_ranges 6)
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
	if [ "$geo_enabled" = 1 ]; then
		entry=$(geo_set geoip-ir) && sets="${sets}${sets:+,}$entry"
		entry=$(geo_set geosite-ir) && sets="${sets}${sets:+,}$entry"
	fi
	if [ "$block_ads" = 1 ]; then
		entry=$(geo_set geosite-ads) && sets="${sets}${sets:+,}$entry"
	fi
	printf '%s' "$sets"
}

route_rules() {
	local rules= geo=
	# DNS first, and before sniffing: queries dnsmasq forwards to the DNS
	# listener are DNS by definition and need no looking at.
	[ "$mode" = tproxy ] &&
		rules="{\"inbound\":[\"gozarbin-dns\"],\"action\":\"hijack-dns\"}"
	# Without this sing-box only ever sees an address, never a name. Every
	# GeoSite rule and the whole ad list match on names, so none of them matched
	# anything: sniffing reads the name out of the TLS handshake or the HTTP
	# request, and out of a DNS query, which is how the next rule finds those.
	rules="${rules}${rules:+,}{\"action\":\"sniff\"}"
	# A device with a resolver of its own — a TV asking 8.8.8.8 — gets its
	# answer from the tunnel as well, not from the filter sitting on port 53.
	rules="${rules},{\"protocol\":\"dns\",\"action\":\"hijack-dns\"}"
	# Keep essential domestic services ahead of optional ad lists and stale
	# GeoSite data. Reverse DNS mapping below covers apps without a sniffable SNI.
	[ "$geo_enabled" = 1 ] &&
		rules="${rules},{\"domain_suffix\":[$iran_domains],\"outbound\":\"direct\"}"
	[ "$block_ads" = 1 ] && geo_file geosite-ads >/dev/null &&
		rules="${rules},{\"rule_set\":[\"geosite-ads\"],\"action\":\"reject\"}"
	rules="${rules},{\"ip_is_private\":true,\"outbound\":\"direct\"}"
	# Services that refuse Iran, to the WARP connection that starts from a Tor
	# exit. With no fallback: while that connection is still coming up these
	# sites fail, rather than reaching the service from Iran after all.
	[ "$unblock" = 1 ] &&
		rules="${rules},{\"domain_suffix\":[$unblock_domains],\"outbound\":\"unblock\"}"
	if [ "$geo_enabled" = 1 ]; then
		geo_file geoip-ir >/dev/null && geo="\"geoip-ir\""
		geo_file geosite-ir >/dev/null && geo="${geo}${geo:+,}\"geosite-ir\""
		[ -n "$geo" ] && rules="${rules},{\"rule_set\":[$geo],\"outbound\":\"direct\"}"
	fi
	printf '%s' "$rules"
}

outbounds() {
	printf '%s' '{ "type": "socks", "tag": "gozarbin", "server": "'"$socks_address"'", "server_port": '"$socks_port"', "version": "5" }, { "type": "direct", "tag": "direct" }'
	if [ "$unblock" = 1 ]; then
		printf ', { "type": "socks", "tag": "unblock", "server": "127.0.0.1", "server_port": %s, "version": "5" }' "$unblock_port"
	fi
	return 0
}

inbound() {
	local addresses
	if [ "$mode" = tun ]; then
		addresses="\"$tun_address\""
		[ -n "$tun_address6" ] && addresses="$addresses,\"$tun_address6\""
		printf '{"type":"tun","tag":"gozarbin-tun","interface_name":"%s","address":[%s],"mtu":%s,"auto_route":true,"strict_route":true,"stack":"system"}' \
			"$tun_name" "$addresses" "$tun_mtu"
	else
		printf '{"type":"tproxy","tag":"gozarbin-tproxy","listen":"::","listen_port":%s},' "$tproxy_port"
		printf '{"type":"direct","tag":"gozarbin-dns","listen":"127.0.0.1","listen_port":%s}' "$dns_port"
	fi
}

# The resolver the WAN handed out, used for Iranian names only. Never the
# router's own 127.0.0.1: while transparent mode is up that is dnsmasq, dnsmasq
# forwards to sing-box, and sing-box would be asking itself.
wan_dns() {
	local file found
	for file in /tmp/resolv.conf.d/resolv.conf.auto /tmp/resolv.conf.auto; do
		[ -r "$file" ] || continue
		found=$(awk '$1 == "nameserver" && $2 ~ /^[0-9.]+$/ && $2 !~ /^127[.]/ { print $2; exit }' "$file")
		[ -n "$found" ] && { printf '%s' "$found"; return 0; }
	done
	return 1
}

# Names go out through the tunnel, as DNS-over-HTTPS, so nothing on the path can
# answer in the resolver's place. Iranian names are the exception: asked through
# the tunnel they would resolve from abroad, to servers abroad or to none at
# all, so those go to the ISP's resolver like they always did.
dns_section() {
	local servers rules= iran strategy
	servers="{\"type\":\"https\",\"tag\":\"remote\",\"server\":\"$dns_server\",\"detour\":\"gozarbin\"}"
	iran=$iran_dns_server
	[ -n "$iran" ] || iran=$(wan_dns) || true
	if [ "$geo_enabled" = 1 ] && [ -n "$iran" ]; then
		servers="${servers},{\"type\":\"udp\",\"tag\":\"iran\",\"server\":\"$iran\"}"
		rules="{\"domain_suffix\":[$iran_domains],\"server\":\"iran\"}"
		geo_file geosite-ir >/dev/null &&
			rules="${rules},{\"rule_set\":[\"geosite-ir\"],\"server\":\"iran\"}"
	fi
	# The tunnel carries what the core was told to carry. Handing out addresses
	# of the other family only gives devices something to try and time out on.
	case "$ip_mode" in
		v4) strategy=ipv4_only ;;
		v6) strategy=ipv6_only ;;
		*) strategy=prefer_ipv4 ;;
	esac
	printf '{ "servers": [%s], "rules": [%s], "final": "remote", "strategy": "%s", "reverse_mapping": true }' \
		"$servers" "$rules" "$strategy"
}

write_singbox() {
	local sets rules
	mkdir -p "$run_dir"
	sets=$(rule_sets)
	rules=$(route_rules)
	cat > "$singbox_file" <<EOF
{
  "log": { "level": "$singbox_log", "timestamp": true },
  "dns": $(dns_section),
  "inbounds": [$(inbound)],
  "outbounds": [$(outbounds)],
  "route": {
    "auto_detect_interface": true,
    "default_domain_resolver": "remote",
    "rule_set": [$sets],
    "rules": [$rules],
    "final": "gozarbin"
  }
}
EOF
	[ -n "$singbox" ] || { echo "no sing-box core for Gozarbin" >&2; return 1; }
	"$singbox" check -c "$singbox_file"
}

start_rules() {
	stop_rules
	write_rules
	# Accounting is a convenience; proxying is not. If an older nftables rejects
	# the counter rules, drop them and put the proxy up regardless.
	if ! nft -c -f "$nft_file" 2>/dev/null; then
		logger -t gozarbin 'traffic accounting rules were rejected; continuing without them'
		accounting=0
		write_rules
	fi
	nft -c -f "$nft_file"
	nft -f "$nft_file"
	[ "$wanted_rules" = all ] && [ "$mode" = tproxy ] || return 0
	# The TProxy mark, not Gozarbin's own: this rule sends whatever carries it to
	# loopback, which is right for intercepted traffic and fatal for the tunnel.
	ip rule add fwmark "$tproxy_mark" lookup "$route_table" priority 100 2>/dev/null || true
	ip route add local 0.0.0.0/0 dev lo table "$route_table" 2>/dev/null || true
	ip -6 rule add fwmark "$tproxy_mark" lookup "$route_table" priority 100 2>/dev/null || true
	ip -6 route add local ::/0 dev lo table "$route_table" 2>/dev/null || true
}

# sing-box installs its own policy routing for the TUN device. Gozarbin marks every
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
		# Older installs put Gozarbin's own mark on this rule; take that out too.
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
