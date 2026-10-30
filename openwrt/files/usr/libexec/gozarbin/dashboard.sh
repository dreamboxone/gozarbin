#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
set -eu
umask 077
lib=${GOZARBIN_LIB:-/usr/libexec/gozarbin}
work=$(mktemp -d /tmp/gozarbin-dashboard.XXXXXX)
trap 'rm -rf "$work"' EXIT
read_status() {
	key=$1
	shift
	"$@" > "$work/$key" 2>/dev/null || printf '{}' > "$work/$key"
	[ -s "$work/$key" ] || printf '{}' > "$work/$key"
}
# rpcd executes calls in a batch serially. These independent local reads can
# run together without delaying one another or changing service state.
read_status proxy "$lib/passwall2-detect.sh" --json &
read_status system "$lib/system-info.sh" &
read_status deps "$lib/deps.sh" --json &
read_status traffic "$lib/traffic.sh" &
read_status core "$lib/singbox.sh" --state &
read_status tunnel "$lib/tunnel.sh" &
read_status connectivity "$lib/connectivity.sh" status &
wait
separator=
printf '{'
for key in proxy system deps traffic core tunnel connectivity; do
	printf '%s"%s":' "$separator" "$key"
	cat "$work/$key"
	separator=,
done
printf '}\n'
