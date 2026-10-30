#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
"""Check direct activation and proxy conflicts without touching real services."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='gozarbin-control-') as temporary:
    base = Path(temporary)
    for name in ['bin', 'init', 'lib', 'config']:
        (base / name).mkdir()

    def executable(path, text):
        path.write_text(text)
        path.chmod(0o755)

    executable(base / 'bin/apk', '#!/bin/sh\nexit 1\n')
    executable(base / 'bin/ubus', '#!/bin/sh\necho "{}"\n')
    executable(base / 'bin/uci', '''#!/bin/sh
case "$*" in
 *passwall2*|*zirgozar*) echo 1 ;;
 *) printf '%s\n' "$*" >> "$TEST_WRITES" ;;
esac
''')
    detector = (ROOT / 'openwrt/files/usr/libexec/gozarbin/passwall2-detect.sh').read_text()
    detector = detector.replace('/etc/init.d/', str(base / 'init') + '/').replace('/etc/config/', str(base / 'config') + '/')
    executable(base / 'lib/passwall2-detect.sh', detector)
    (base / 'config/passwall2').write_text('leftover configuration')
    env = dict(os.environ, PATH=str(base / 'bin') + ':' + os.environ['PATH'], TEST_WRITES=str(base / 'writes'))

    def report():
        result = subprocess.run(['sh', str(base / 'lib/passwall2-detect.sh'), '--json'], env=env, capture_output=True, text=True)
        assert result.returncode == 0, result.stderr
        return json.loads(result.stdout)

    assert report() == {'installed': False, 'active': False, 'zirgozar_active': False}
    print('PASS: missing Passwall2 never warns or blocks, including leftover configuration')
    executable(base / 'init/passwall2', '#!/bin/sh\nexit 0\n')
    assert report()['active'] is True
    executable(base / 'init/zirgozar', '#!/bin/sh\nexit 0\n')
    assert report()['zirgozar_active'] is True

    control = (ROOT / 'openwrt/files/usr/bin/gozarbinctl').read_text()
    control = control.replace('/usr/libexec/gozarbin/', str(base / 'lib') + '/')
    control = control.replace('/etc/init.d/gozarbin', str(base / 'init/gozarbin'))
    executable(base / 'gozarbinctl', control)
    executable(base / 'init/gozarbin', '#!/bin/sh\necho "$1" >> "$TEST_WRITES"\n')
    result = subprocess.run(['sh', str(base / 'gozarbinctl'), 'on'], env=env, capture_output=True, text=True)
    assert result.returncode != 0 and 'conflict:zirgozar' in result.stderr
    assert not (base / 'writes').exists()
    print('PASS: conflict blocks start before changing settings or calling any service')
    (base / 'init/zirgozar').unlink()
    result = subprocess.run(['sh', str(base / 'gozarbinctl'), 'on'], env=env, capture_output=True, text=True)
    assert result.returncode != 0 and 'conflict:passwall2' in result.stderr
    assert not (base / 'writes').exists()
    (base / 'init/passwall2').unlink()
    assert subprocess.run(['sh', str(base / 'gozarbinctl'), 'on'], env=env).returncode == 0
    writes = (base / 'writes').read_text()
    assert 'set gozarbin.main.enabled=1' in writes and 'commit gozarbin' in writes
    assert 'enable' in writes and 'restart' in writes
    executable(base / 'init/passwall2', '#!/bin/sh\nexit 0\n')
    assert subprocess.run(['sh', str(base / 'gozarbinctl'), 'off'], env=env).returncode == 0
    writes = (base / 'writes').read_text()
    assert 'set gozarbin.main.enabled=0' in writes and 'stop' in writes
    print('PASS: on/off persist and act directly; stop remains available during a conflict')
