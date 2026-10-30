#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
"""Verify the unified package installs every required versioned LuCI resource."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='gozarbin-ui-package-') as temporary:
    base = Path(temporary)
    shutil.copytree(ROOT / 'luci-app-gozarbin', base / 'build/luci')
    makefile = base / 'Makefile'
    destination = base / 'installed'
    makefile.write_text(f'''PKG_VERSION:=5.7.29
PKG_RELEASE:=3
PKG_BUILD_DIR:={base}/build
INSTALL_DIR:=mkdir -p
INSTALL_DATA:=install -m 0644
include {ROOT}/openwrt/luci.mk
stage:
\t$(call Gozarbin/InstallLuCI,{destination})
''')
    result = subprocess.run(['make', '-f', str(makefile), 'stage'], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    resources = destination / 'www/luci-static/resources/view/gozarbin'
    for name in ['settings', 'update', 'appearance', 'traffic', 'i18n', 'core-update']:
        assert (resources / f'{name}-5-7-29-r3.js').is_file(), name
    assert (resources / 'logo.png').is_file()
    assert (resources / 'fonts/Vazirmatn.woff2').is_file()
    source = (resources / 'update-5-7-29-r3.js').read_text()
    assert 'view.gozarbin.core-update-5-7-29-r3 as coreupdate' in source
    menu = json.loads((destination / 'usr/share/luci/menu.d/luci-app-gozarbin.json').read_text())
    assert menu['admin/services/gozarbin/settings']['action']['path'] == 'gozarbin/settings-5-7-29-r3'
    acl = json.loads((destination / 'usr/share/rpcd/acl.d/luci-app-gozarbin.json').read_text())['luci-app-gozarbin']
    assert '/usr/libexec/gozarbin/singbox-core.sh install' in acl['write']['file']
    assert '/usr/share/gozarbin/core-options.json' in acl['read']['file']
    package = (ROOT / 'openwrt/Makefile').read_text()
    assert 'REPLACES:=luci-app-gozarbin' in package
    assert '$(call Gozarbin/InstallLuCI,$(1))' in package
print('PASS: unified package contains all LuCI resources, logo, fonts, menu and core-update permissions')
