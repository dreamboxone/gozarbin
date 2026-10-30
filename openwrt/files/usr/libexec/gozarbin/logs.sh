#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
set -eu
umask 077
run=${GOZARBIN_LOG_RUN:-/var/run/gozarbin/logs}
case "${1:-}" in
	runtime|core) kind=$1; clear=0 ;;
	clear-runtime) kind=runtime; clear=1 ;;
	clear-core) kind=core; clear=1 ;;
	*) exit 2 ;;
esac
mkdir -p "$run"
snapshot=$(mktemp "$run/snapshot.XXXXXX")
trap 'rm -f "$snapshot"' EXIT
logread -e gozarbin | awk -v kind="$kind" '
	/ gozarbin(-unblock)?(\[[0-9]+\])?: / {
		core = ($0 ~ / gozarbin(-unblock)?\[[0-9]+\]: /)
		if ((kind == "core") == core) print
	}' > "$snapshot"
if [ "$clear" = 1 ]; then
	tail -n 1 "$snapshot" > "$snapshot.cursor"
	mv "$snapshot.cursor" "$run/$kind.cursor"
	exit 0
fi
# Clearing hides only this program's earlier lines; the system log is preserved.
awk -v marker="$run/$kind.cursor" '
	BEGIN { getline cutoff < marker; close(marker) }
	{ lines[NR] = $0; if (cutoff != "" && $0 == cutoff) start = NR }
	END { first = start + 1; if (first < NR - 299) first = NR - 299
		for (i = first; i <= NR; i++) print lines[i] }
' "$snapshot"
