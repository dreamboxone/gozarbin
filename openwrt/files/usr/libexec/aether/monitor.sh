#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
#
# The one long-lived background task this package owns. It keeps a running total
# of what has gone through the proxy, which the nftables counters cannot do on
# their own because they start again at zero with every firewall reload, and it
# lets the sing-box version check decide for itself when a day has passed.
#
# procd runs it, so it lives and dies with the service and nothing is written to
# anybody else's crontab.

while :; do
	/usr/libexec/aether/singbox.sh --sample >/dev/null 2>&1
	/usr/libexec/aether/singbox.sh --check >/dev/null 2>&1
	sleep 1200
done
