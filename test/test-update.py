#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
"""Run the actual update worker against isolated package managers and releases."""
import hashlib
import io
import json
import tarfile
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
    system = base / 'openwrt_release'; system.write_text("DISTRIB_RELEASE='24.10.8'\nDISTRIB_ARCH='arm_cortex-a7_neon-vfpv4'\n")
    def bundle(openwrt, extension, unsafe=False):
        name = f'gozarbin-openwrt-{openwrt}-arm_cortex-a7_neon-vfpv4.tar.gz'
        folder = name.removesuffix('.tar.gz')
        with tarfile.open(release / name, 'w:gz') as tar:
            for prefix in ['gozarbin', 'luci-app-gozarbin']:
                filename = f'{prefix}_2.2.2-r1_all.ipk' if extension == 'ipk' else f'{prefix}-2.2.2-r1.apk'
                entry = tarfile.TarInfo(('../' if unsafe else folder + '/') + filename)
                data = b'package:' + filename.encode(); entry.size = len(data)
                tar.addfile(entry, io.BytesIO(data))
        sha = hashlib.sha256((release / name).read_bytes()).hexdigest()
        (release / 'SHA256SUMS.txt').write_text(sha + '  ' + name + '\n')
        return name
    archive = bundle('24.10.8', 'ipk')
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
compare-versions) dpkg --compare-versions "$2" gt "$4" ;;
install) echo "${TEST_TARGET:-2.2.2-r1}" > "$TEST_VERSION"; shift; printf '%s\\n' "$@" >> "$TEST_INSTALL_LOG" ;;
esac
''')
    (binaries / 'apk').write_text('''#!/bin/sh
case "$1" in
--print-arch) echo armv7 ;;
version) echo '>' ;;
add) echo "${TEST_TARGET:-2.2.2-r1}" > "$TEST_VERSION"; shift; printf '%s\\n' "$@" >> "$TEST_INSTALL_LOG" ;;
esac
''')
    (binaries / 'uci').write_text('#!/bin/sh\necho 0\n')
    (binaries / 'jsonfilter').write_text('''#!/bin/sh
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("tag_name", "") if sys.argv[2]=="@.tag_name" else d.get("state", ""))' "$2" "$4"
''')
    for binary in binaries.iterdir(): binary.chmod(0o755)
    worker = base / 'update.sh'
    worker.write_text(source.replace('/etc/openwrt_release', str(system)).replace('/usr/share/gozarbin/version', str(version)))
    env = dict(os.environ, PATH=str(binaries) + ':' + os.environ['PATH'],
               GOZARBIN_LIB=str(lib), GOZARBIN_UPDATE_RUN=str(runtime),
               TEST_VERSION=str(version), TEST_RELEASE=str(release), TEST_INSTALL_LOG=str(base / 'installed'),
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
    assert (base / 'delta-log').read_text().splitlines() == ['fetch', 'seed']
    print('PASS: failed delta falls back to verified full packages before opkg install')
    (base / 'installed').unlink()
    version.write_text('2.2.1-r2\n')
    (release / archive).write_bytes(b'corrupt')
    assert run('install').returncode != 0 and state() == 'error'
    assert not (base / 'installed').exists()
    print('PASS: corrupt bundle prevents installation of either package')
    version.write_text('2.2.2-r1\n')
    assert run('check').returncode == 0 and state() == 'current'
    version.write_text('2.3.0-r1\n')
    assert run('install').returncode == 0 and state() == 'current'
    print('PASS: current and newer installed versions are never downgraded')
    version.write_text('2.2.1-r2\n')
    system.write_text("DISTRIB_RELEASE='25.12.5'\nDISTRIB_ARCH='arm_cortex-a7_neon-vfpv4'\n")
    env['TEST_MANAGER'] = 'apk'
    bundle('25.12.5', 'apk')
    result = run('install')
    assert result.returncode == 0, result.stderr
    assert state() == 'done'
    installed = (base / 'installed').read_text()
    assert '--allow-untrusted' in installed and installed.count('.apk') == 2
    print('PASS: OpenWrt 25.12 unpacks the APK pair and uses apk add')
    (base / 'installed').unlink()
    version.write_text('2.2.1-r2\n')
    bundle('25.12.5', 'apk', unsafe=True)
    assert run('install').returncode != 0 and state() == 'error'
    assert not (base / 'installed').exists()
    print('PASS: unsafe archive paths are rejected before extraction or installation')

    env['TEST_MANAGER'] = 'opkg'
    env['TEST_TARGET'] = '5.7.29-r2'
    system.write_text("DISTRIB_RELEASE='24.10.8'\nDISTRIB_ARCH='arm_cortex-a7_neon-vfpv4'\n")
    version.write_text('5.7.29-r1\n')
    (release / 'latest').write_text('{"tag_name":"v5.7.29r2"}')
    bundle('24.10.8', 'ipk')
    assert run('check').returncode == 0 and state() == 'available'
    snapshot = json.loads((runtime / 'state.json').read_text())
    assert snapshot['current'] == '5.7.29r1' and snapshot['latest'] == '5.7.29r2'
    result = run('install')
    assert result.returncode == 0, result.stderr
    snapshot = json.loads((runtime / 'state.json').read_text())
    assert snapshot['final'] == '5.7.29r2' and snapshot['install_percent'] == 100
    assert snapshot['download_percent'] == 100
    print('PASS: same-day r2 upgrades r1 and reports the verified final installed version')

    (runtime / 'state.json').write_text('{"state":"downloading"}')
    partial = base / 'partial.tar.gz'
    (base / 'partial.tar.gz.delta').mkdir()
    (base / 'partial.tar.gz.delta/part').write_bytes(b'x' * 50)
    (runtime / 'download-path').write_text(str(partial))
    (runtime / 'progress').write_text('100 200 delta\n')
    result = subprocess.run(['sh', str(worker), 'status'], env=env, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    snapshot = json.loads(result.stdout)
    assert snapshot['download_percent'] == 75 and snapshot['downloaded'] == 150
    print('PASS: live delta progress includes completed ranges and the active partial download')

print('All update worker tests passed')
