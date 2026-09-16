#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
#
# Gozarbin's own sing-box core, and the daily look for a newer one.
#
# The core is kept at $own, installed from SagerNet's own releases, and it is
# what Gozarbin runs. A sing-box that came from a Passwall feed is never used and
# never upgraded: it belongs to Passwall2, it is the engine Passwall2 is running
# on right now, and replacing it underneath a working setup to satisfy a proxy
# the user may not even have switched on is not ours to do. A sing-box from the
# ordinary OpenWrt feed is nobody's in particular, so that one is borrowed when
# Gozarbin has no core of its own yet.
#
# The version check looks once a day, and only after a hundred megabytes have
# actually gone through the tunnel: a router that has barely passed traffic has
# not earned a request over someone's metered link. It never reports a failure.
# Offline, blocked, between tunnels — all normal here, and none of it is news.

own=/usr/libexec/gozarbin/sing-box
state_dir=/etc/gozarbin/state
state_file="$state_dir/singbox.json"
counter_file="$state_dir/counter"
total_file="$state_dir/downloaded"
checked_file="$state_dir/checked"

threshold=$((100 * 1024 * 1024))
interval=86400
api=https://api.github.com/repos/SagerNet/sing-box/releases/latest
downloads=https://github.com/SagerNet/sing-box/releases/download

. /usr/libexec/gozarbin/packages.sh

# ---------------------------------------------------------------- the core

# Which package a system sing-box came from. apk and opkg both name the feed the
# package was built from, and a Passwall feed says so in that name.
system_origin() {
	command -v sing-box >/dev/null 2>&1 || { echo none; return; }
	pkg_snapshot
	if printf '%s\n' "$PKG_LIST" | grep -i '^sing-box-[0-9]' | grep -qi passwall; then
		echo passwall
	elif command -v opkg >/dev/null 2>&1 &&
		opkg status sing-box 2>/dev/null | grep -qi 'passwall'; then
		echo passwall
	else
		echo system
	fi
}

origin() {
	[ -x "$own" ] && { echo own; return; }
	system_origin
}

# The binary Gozarbin runs, or nothing, which callers must treat as "no core".
path() {
	case "$(origin)" in
		own) printf '%s' "$own" ;;
		system) command -v sing-box ;;
		*) return 1 ;;
	esac
}

version_of() {
	[ -n "$1" ] && [ -x "$1" ] || return 1
	"$1" version 2>/dev/null | sed -n 's/^sing-box version \([0-9][0-9.]*\).*/\1/p' | head -n 1
}

version() {
	local binary
	binary=$(path) || return 1
	version_of "$binary"
}

# ------------------------------------------------------------- downloading

# SagerNet names its release assets by Go's architecture, not OpenWrt's. Several
# spellings can fit one target — a mips build comes in a softfloat flavour as
# well — so each candidate is tried in turn rather than guessed at once.
go_arches() {
	local arch
	arch=$(sed -n "s/^DISTRIB_ARCH='\(.*\)'$/\1/p" /etc/openwrt_release 2>/dev/null | head -n 1)
	[ -n "$arch" ] || arch=$(uname -m)
	case "$arch" in
		x86_64|amd64) echo amd64 ;;
		i386*|i486|i586|i686) echo 386 ;;
		aarch64*|arm64) echo arm64 ;;
		arm_cortex-a7*|arm_cortex-a8*|arm_cortex-a9*|arm_cortex-a15*|arm_cortex-a17*|armv7*) echo armv7 armv6 armv5 ;;
		arm_arm1176*|armv6*) echo armv6 armv5 ;;
		arm_*|armv5*) echo armv5 ;;
		mips64el_*|mips64le) echo mips64le ;;
		mips64_*|mips64) echo mips64 ;;
		mipsel_*|mipsel|mipsle) echo mipsle-softfloat mipsle ;;
		mips_*|mips) echo mips-softfloat mips ;;
		riscv64*) echo riscv64 ;;
		loongarch64*) echo loong64 ;;
		*) echo "$arch" ;;
	esac
}

free_kb() { df -k "$1" 2>/dev/null | awk 'NR == 2 { print $4 }'; }

install_version() {
	local wanted work asset url goarch found extracted
	wanted="$1"
	[ -n "$wanted" ] || wanted=$(latest_stable) || {
		echo 'Could not find out which version is current.' >&2; return 1; }
	wanted=${wanted#v}

	# SagerNet's own build is unstripped and around seventy megabytes, and the
	# tarball sits beside it while it is unpacked. Unpacking happens next to the
	# destination, not in /tmp: /tmp is a tmpfs, so a router with 512 MB of RAM
	# would be spending a fifth of it on a file that is about to be moved one
	# directory across. Same filesystem also makes that move a rename.
	work="$(dirname "$own")/.work"
	rm -rf "$work"
	mkdir -p "$work" || return 1
	# shellcheck disable=SC2064
	trap "rm -rf '$work'" EXIT
	[ "$(free_kb "$work")" -ge 153600 ] 2>/dev/null || {
		echo 'Not enough free space for a sing-box core: 150 MB is needed to unpack one.' >&2
		echo 'On a router this small, install the sing-box package from the OpenWrt feed instead.' >&2
		return 1; }
	found=
	for goarch in $(go_arches); do
		asset="sing-box-$wanted-linux-$goarch.tar.gz"
		url="$downloads/v$wanted/$asset"
		echo "Trying $asset"
		uclient-fetch -q -T 120 -O "$work/core.tar.gz" "$url" 2>/dev/null || continue
		[ -s "$work/core.tar.gz" ] || continue
		tar -xzf "$work/core.tar.gz" -C "$work" 2>/dev/null || continue
		extracted=$(find "$work" -type f -name sing-box | head -n 1)
		[ -n "$extracted" ] || continue
		chmod 0755 "$extracted"
		# A binary for the wrong architecture downloads perfectly well and then
		# cannot run, so it only counts once it has answered a question.
		version_of "$extracted" >/dev/null || { echo "  not runnable on this router"; continue; }
		found="$extracted"
		break
	done
	[ -n "$found" ] || { echo "No sing-box $wanted build fits this router." >&2; return 1; }

	mv "$found" "$own.new"
	# The tarball carries SagerNet's build uid; on this router it is just a number.
	chown 0:0 "$own.new" 2>/dev/null || true
	chmod 0755 "$own.new"
	mv "$own.new" "$own"
	rm -rf "$work"
	rm -f "$state_file" "$checked_file"
	echo "Installed sing-box $(version_of "$own") for Gozarbin at $own ($(( $(wc -c < "$own") / 1048576 )) MB)"
	[ "$(uci -q get gozarbin.main.enabled)" = 1 ] && /etc/init.d/gozarbin restart >/dev/null 2>&1
	return 0
}

# --------------------------------------------------------- the daily check

read_number() { [ -r "$1" ] && head -n 1 "$1" 2>/dev/null | grep -E '^[0-9]+$' || echo 0; }

# The nftables counters start again from zero whenever the firewall rules are
# rebuilt, so a reading below the last one is a restart, not a negative delta.
sample() {
	local current previous total
	mkdir -p "$state_dir"
	current=$(/usr/libexec/gozarbin/traffic.sh 2>/dev/null |
		sed -n 's/.*"download":\([0-9]*\).*/\1/p')
	[ -n "$current" ] || return 0
	previous=$(read_number "$counter_file")
	total=$(read_number "$total_file")
	if [ "$current" -ge "$previous" ]; then
		total=$((total + current - previous))
	else
		total=$((total + current))
	fi
	echo "$current" > "$counter_file"
	echo "$total" > "$total_file"
}

downloaded() { read_number "$total_file"; }

# 1.14.0-r1 and v1.14.1 both reduce to three numbers, which is all that is being
# compared. Succeeds when the first argument is the older one.
older_than() {
	local a b i field_a field_b
	a=$(printf '%s' "$1" | sed 's/^v//; s/-.*//')
	b=$(printf '%s' "$2" | sed 's/^v//; s/-.*//')
	i=1
	while [ "$i" -le 3 ]; do
		field_a=$(printf '%s' "$a" | cut -d. -f"$i")
		field_b=$(printf '%s' "$b" | cut -d. -f"$i")
		[ -n "$field_a" ] || field_a=0
		[ -n "$field_b" ] || field_b=0
		[ "$field_a" -lt "$field_b" ] 2>/dev/null && return 0
		[ "$field_a" -gt "$field_b" ] 2>/dev/null && return 1
		i=$((i + 1))
	done
	return 1
}

# releases/latest is the newest non-prerelease by definition, which is exactly
# the "stable" being offered to the user.
latest_stable() {
	local body found
	body=$(uclient-fetch -q -T 20 -O - "$api" 2>/dev/null) || return 1
	found=$(printf '%s' "$body" |
		sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\{0,1\}\([0-9][0-9.]*\)".*/\1/p' | head -n 1)
	printf '%s' "$found" | grep -qE '^[0-9]+\.[0-9]+(\.[0-9]+)?$' || return 1
	printf '%s' "$found"
}

write_state() {
	mkdir -p "$state_dir"
	printf '{"origin":"%s","installed":"%s","latest":"%s","update":%s,"checked":%s,"downloaded":%s}\n' \
		"$(origin)" "$1" "$2" "$3" "$(date +%s)" "$(downloaded)" > "$state_file"
}

check() {
	local installed latest
	sample
	[ "$(downloaded)" -ge "$threshold" ] || return 0
	[ $(( $(date +%s) - $(read_number "$checked_file") )) -ge "$interval" ] || return 0
	installed=$(version) || return 0
	[ -n "$installed" ] || return 0
	latest=$(latest_stable) || return 0
	# Only a look that got an answer counts as a look; a failed one is retried.
	date +%s > "$checked_file"
	if older_than "$installed" "$latest"; then
		write_state "$installed" "$latest" true
	else
		write_state "$installed" "$latest" false
	fi
}

state() {
	if [ -r "$state_file" ]; then
		cat "$state_file"
	else
		printf '{"origin":"%s","installed":"%s","latest":"","update":false,"checked":0,"downloaded":%s}\n' \
			"$(origin)" "$(version 2>/dev/null)" "$(downloaded)"
	fi
}

case "${1:-}" in
	--path) path ;;
	--origin) origin ;;
	--version) version ;;
	--sample) sample ;;
	--check) check ;;
	--state) state ;;
	--install) install_version "$2" ;;
	--reset) rm -f "$state_file" "$checked_file" "$counter_file" "$total_file" ;;
	*)
		echo 'Usage: singbox.sh {--path|--origin|--version|--state|--check|--sample|--install [version]|--reset}' >&2
		exit 2
		;;
esac
