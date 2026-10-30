#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
"""Verify status reads run concurrently and one failure stays isolated."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

SCRIPT = Path(__file__).resolve().parents[1] / 'openwrt/files/usr/libexec/gozarbin/dashboard.sh'
with tempfile.TemporaryDirectory(prefix='gozarbin-dashboard-test-') as directory:
    base = Path(directory)
    (base / 'started').mkdir()
    names = ['passwall2-detect', 'system-info', 'deps', 'traffic', 'singbox', 'tunnel', 'connectivity']
    for name in names:
        path = base / (name + '.sh')
        path.write_text('''#!/bin/sh
name=${0##*/}
touch "$FIXTURE/started/$name"
while [ "$(ls "$FIXTURE/started" | wc -l)" -lt 7 ]; do sleep 0.05; done
[ "$name" != deps.sh ] || exit 1
printf '{"source":"%s"}' "$name"
''')
        path.chmod(0o755)
    env = {**os.environ, 'FIXTURE': str(base), 'GOZARBIN_LIB': str(base)}
    result = subprocess.run(['sh', str(SCRIPT)], env=env, capture_output=True, text=True, timeout=5)
    assert result.returncode == 0, result.stderr
    state = json.loads(result.stdout)
    assert state['deps'] == {}
    assert state['system']['source'] == 'system-info.sh' and state['traffic']['source'] == 'traffic.sh'
    assert set(state) == {'proxy', 'system', 'deps', 'traffic', 'core', 'tunnel', 'connectivity'}
    print('PASS: independent dashboard reads run together and a failed read does not discard the other results')
