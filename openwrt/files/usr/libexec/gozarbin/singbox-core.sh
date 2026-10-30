#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
export GOZARBIN_CORE_PROVIDER=singbox
exec "${GOZARBIN_LIB:-/usr/libexec/gozarbin}/aether-core.sh" "$@"
