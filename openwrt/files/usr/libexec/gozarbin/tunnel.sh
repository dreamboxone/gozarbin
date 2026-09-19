#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
#
# What the tunnel is doing: which server it is on, how that server was chosen,
# and whether a scan is running right now.
#
# This is the part the settings page had nothing to say about, which is why a
# working tunnel looked like a program that does nothing. Gozarbin has no status
# socket, so the answer is read from the two places it does leave one: the
# last-connection file it keeps beside the identity, and its own log since the
# most recent start.

# Not the non-Iranian exit's note: that core keeps its own, and this reports the
# main tunnel.
lastconn=$(ls /etc/gozarbin/*lastconn*.toml 2>/dev/null | grep -v '/unblock' | head -n 1)
peer=
profile=
if [ -n "$lastconn" ]; then
	peer=$(sed -n 's/^peer[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$lastconn" | head -n 1)
	profile=$(sed -n 's/^profile[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$lastconn" | head -n 1)
fi

# Everything below comes from the log since the last start, so a previous run's
# outcome is never reported as this one's.
# The exit core logs as gozarbin-unblock, which the pattern also matches; its own
# scans and starts would otherwise read as the main tunnel's.
report=$(logread -e gozarbin 2>/dev/null | grep -v 'gozarbin-unblock[[]' | awk '
	/Aether v/ { state = "starting"; source = ""; gateway = ""; transport = ""; rtt = ""; detail = ""; fails = 0 }
	/hunting for a working MASQUE gateway/ { state = "scanning"; source = "scan" }
	/scan mode=/ { state = "scanning"; source = "scan" }
	/verifying cached (gateway|WireGuard endpoint)/ { state = "verifying"; source = "cache" }
	/cached gateway .* still works; skipping scan/ { source = "cache" }
	/cached gateway .* no longer works; scanning fresh/ { state = "scanning"; source = "scan" }
	/last known-good endpoint .* no longer responds/ { state = "scanning"; source = "scan" }
	/retrying last known-good gateway/ { state = "verifying"; source = "cache" }
	/selected (MASQUE|WireGuard) gateway|best gateway|using cloudflare edge/ {
		for (i = 1; i <= NF; i++)
			if ($i ~ /^[0-9a-fA-F.:\[\]]+:[0-9]+$/) gateway = $i
		for (i = 1; i <= NF; i++)
			if ($i ~ /^rtt/) { rtt = $(i + 0); sub(/^rtt=?/, "", rtt); if (rtt == "") rtt = $(i + 1) }
	}
	/MASQUE transport:/ {
		p = index($0, "MASQUE transport:")
		transport = substr($0, p + 18)
		sub(/ to .*/, "", transport)
	}
	# A scan that ran out of time still connects on the best candidate it found,
	# so reaching the deadline stops being the story once the tunnel is up.
	/tunnel validated .*exposing socks5/ { state = "connected"; detail = "" }
	/socks5 server listening on/ { state = "connected"; detail = "" }
	# A failed sweep is followed straight away by another one, so without counting
	# them the page shows a scan permanently in progress and never says that the
	# same scan has already failed twenty times over.
	/no usable (MASQUE|WireGuard|WARP) (gateway|endpoint) found|no clean endpoint found/ {
		state = "failed"; detail = "no-gateway"; fails = fails + 1
	}
	/scan deadline reached/ { detail = "deadline" }
	END {
		# Scanning again after a failure is retrying, not a first attempt.
		if (state == "scanning" && fails > 0) state = "retrying"
		printf "state=%s\nsource=%s\ngateway=%s\ntransport=%s\nrtt=%s\ndetail=%s\nfails=%d\n",
			state, source, gateway, transport, rtt, detail, fails
	}
')

state=; source=; gateway=; transport=; rtt=; detail=; fails=0
# Read line by line, not word by word: a transport is "HTTP/3 (QUIC)" and word
# splitting drops half of it.
while IFS= read -r line; do
	case "$line" in
		state=*) state=${line#*=} ;;
		source=*) source=${line#*=} ;;
		gateway=*) gateway=${line#*=} ;;
		transport=*) transport=${line#*=} ;;
		rtt=*) rtt=${line#*=} ;;
		detail=*) detail=${line#*=} ;;
		fails=*) fails=${line#*=} ;;
	esac
done <<REPORT
$report
REPORT

# A log that has rotated past the last start leaves nothing to read; the running
# process and the SOCKS5 listener still answer the question.
if [ -z "$state" ]; then
	if pidof gozarbin >/dev/null 2>&1; then
		netstat -ln 2>/dev/null | grep -q ":$(uci -q get gozarbin.main.socks_port || echo 1819) " &&
			state=connected || state=starting
	else
		state=stopped
	fi
fi
pidof gozarbin >/dev/null 2>&1 || state=stopped

# The gateway the log named beats the cached one: it is this run's.
[ -n "$gateway" ] || gateway="$peer"

# Cloudflare's edge addresses are anycast, so an IP geolocation result would be
# misleading. Ask through the established SOCKS proxy instead: the trace tells
# us the actual WARP exit country and colo. Cache it so dashboard polling does
# not create a new request every few seconds.
country=
exit_cache=/var/run/gozarbin/exit-location
if [ "$state" = connected ] && command -v curl >/dev/null 2>&1; then
	now=$(date +%s 2>/dev/null)
	then=$(stat -c %Y "$exit_cache" 2>/dev/null)
	if [ -n "$now" ] && [ -n "$then" ] && [ $((now - then)) -lt 60 ] 2>/dev/null; then
		. "$exit_cache" 2>/dev/null
	else
		trace=$(timeout 5 curl -fsS -x "socks5h://127.0.0.1:$(uci -q get gozarbin.main.socks_port || echo 1819)" \
			'https://www.cloudflare.com/cdn-cgi/trace' 2>/dev/null)
		country=$(printf '%s\n' "$trace" | sed -n 's/^loc=\([A-Z][A-Z]\)$/\1/p' | head -n 1)
		if [ -n "$country" ]; then
			( umask 077; printf 'country=%s\n' "$country" > "$exit_cache" )
		fi
	fi
fi

quoteless() { printf '%s' "$1" | tr -d '"\\'; }

protocol=$(uci -q get gozarbin.main.protocol)
[ -n "$protocol" ] || protocol=masque
[ "$fails" -ge 0 ] 2>/dev/null || fails=0

printf '{"state":"%s","source":"%s","gateway":"%s","profile":"%s","transport":"%s","rtt":"%s","country":"%s","detail":"%s","fails":%s,"protocol":"%s","cached":"%s"}\n' \
	"$(quoteless "$state")" "$(quoteless "$source")" "$(quoteless "$gateway")" \
	"$(quoteless "$profile")" "$(quoteless "$transport")" "$(quoteless "$rtt")" \
	"$(quoteless "$country")" "$(quoteless "$detail")" \
	"$fails" "$(quoteless "$protocol")" "$(quoteless "$peer")"
