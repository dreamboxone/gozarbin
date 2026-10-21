#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
"""Run the actual update worker against isolated package managers and releases."""
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'openwrt/files/usr/libexec/gozarbin/update.sh').read_text()

with tempfile.TemporaryDirectory(prefix='gozarbin-update-test-') as temporary:
    base = Path(temporary)
    lib = base / 'lib'; lib.mkdir()
    binaries = base / 'bin'; binaries.mkdir()
    release = base / 'release'; release.mkdir()
    runtime = base / 'run'; runtime.mkdir()
    version = base / 'version'; version.write_text('2.2.1-r2\n')
    system = base / 'openwrt_release'; system.write_text("DISTRIB_RELEASE='24.10.8'\n")
    names = ['24.10-arm_cortex-a7_neon-vfpv4-gozarbin_2.2.2-r1_arm_cortex-a7_neon-vfpv4.ipk',
             '24.10-arm_cortex-a7_neon-vfpv4-luci-app-gozarbin_2.2.2-r1_all.ipk']
    for name in names:
        (release / name).write_bytes(b'package:' + name.encode())
    sums = ''.join(hashlib.sha256((release / name).read_bytes()).hexdigest() + '  ' + name + '\n' for name in names)
    (release / 'SHA256SUMS.txt').write_text(sums)
    (release / 'latest').write_text('{"tag_name":"v2.2.2"}')
    (lib / 'fetch.sh').write_text('''fetch() {
case "$1" in */latest) cp "$TEST_RELEASE/latest" "$2" ;;
*) cp "$TEST_RELEASE/${1##*/}" "$2" ;; esac
}
''')
    (lib / 'packages.sh').write_text('pkg_manager() { echo "${TEST_MANAGER:-opkg}"; }\npkg_installed() { return 1; }\n')
    (lib / 'delta.sh').write_text('#!/bin/sh\necho "$1" >> "$TEST_DELTA_LOG"\nexit 2\n')
    (lib / 'delta.sh').chmod(0o755)
    (binaries / 'opkg').write_text('''#!/bin/sh
case "$1" in
print-architecture) echo 'arch all 1'; echo 'arch arm_cortex-a7_neon-vfpv4 10' ;;
compare-versions) [ "$2" = 2.2.2 ] && [ "$4" = 2.2.1 ] ;;
install) shift; printf '%s\\n' "$@" >> "$TEST_INSTALL_LOG" ;;
esac
''')
    (binaries / 'apk').write_text('''#!/bin/sh
case "$1" in
--print-arch) echo arm_cortex-a7_neon-vfpv4 ;;
version) echo '>' ;;
add) shift; printf '%s\\n' "$@" >> "$TEST_INSTALL_LOG" ;;
esac
''')
    (binaries / 'uci').write_text('#!/bin/sh\necho 0\n')
    (binaries / 'jsonfilter').write_text('''#!/bin/sh
python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["tag_name"])' "$2"
''')
    for binary in binaries.iterdir(): binary.chmod(0o755)
    worker = base / 'update.sh'
    worker.write_text(source.replace('/etc/openwrt_release', str(system)).replace('/usr/share/gozarbin/version', str(version)))
    env = dict(os.environ, PATH=str(binaries) + ':' + os.environ['PATH'],
               GOZARBIN_LIB=str(lib), GOZARBIN_UPDATE_RUN=str(runtime),
               TEST_RELEASE=str(release), TEST_INSTALL_LOG=str(base / 'installed'),
               TEST_DELTA_LOG=str(base / 'delta-log'))

    def run(action):
        (runtime / 'lock').mkdir()
        return subprocess.run(['sh', str(worker), 'worker-' + action], env=env, capture_output=True, text=True)

    def state():
        import json
        return json.loads((runtime / 'state.json').read_text())['state']

    assert run('check').returncode == 0 and state() == 'available'
    assert not (base / 'installed').exists()
    print('PASS: compatible release check does not install packages')
    result = run('install')
    assert result.returncode == 0, result.stderr
    assert state() == 'done'
    assert len((base / 'installed').read_text().splitlines()) == 2
    assert (base / 'delta-log').read_text().splitlines() == ['fetch', 'fetch', 'seed', 'seed']
    print('PASS: failed delta falls back to verified full packages before opkg install')
    (base / 'installed').unlink()
    (release / names[1]).write_bytes(b'corrupt')
    assert run('install').returncode != 0 and state() == 'error'
    assert not (base / 'installed').exists()
    print('PASS: corrupt second package prevents installation of either package')
    version.write_text('2.2.2-r1\n')
    assert run('check').returncode == 0 and state() == 'current'
    version.write_text('2.3.0-r1\n')
    assert run('install').returncode == 0 and state() == 'current'
    print('PASS: current and newer installed versions are never downgraded')
    version.write_text('2.2.1-r2\n')
    system.write_text("DISTRIB_RELEASE='25.12.5'\n")
    env['TEST_MANAGER'] = 'apk'
    apk_names = [f'25.12-arm_cortex-a7_neon-vfpv4-{prefix}-2.2.2-r1.apk' for prefix in ['gozarbin', 'luci-app-gozarbin']]
    for name in apk_names: (release / name).write_bytes(b'valid apk')
    (release / 'SHA256SUMS.txt').write_text(''.join(
        hashlib.sha256((release / n).read_bytes()).hexdigest() + '  ' + n + '\n' for n in apk_names))
    result = run('install')
    assert result.returncode == 0, result.stderr
    assert state() == 'done'
    installed = (base / 'installed').read_text()
    assert '--allow-untrusted' in installed and installed.count('.apk') == 2
    print('PASS: OpenWrt 25.12 selects APK assets and uses apk add')

print('All update worker tests passed')
