#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
set -eu
LIB="${GOZARBIN_LIB:-/usr/libexec/gozarbin}"
RUN="${GOZARBIN_UPDATE_RUN:-/var/run/gozarbin-update}"
BASE=https://github.com/dreamboxone/gozarbin/releases/download
mkdir -p "$RUN"
state() {
	printf '{"state":"%s","detail":"%s"}\n' "$1" "${2:-}" > "$RUN/state.new"
	mv "$RUN/state.new" "$RUN/state.json"
}
case "${1:-}" in
	status)
		if [ -d "$RUN/lock" ] && [ -s "$RUN/pid" ]; then
			pid=$(cat "$RUN/pid")
			if ! kill -0 "$pid" 2>/dev/null; then
				state error interrupted
				rm -f "$RUN/pid"
				rmdir "$RUN/lock" 2>/dev/null || true
			fi
		fi
		cat "$RUN/state.json" 2>/dev/null || echo '{"state":"idle"}'; exit 0 ;;
	check|install)
		mkdir "$RUN/lock" 2>/dev/null || { echo 'An update is already running' >&2; exit 1; }
		state starting
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
	[ "$success" = 1 ] || state error failed
	rm -rf "$work"
	rm -f "$RUN/pid"
	rmdir "$RUN/lock"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
. "$LIB/fetch.sh"
. "$LIB/packages.sh"
manager=$(pkg_manager)
case "$manager" in
	opkg) arch=$(opkg print-architecture | sort -nk3 | tail -n1 | awk '{print $2}') ;;
	apk) arch=$(apk --print-arch) ;;
	*) exit 1 ;;
esac
case "$arch" in ''|*[!A-Za-z0-9_-]*) exit 1 ;; esac
. /etc/openwrt_release
series=$(printf '%s' "$DISTRIB_RELEASE" | cut -d. -f1,2)
case "$series" in *[!0-9.]*|'') exit 1 ;; esac
state checking
fetch https://api.github.com/repos/dreamboxone/gozarbin/releases/latest "$work/release.json" 45
tag=$(jsonfilter -i "$work/release.json" -e '@.tag_name')
echo "$tag" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' || exit 1
current=$(cat /usr/share/gozarbin/version)
if [ "${current%-r*}" = "${tag#v}" ]; then
	state current "$tag"; success=1; exit 0
fi
# Do not downgrade when a development build or a newer release is installed.
if [ "$manager" = opkg ]; then
	opkg compare-versions "${tag#v}" '>' "${current%-r*}" || { state current "$tag"; success=1; exit 0; }
else
	[ "$(apk version -t "${tag#v}" "${current%-r*}")" = '>' ] || { state current "$tag"; success=1; exit 0; }
fi
fetch "$BASE/$tag/SHA256SUMS.txt" "$work/sums" 60
names=''
keys='main luci'
for key in $keys; do
	case "$key" in main) prefix=gozarbin ;; luci) prefix=luci-app-gozarbin ;; psiphon) prefix=gozarbin-psiphon ;; esac
	case "$manager" in
		opkg) pattern="^${series}-${arch}-${prefix}_[0-9][A-Za-z0-9_.+-]*[.]ipk$" ;;
		apk) pattern="^${series}-${arch}-${prefix}-[0-9][A-Za-z0-9_.+-]*[.]apk$" ;;
	esac
	name=$(awk '{print $2}' "$work/sums" | grep -E "$pattern")
	[ "$(printf '%s\n' "$name" | wc -l)" -eq 1 ] && [ -n "$name" ] || exit 1
	names="$names $name"
done
if [ "$1" = worker-check ]; then state available "$tag"; success=1; exit 0; fi
free=$(df -Pk "$RUN" | awk 'END {print $4}')
[ "$free" -gt 65536 ] || { state error space; success=1; exit 1; }
set -- $names
for key in $keys; do
	name=$1; shift
	expected=$(awk -v n="$name" '$2 == n {print $1}' "$work/sums")
	echo "$expected" | grep -Eq '^[0-9a-f]{64}$' || exit 1
	state downloading "$key"
	if ! "$LIB/delta.sh" fetch "$BASE/$tag/$name" "$work/$name" "$expected" "$work/sums" "$key"; then
		fetch "$BASE/$tag/$name" "$work/$name" 600
	fi
	[ "$(sha256sum "$work/$name" | awk '{print $1}')" = "$expected" ] || exit 1
done
state installing
# The package manager keeps conffiles and owns all installed paths.
case "$manager" in
	opkg) opkg install "$work/"*.ipk ;;
	apk) apk add --allow-untrusted "$work/"*.apk ;;
esac
set -- $names
for key in $keys; do
	name=$1; shift
	expected=$(awk -v n="$name" '$2 == n {print $1}' "$work/sums")
	"$LIB/delta.sh" seed "$BASE/$tag/$name" "$work/$name" "$expected" "$work/sums" "$key" || true
done
[ "$(uci -q get gozarbin.main.enabled)" != 1 ] || /etc/init.d/gozarbin restart
state 'done' "$tag"
success=1
