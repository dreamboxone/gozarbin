#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone

installed=0
active=0

[ -x /etc/init.d/passwall2 ] && installed=1
if command -v apk >/dev/null 2>&1; then
	apk info -e luci-app-passwall2 >/dev/null 2>&1 && installed=1
elif command -v opkg >/dev/null 2>&1; then
	opkg status luci-app-passwall2 2>/dev/null | grep -q '^Status:.* installed' && installed=1
fi

if [ "$installed" = 1 ]; then
	ubus call service list '{"name":"passwall2"}' 2>/dev/null | grep -q '"running": true' && active=1
# Passwall2 does not expose a reliable `running` action on every OpenWrt build.
# Treat an enabled global configuration as active so Gozarbin fails safely during
# Passwall2 startup, restart, or monitor recovery as well.
	[ "$(uci -q get passwall2.@global[0].enabled 2>/dev/null)" = 1 ] && active=1
fi

zirgozar_active=0
if [ -x /etc/init.d/zirgozar ]; then
	ubus call service list '{"name":"zirgozar"}' 2>/dev/null | grep -q '"running": true' && zirgozar_active=1
	[ "$(uci -q get zirgozar.config.enabled 2>/dev/null)" = 1 ] && zirgozar_active=1
fi

case "$1" in
	--installed) [ "$installed" = 1 ] ;;
	--active) [ "$active" = 1 ] ;;
	--conflict)
		if [ "$zirgozar_active" = 1 ]; then echo zirgozar
		elif [ "$active" = 1 ]; then echo passwall2
		else exit 1; fi ;;
	--json) printf '{"installed":%s,"active":%s,"zirgozar_active":%s}\n' "$([ "$installed" = 1 ] && echo true || echo false)" "$([ "$active" = 1 ] && echo true || echo false)" "$([ "$zirgozar_active" = 1 ] && echo true || echo false)" ;;
	*) printf 'installed=%s active=%s\n' "$installed" "$active" ;;
esac
