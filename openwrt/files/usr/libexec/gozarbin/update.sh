#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
set -eu
LIB="${GOZARBIN_LIB:-/usr/libexec/gozarbin}"
RUN="${GOZARBIN_UPDATE_RUN:-/var/run/gozarbin-update}"
BASE=https://github.com/dreamboxone/gozarbin/releases/download
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
download_percent=0
install_percent=0
emit_state() {
	current=$(cat /usr/share/gozarbin/version 2>/dev/null || true)
	latest=$(cat "$RUN/latest" 2>/dev/null || true)
	prerelease=$(cat "$RUN/prerelease" 2>/dev/null || true)
	[ "$prerelease" = true ] || prerelease=false
	current=$(printf '%s' "$current" | sed 's/-r/r/')
	final=''
	[ "$1" != 'done' ] || final="$current"
	printf '{"state":"%s","detail":"%s","current":"%s","latest":"%s","final":"%s","download_percent":%s,"install_percent":%s,"downloaded":%s,"total":%s,"method":"%s","prerelease":%s}\n' \
		"$1" "${2:-}" "$current" "$latest" "$final" "$download_percent" "$install_percent" "${downloaded:-0}" "${total:-0}" "${method:-}" "$prerelease"
}
state() {
	emit_state "$1" "${2:-}" > "$RUN/state.new"
	mv "$RUN/state.new" "$RUN/state.json"
}
case "${1:-}" in
	status)
		if [ -d "$RUN/lock" ] && [ -s "$RUN/pid" ]; then
			pid=$(cat "$RUN/pid")
			if ! kill -0 "$pid" 2>/dev/null; then
				state error interrupted
				release_guard
				rm -f "$RUN/pid"
				rmdir "$RUN/lock" 2>/dev/null || true
			fi
		fi
		if [ -s "$RUN/state.json" ] && [ "$(jsonfilter -i "$RUN/state.json" -e '@.state')" = downloading ]; then
			if [ -s "$RUN/progress" ]; then
				read -r downloaded total method < "$RUN/progress"
				case "$method" in delta) part=$(cat "$RUN/download-path").delta/part ;; *) part=$(cat "$RUN/download-path").part ;; esac
				part_bytes=$(wc -c < "$part" 2>/dev/null || echo 0)
				downloaded=$((downloaded + part_bytes))
				if [ "$total" -gt 0 ]; then download_percent=$((downloaded * 100 / total)); fi
				[ "$download_percent" -le 100 ] || download_percent=100
			fi
			emit_state downloading
		else
			cat "$RUN/state.json" 2>/dev/null || emit_state idle
		fi
		exit 0 ;;
	check|install)
		[ ! -d /var/run/gozarbin-aether/lock ] || { echo 'A core operation is already running' >&2; exit 1; }
		[ ! -d /var/run/gozarbin-singbox/lock ] || { echo 'A core operation is already running' >&2; exit 1; }
		mkdir "$RUN/lock" 2>/dev/null || { echo 'An update is already running' >&2; exit 1; }
		claim_guard || { rmdir "$RUN/lock"; echo 'Another update is running' >&2; exit 1; }
		rm -f "$RUN/latest" "$RUN/prerelease"
		state starting
		rm -f "$RUN/progress" "$RUN/download-path"
		# rpcd terminates the request's process group; the worker needs its own.
		setsid "$0" "worker-$1" > "$RUN/log" 2>&1 < /dev/null &
		exit 0 ;;
	worker-check|worker-install) ;;
	*) exit 2 ;;
esac
work=$(mktemp -d "$RUN/work.XXXXXX")
echo "$$" > "$RUN/pid"
success=0
cleanup() {
	release_guard
	[ "$success" = 1 ] || state error failed
	rm -rf "$work"
	rm -f "$RUN/pid"
	rmdir "$RUN/lock"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
. "$LIB/fetch.sh"
. "$LIB/releases.sh"
. "$LIB/packages.sh"
manager=$(pkg_manager)
. /etc/openwrt_release
case "$manager" in
	opkg) arch=$(opkg print-architecture | sort -nk3 | tail -n1 | awk '{print $2}') ;;
	apk) arch=${DISTRIB_ARCH:-$(cat /etc/apk/arch 2>/dev/null || apk --print-arch)} ;;
	*) exit 1 ;;
esac
case "$arch" in ''|*[!A-Za-z0-9_-]*) exit 1 ;; esac
series=$(printf '%s' "$DISTRIB_RELEASE" | cut -d. -f1,2)
case "$series" in *[!0-9.]*|'') exit 1 ;; esac
state checking
tag=''
valid_tag() { printf '%s\n' "$1" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+(r[1-9][0-9]*)?$'; }
rm -f "$RUN/prerelease"
if fetch 'https://api.github.com/repos/dreamboxone/gozarbin/releases?per_page=20' "$work/release.json" 45; then
	tag=$(select_release "$work/release.json" || true)
fi
if ! valid_tag "$tag"; then
	if fetch https://github.com/dreamboxone/gozarbin/releases "$work/release.html" 45; then
		tag=$(grep -o 'https://github.com/dreamboxone/gozarbin/releases/tag/v[0-9][0-9.r]*' "$work/release.html" | head -n1 | sed 's|.*/||')
	fi
fi
if ! valid_tag "$tag"; then
	rm -f "$RUN/latest"
	state error network; success=1; exit 1
fi
printf '%s' "${tag#v}" > "$RUN/latest"
target=${tag#v}
case "$target" in *r*) target=$(printf '%s' "$target" | sed 's/r/-r/') ;; *) target="$target-r1" ;; esac
current=$(cat /usr/share/gozarbin/version)
if [ "$current" = "$target" ]; then
	state current "$tag"; success=1; exit 0
fi
# Do not downgrade when a development build or a newer release is installed.
if [ "$manager" = opkg ]; then
	opkg compare-versions "$target" '>' "$current" || { state current "$tag"; success=1; exit 0; }
else
	[ "$(apk version -t "$target" "$current")" = '>' ] || { state current "$tag"; success=1; exit 0; }
fi
fetch "$BASE/$tag/SHA256SUMS.txt" "$work/sums" 60
case "$manager" in opkg) ext=ipk ;; apk) ext=apk ;; esac
name=$(awk '{print $2}' "$work/sums" | grep -E "^gozarbin-openwrt-${series}[.][0-9]+-${arch}[.]$ext$" || true)
[ -n "$name" ] || name=$(awk '{print $2}' "$work/sums" | grep -E "^gozarbin-openwrt-${series}[.][0-9]+-${arch}[.]tar[.]gz$" || true)
[ "$(printf '%s\n' "$name" | wc -l)" -eq 1 ] && [ -n "$name" ] || exit 1
if [ "$1" = worker-check ]; then state available "$tag"; success=1; exit 0; fi
free=$(df -Pk "$RUN" | awk 'END {print $4}')
[ "$free" -gt 131072 ] || { state error space; success=1; exit 1; }
expected=$(awk -v n="$name" '$2 == n {print $1}' "$work/sums")
echo "$expected" | grep -Eq '^[0-9a-f]{64}$' || exit 1
state downloading bundle
export GOZARBIN_PROGRESS="$RUN/progress"
printf '%s' "$work/$name" > "$RUN/download-path"
if ! "$LIB/delta.sh" fetch "$BASE/$tag/$name" "$work/$name" "$expected" "$work/sums" main; then
	total=$(jsonfilter -i "$work/release.json" -e "@.assets[@.name=\"$name\"].size" 2>/dev/null || true)
	case "$total" in ''|*[!0-9]*) total=0 ;; esac
	printf '0 %s full\n' "$total" > "$RUN/progress"
	fetch "$BASE/$tag/$name" "$work/$name" 600
fi
[ "$(sha256sum "$work/$name" | awk '{print $1}')" = "$expected" ] || exit 1
download_percent=100
if [ -s "$RUN/progress" ]; then
	read -r downloaded total method < "$RUN/progress"
	downloaded=$total
fi
# New releases are one architecture package including LuCI. Older verified
# two-package archives remain installable during the transition.
case "$name" in
	*."$ext") set -- "$work/$name" ;;
	*.tar.gz)
		folder=${name%.tar.gz}
		folder_pattern=$(printf '%s' "$folder" | sed 's/[.]/[.]/g')
		tar -tzf "$work/$name" > "$work/entries"
		[ "$(wc -l < "$work/entries")" -eq 2 ] || exit 1
		for prefix in gozarbin luci-app-gozarbin; do
			count=$(grep -Ec "^$folder_pattern/${prefix}[-_][0-9][A-Za-z0-9_.+-]*[.]$ext$" "$work/entries" || true)
			[ "$count" = 1 ] || exit 1
		done
		tar -tvzf "$work/$name" > "$work/types"
		[ "$(grep -c '^-' "$work/types")" -eq 2 ] || exit 1
		mkdir "$work/packages"
		tar -xzf "$work/$name" -C "$work/packages"
		set -- "$work/packages/$folder/"*."$ext"
		;;
	*) exit 1 ;;
esac
state installing
# The package manager keeps conffiles and owns all installed paths.
case "$manager" in
	opkg) opkg install "$@" ;;
	apk) apk add --allow-untrusted "$@" ;;
esac
install_percent=80
state installing package
installed=$(cat /usr/share/gozarbin/version)
[ "$installed" = "$target" ] || { state error version; success=1; exit 1; }
install_percent=90
state installing verifying
"$LIB/delta.sh" seed "$BASE/$tag/$name" "$work/$name" "$expected" "$work/sums" main || true
[ "$(uci -q get gozarbin.main.enabled)" != 1 ] || /etc/init.d/gozarbin restart
install_percent=100
state 'done' "$tag"
success=1
