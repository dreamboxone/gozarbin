#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
#
# What the tunnel is doing: which server it is on, how that server was chosen,
# and whether a scan is running right now.
#
# This is the part the settings page had nothing to say about, which is why a
# working tunnel looked like a program that does nothing. Aether has no status
# socket, so the answer is read from the two places it does leave one: the
# last-connection file it keeps beside the identity, and its own log since the
# most recent start.

lastconn=$(ls /etc/aether/*lastconn*.toml 2>/dev/null | head -n 1)
peer=
profile=
if [ -n "$lastconn" ]; then
	peer=$(sed -n 's/^peer[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$lastconn" | head -n 1)
	profile=$(sed -n 's/^profile[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$lastconn" | head -n 1)
fi

# Everything below comes from the log since the last start, so a previous run's
# outcome is never reported as this one's.
report=$(logread -e aether 2>/dev/null | awk '
	/Aether v/ { state = "starting"; source = ""; gateway = ""; transport = ""; rtt = ""; detail = "" }
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
	/no usable (MASQUE|WireGuard|WARP) (gateway|endpoint) found/ { state = "failed"; detail = "no-gateway" }
	/scan deadline reached/ { state = "failed"; detail = "deadline" }
	END {
		printf "state=%s\nsource=%s\ngateway=%s\ntransport=%s\nrtt=%s\ndetail=%s\n",
			state, source, gateway, transport, rtt, detail
	}
')

state=; source=; gateway=; transport=; rtt=; detail=
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
	esac
done <<REPORT
$report
REPORT

# A log that has rotated past the last start leaves nothing to read; the running
# process and the SOCKS5 listener still answer the question.
if [ -z "$state" ]; then
	if pidof aether >/dev/null 2>&1; then
		netstat -ln 2>/dev/null | grep -q ":$(uci -q get aether.main.socks_port || echo 1819) " &&
			state=connected || state=starting
	else
		state=stopped
	fi
fi
pidof aether >/dev/null 2>&1 || state=stopped

# The gateway the log named beats the cached one: it is this run's.
[ -n "$gateway" ] || gateway="$peer"

quoteless() { printf '%s' "$1" | tr -d '"\\'; }

printf '{"state":"%s","source":"%s","gateway":"%s","profile":"%s","transport":"%s","rtt":"%s","detail":"%s","cached":"%s"}\n' \
	"$(quoteless "$state")" "$(quoteless "$source")" "$(quoteless "$gateway")" \
	"$(quoteless "$profile")" "$(quoteless "$transport")" "$(quoteless "$rtt")" \
	"$(quoteless "$detail")" "$(quoteless "$peer")"
