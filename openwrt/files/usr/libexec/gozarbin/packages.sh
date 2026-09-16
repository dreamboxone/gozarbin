# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
#
# Package queries against one snapshot of the installed database. Asking apk per
# package costs about eighty milliseconds each, which a dependency report turns
# into a second and a half of a router's time and of the settings page's load.
# Sourced, not executed.

pkg_manager() {
	if command -v apk >/dev/null 2>&1; then echo apk
	elif command -v opkg >/dev/null 2>&1; then echo opkg
	fi
}

pkg_snapshot() {
	[ -n "${PKG_LIST+set}" ] && return 0
	case "$(pkg_manager)" in
		apk) PKG_LIST=$(apk list --installed 2>/dev/null) ;;
		opkg) PKG_LIST=$(opkg list-installed 2>/dev/null) ;;
		*) PKG_LIST= ;;
	esac
}

# The snapshot holds real package names. A name that is missing from it may still
# be provided by another package under a different name, which only the package
# manager can resolve, so that one question is worth asking it.
pkg_installed() {
	pkg_snapshot
	printf '%s\n' "$PKG_LIST" | grep -q "^$1[- ][0-9-]" && return 0
	case "$(pkg_manager)" in
		apk) apk info -e "$1" >/dev/null 2>&1 ;;
		opkg) opkg status "$1" 2>/dev/null | grep -q '^Status:.* installed' ;;
		*) return 1 ;;
	esac
}

pkg_version() {
	pkg_snapshot
	case "$(pkg_manager)" in
		apk) printf '%s\n' "$PKG_LIST" | sed -n "s/^$1-\([0-9][^ ]*\) .*/\1/p" | head -n 1 ;;
		opkg) printf '%s\n' "$PKG_LIST" | sed -n "s/^$1 - \([^ ]*\).*/\1/p" | head -n 1 ;;
	esac
}
