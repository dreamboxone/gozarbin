#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
set -eu

LIB=${GOZARBIN_LIB:-/usr/libexec/gozarbin}
PROVIDER=${GOZARBIN_CORE_PROVIDER:-aether}
case "$PROVIDER" in
	aether) REPO=CluvexStudio/Aether; BIN_NAME=gozarbin; DEFAULT_BUNDLE=/usr/libexec/gozarbin/cores/aether/bundled/gozarbin
		[ -x "$DEFAULT_BUNDLE" ] || DEFAULT_BUNDLE=/usr/bin/gozarbin ;;
	singbox) REPO=SagerNet/sing-box; BIN_NAME=sing-box; DEFAULT_BUNDLE=/usr/libexec/gozarbin/cores/singbox/bundled/sing-box
		[ -x "$DEFAULT_BUNDLE" ] || DEFAULT_BUNDLE=/usr/libexec/gozarbin/sing-box ;;
	*) exit 2 ;;
esac
ROOT=${GOZARBIN_CORE_ROOT:-/usr/libexec/gozarbin/cores/$PROVIDER}
RUN=${GOZARBIN_CORE_RUN:-/var/run/gozarbin-$PROVIDER}
BUNDLED=${GOZARBIN_BUNDLED_CORE:-$DEFAULT_BUNDLE}
SERVICE=${GOZARBIN_CORE_SERVICE:-/etc/init.d/gozarbin}
SCHEMA=${GOZARBIN_CORE_SCHEMA:-/usr/share/gozarbin/core-options.json}
API=https://api.github.com/repos/$REPO/releases?per_page=20
BASE=https://github.com/$REPO/releases/download
mkdir -p "$RUN"
MAINTENANCE=/var/run/gozarbin-maintenance.lock
release_guard() {
	[ "$(cat "$MAINTENANCE/owner" 2>/dev/null || true)" = "$RUN" ] || return 0
	rm -f "$MAINTENANCE/owner"
	rmdir "$MAINTENANCE" 2>/dev/null || true
}
claim_guard() {
	mkdir "$MAINTENANCE" 2>/dev/null || return 1
	printf '%s' "$RUN" > "$MAINTENANCE/owner"
}

bounded_run() {
	local limit=$1 result=0
	shift
	"$@" &
	registration_pid=$!
	(
		sleep "$limit" &
		timer=$!
		trap 'kill "$timer" 2>/dev/null || true; exit 0' TERM INT HUP
		wait "$timer" || exit 0
		kill -TERM "$registration_pid" 2>/dev/null || exit 0
		sleep 2
		kill -KILL "$registration_pid" 2>/dev/null || true
	) &
	registration_watchdog=$!
	wait "$registration_pid" || result=$?
	kill "$registration_watchdog" 2>/dev/null || true
	wait "$registration_watchdog" 2>/dev/null || true
	registration_pid= registration_watchdog=
	return "$result"
}

core_path() {
	if [ -x "$ROOT/current/$BIN_NAME" ]; then printf '%s\n' "$ROOT/current/$BIN_NAME"; else printf '%s\n' "$BUNDLED"; fi
}
core_version() {
	local binary identity found cached
	binary=$(core_path)
	identity=$(stat -L -c '%i:%s:%Y' "$binary" 2>/dev/null || true)
	[ -n "$identity" ] || identity=$(LC_ALL=C ls -L -lni "$binary" 2>/dev/null || true)
	if [ -n "$identity" ] && [ -r "$RUN/version.cache" ]; then
		cached=$(head -n 1 "$RUN/version.cache")
		if [ "$cached" = "$binary:$identity" ]; then sed -n '2p' "$RUN/version.cache"; return; fi
	fi
	if [ "$PROVIDER" = singbox ]; then
		found=$("$binary" version 2>/dev/null | sed -n 's/^sing-box version \([^ ]*\).*/\1/p' | head -n 1)
	elif [ "$binary" = "$BUNDLED" ] && [ -r /usr/share/gozarbin/aether-upstream-version ]; then
		found=$(cat /usr/share/gozarbin/aether-upstream-version)
	else
		found=$("$binary" --version 2>/dev/null | sed -n 's/^[Aa]ether v\{0,1\}\([^ ]*\).*/\1/p' | head -n 1)
	fi
	if [ -n "$identity" ] && [ -n "$found" ]; then
		printf '%s\n%s\n' "$binary:$identity" "$found" > "$RUN/version.cache.$$"
		mv -f "$RUN/version.cache.$$" "$RUN/version.cache"
	fi
	printf '%s\n' "$found"
}
origin() { if [ -x "$ROOT/current/$BIN_NAME" ]; then echo upstream; else echo bundled; fi; }
asset_name() {
	local arch
	arch=${GOZARBIN_CORE_ARCH:-$(uname -m)}
	if [ "$PROVIDER" = singbox ]; then
		case "$arch" in
			armv7*|arm_cortex-a[5789]*|arm_cortex-a1*) arch=armv7 ;;
			armv6*|arm_arm1176*) arch=armv6 ;;
			armv5*|arm_*) arch=armv5 ;;
			aarch64*|arm64) arch=arm64 ;;
			x86_64|amd64) arch=amd64 ;;
			i?86) arch=386 ;;
			mipsel*|mipsle) arch=mipsle-softfloat ;;
			mips*) arch=mips-softfloat ;;
			riscv64*) arch=riscv64 ;;
			*) return 1 ;;
		esac
		echo "sing-box-${latest:-}-linux-$arch.tar.gz"; return
	fi
	case "$arch" in
		armv7*|arm_cortex-a[5789]*|arm_cortex-a1*) echo aether-linux-armv7-musl.tar.gz ;;
		aarch64*|arm64) echo aether-linux-aarch64-musl.tar.gz ;;
		x86_64|amd64) echo aether-linux-x86_64-musl.tar.gz ;;
		*) return 1 ;;
	esac
}
valid_version() { printf '%s\n' "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$'; }
valid_tag() { case "$1" in v*) valid_version "${1#v}" ;; *) return 1 ;; esac; }
newer() {
	local old_base=${1%%-*} new_base=${2%%-*}
	if [ "$old_base" = "$new_base" ]; then
		case "$1:$2" in *-*:*-*) ;; *-*:*) return 0 ;; *:*-*) return 1 ;; esac
	fi
	[ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)" = "$2" ]
}
emit() {
	local latest current percent downloaded total binary folder prerelease
	latest=$(cat "$RUN/latest" 2>/dev/null || true)
	current=$(core_version || true)
	binary=$(core_path); folder=${binary%/*}
	prerelease=$(cat "$RUN/prerelease" 2>/dev/null || true)
	[ "$prerelease" = true ] || prerelease=false
	percent=${3:-0}; downloaded=0; total=$(cat "$RUN/total" 2>/dev/null || echo 0)
	if [ "$1" = downloading ] && [ -r "$RUN/download-path" ]; then
		downloaded=$(wc -c < "$(cat "$RUN/download-path").part" 2>/dev/null || echo 0)
		if [ "$total" -gt 0 ]; then percent=$((downloaded * 100 / total)); [ "$percent" -le 99 ] || percent=99; fi
	fi
	printf '{"state":"%s","detail":"%s","installed":"%s","latest":"%s","origin":"%s","percent":%s,"downloaded":%s,"total":%s,"folder":"%s","prerelease":%s}\n' \
		"$1" "${2:-}" "$current" "$latest" "$(origin)" "$percent" "$downloaded" "$total" "$folder" "$prerelease"
}
state() { emit "$@" > "$RUN/state.new"; mv -f "$RUN/state.new" "$RUN/state.json"; }
apply_options() {
	local env key value
	for env in $(jsonfilter -i "$SCHEMA" -e '@.options[*].env' 2>/dev/null); do
		case "$env" in AETHER_[A-Z0-9_]*) ;; *) continue ;; esac
		key=core_$(printf '%s' "${env#AETHER_}" | tr A-Z a-z)
		value=$(uci -q get "gozarbin.main.$key" 2>/dev/null || true)
		[ -z "$value" ] || export "$env=$value"
	done
}

case "${1:-status}" in
	path) core_path; exit ;;
	version) core_version; exit ;;
	pt-path)
		if [ -d "$ROOT/current/pt" ]; then echo "$ROOT/current/pt"
		elif [ -d "$ROOT/bundled/pt" ]; then echo "$ROOT/bundled/pt"
		else echo /usr/libexec/gozarbin/pt; fi; exit ;;
	psiphon-path)
		if [ -x "$ROOT/current/pt/psiphon-tunnel-core" ]; then echo "$ROOT/current/pt/psiphon-tunnel-core"
		elif [ -x "$ROOT/bundled/pt/psiphon-tunnel-core" ]; then echo "$ROOT/bundled/pt/psiphon-tunnel-core"
		else echo /usr/libexec/gozarbin/psiphon-tunnel-core; fi; exit ;;
	status)
		if [ -d "$RUN/lock" ] && [ -r "$RUN/pid" ]; then
			pid=$(cat "$RUN/pid")
			if ! kill -0 "$pid" 2>/dev/null; then
				state error interrupted; release_guard; rm -f "$RUN/pid"; rmdir "$RUN/lock" 2>/dev/null || true
			fi
		fi
		if [ -r "$RUN/state.json" ]; then
			phase=$(jsonfilter -i "$RUN/state.json" -e '@.state')
			detail=$(jsonfilter -i "$RUN/state.json" -e '@.detail')
			percent=$(jsonfilter -i "$RUN/state.json" -e '@.percent')
			emit "$phase" "$detail" "${percent:-0}"
		else emit idle; fi; exit ;;
	check|install|register|clear-psiphon|geo-update)
		if [ "$PROVIDER" != aether ]; then case "$1" in register|clear-psiphon) exit 2 ;; esac; fi
		[ ! -d /var/run/gozarbin-update/lock ] || { echo 'Application update is running' >&2; exit 1; }
		for other in /var/run/gozarbin-aether /var/run/gozarbin-singbox; do
			[ "$other" = "$RUN" ] || [ ! -d "$other/lock" ] || { echo 'Another core operation is running' >&2; exit 1; }
		done
		mkdir "$RUN/lock" 2>/dev/null || { echo 'A core operation is already running' >&2; exit 1; }
		claim_guard || { rmdir "$RUN/lock"; echo 'Another update is running' >&2; exit 1; }
		state starting
		setsid "$0" "worker-$1" > "$RUN/log" 2>&1 < /dev/null &
		echo "$!" > "$RUN/pid"
		exit ;;
	worker-check|worker-install|worker-register|worker-clear-psiphon|worker-geo-update) ;;
	*) exit 2 ;;
esac

echo "$$" > "$RUN/pid"
work=$(mktemp -d "$RUN/work.XXXXXX")
finished=0
cleanup() {
	[ -z "${registration_pid:-}" ] || kill -TERM "$registration_pid" 2>/dev/null || true
	[ -z "${registration_watchdog:-}" ] || kill -TERM "$registration_watchdog" 2>/dev/null || true
	release_guard
	[ "$finished" = 1 ] || state error failed
	case "$work" in "$RUN"/work.*) rm -rf "$work" ;; esac
	rm -f "$RUN/pid" "$RUN/download-path"
	rmdir "$RUN/lock" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
fail() { state error "$1"; finished=1; exit 1; }
. "$LIB/fetch.sh"
. "$LIB/releases.sh"

if [ "$1" = worker-geo-update ]; then
	state geo-downloading
	"$LIB/geo-update.sh" "${GOZARBIN_GEO_TARGET:-all}" || fail geo
	state done geo-updated 100; finished=1; exit
fi

if [ "$1" = worker-clear-psiphon ]; then
	state clearing
	was_running=0
	"$SERVICE" running >/dev/null 2>&1 && was_running=1
	[ "$was_running" = 0 ] || "$SERVICE" stop || fail restart
	rm -rf /var/run/gozarbin/psiphon
	[ "$was_running" = 0 ] || "$SERVICE" start || fail restart
	state done cleared 100; finished=1; exit
fi

if [ "$1" = worker-register ]; then
	state registering
	apply_options
	api_address=$(uci -q get gozarbin.main.enroll_address 2>/dev/null || true)
	if [ -n "$api_address" ]; then export AETHER_API_ADDRESS="$api_address" AETHER_ENROLL_ADDRESS="$api_address"; fi
	config=$(uci -q get gozarbin.main.config_file 2>/dev/null || true)
	[ -n "$config" ] || config=/etc/gozarbin/gozarbin.toml
	bounded_run 300 "$(core_path)" --register all --config "$config" || fail registration
	state done registered 100; finished=1; exit
fi

asset_name >/dev/null || fail architecture
state checking
rm -f "$RUN/latest" "$RUN/total" "$RUN/prerelease"
tag=''
if fetch "$API" "$work/release.json" 60; then tag=$(select_release "$work/release.json" || true); fi
if ! valid_version "${tag#v}"; then
	if fetch "https://github.com/$REPO/releases" "$work/release.html" 60; then
		tag=$(grep -o 'https://github.com/[^"<> ]*/releases/tag/v[0-9][0-9A-Za-z.-]*' "$work/release.html" | head -n1 | sed 's|.*/||')
	fi
fi
latest=${tag#v}
valid_version "$latest" || fail network
asset=$(asset_name) || fail architecture
printf '%s\n' "$latest" > "$RUN/latest"
installed=$(core_version || true)
if [ "$PROVIDER" = singbox ] || [ "$(origin)" = upstream ] || [ -r /usr/share/gozarbin/aether-upstream-version ]; then
	if [ "$installed" = "$latest" ] || ! newer "$installed" "$latest"; then
		state current; finished=1; exit
	fi
fi
if [ "$1" = worker-check ]; then state available; finished=1; exit; fi

mkdir -p "$ROOT/releases"
[ "$(df -k "$ROOT" | awk 'NR==2 {print $4}')" -ge 102400 ] || fail space
[ "$(df -k "$RUN" | awk 'NR==2 {print $4}')" -ge 102400 ] || fail space
state downloading
expected=''
if [ "$PROVIDER" = aether ]; then
	fetch "$BASE/v$latest/SHA256SUMS.txt" "$work/SHA256SUMS.txt" 90 || fail download
	expected=$(awk -v name="$asset" '$2==name || $2=="*"name {print $1; exit}' "$work/SHA256SUMS.txt")
fi
if [ -r "$work/release.json" ]; then
	i=0
	while name=$(jsonfilter -i "$work/release.json" -e "@.assets[$i].name" 2>/dev/null) && [ -n "$name" ]; do
		if [ "$name" = "$asset" ]; then
			if [ "$PROVIDER" = singbox ]; then
				digest=$(jsonfilter -i "$work/release.json" -e "@.assets[$i].digest" 2>/dev/null || true)
				case "$digest" in sha256:*) expected=${digest#sha256:} ;; esac
			fi
			size=$(jsonfilter -i "$work/release.json" -e "@.assets[$i].size" 2>/dev/null || echo 0)
			case "$size" in ''|*[!0-9]*) ;; *) echo "$size" > "$RUN/total" ;; esac
			break
		fi
		i=$((i + 1))
	done
fi
printf '%s\n' "$expected" | grep -Eq '^[0-9a-fA-F]{64}$' || fail checksum
echo "$work/archive.tar.gz" > "$RUN/download-path"
fetch "$BASE/v$latest/$asset" "$work/archive.tar.gz" 900 || fail download
actual=$(sha256sum "$work/archive.tar.gz" | awk '{print $1}')
[ "$actual" = "$expected" ] || fail checksum
state verifying '' 100
tar -tzf "$work/archive.tar.gz" > "$work/files" || fail archive
if grep -Eq '(^/|(^|/)\.\.(/|$))' "$work/files"; then fail archive; fi
if tar -tvzf "$work/archive.tar.gz" | grep -Eq '^[lhbcp]'; then fail archive; fi
mkdir "$work/unpacked"
tar -xzf "$work/archive.tar.gz" -C "$work/unpacked" || fail archive
payload="$work/unpacked"
if [ "$PROVIDER" = singbox ]; then
	payload="$work/unpacked/${asset%.tar.gz}"
	[ -f "$payload/sing-box" ] || fail archive
	chmod 755 "$payload/sing-box"
	found=$("$payload/sing-box" version 2>/dev/null | sed -n 's/^sing-box version \([^ ]*\).*/\1/p')
else
	[ -f "$payload/aether" ] || fail archive
	chmod 755 "$payload/aether"
	found=$("$payload/aether" --version 2>/dev/null | sed -n 's/^aether v\{0,1\}//p')
fi
[ "$found" = "$latest" ] || fail binary
[ "$PROVIDER" != aether ] || mv "$payload/aether" "$payload/gozarbin"
target="$ROOT/releases/$latest-$(date +%s)-$$"
mv "$payload" "$target"
previous=$(readlink "$ROOT/current" 2>/dev/null || true)
was_running=0
"$SERVICE" running >/dev/null 2>&1 && was_running=1
state installing '' 100
ln -s "$target" "$ROOT/current.new.$$"
mv -fT "$ROOT/current.new.$$" "$ROOT/current"
if [ "$was_running" = 1 ] && ! "$SERVICE" restart; then
	if [ -n "$previous" ]; then
		ln -s "$previous" "$ROOT/rollback.$$"; mv -fT "$ROOT/rollback.$$" "$ROOT/current"
	else rm -f "$ROOT/current"; fi
	"$SERVICE" restart || true
	fail restart
fi
state done installed 100
finished=1
