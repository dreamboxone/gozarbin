#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
LIB="${GOZARBIN_LIB:-/usr/libexec/gozarbin}"
if [ "${1:-}" = report ]; then exec ucode "$LIB/history.uc" report; fi
lock="${GOZARBIN_HISTORY_LOCK:-/var/run/gozarbin-history.lock}"
mkdir "$lock" 2>/dev/null || exit 0
trap 'rmdir "$lock"' EXIT
if [ "${1:-}" = reset ]; then
	ucode "$LIB/history.uc" reset
else
	data=$("$LIB/traffic.sh") || exit 1
	ucode "$LIB/history.uc" sample "$data" "${2:-}"
fi
