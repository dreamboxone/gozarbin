#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
"""Check log isolation, bounded output and section-only clearing."""
import os
from pathlib import Path
import subprocess
import tempfile

SCRIPT = Path(__file__).resolve().parents[1] / 'openwrt/files/usr/libexec/gozarbin/logs.sh'
with tempfile.TemporaryDirectory(prefix='gozarbin-logs-') as directory:
    base = Path(directory)
    (base / 'bin').mkdir()
    reader = base / 'bin/logread'
    reader.write_text('#!/bin/sh\ncat "$FIXTURE/source"\n')
    reader.chmod(0o755)
    source = base / 'source'
    source.write_text('date daemon.info other[9]: gozarbin mentioned\n'
                      'date user.notice gozarbin: starting\n'
                      'date daemon.info gozarbin[20]: connected\n'
                      'date daemon.info gozarbin-unblock[21]: ready\n'
                      'date daemon.info zirgozar[22]: private\n')
    env = {**os.environ, 'PATH': str(base / 'bin') + ':' + os.environ['PATH'],
           'FIXTURE': str(base), 'GOZARBIN_LOG_RUN': str(base / 'run')}
    def run(action):
        result = subprocess.run(['sh', str(SCRIPT), action], env=env, capture_output=True, text=True)
        assert result.returncode == 0, result.stderr
        return result.stdout
    assert run('runtime') == 'date user.notice gozarbin: starting\n'
    assert 'connected' in run('core') and 'ready' in run('core')
    assert 'private' not in run('core') and 'mentioned' not in run('runtime')
    before = source.read_bytes()
    run('clear-runtime')
    assert run('runtime') == '' and 'connected' in run('core')
    assert source.read_bytes() == before
    with source.open('a') as output:
        output.write('date user.notice gozarbin: next\n')
    assert run('runtime') == 'date user.notice gozarbin: next\n'
    run('clear-core')
    assert run('core') == '' and 'next' in run('runtime')
    source.write_text(''.join(f'date daemon.info gozarbin[20]: message {i}\n' for i in range(500)))
    lines = run('core').splitlines()
    assert len(lines) == 300 and lines[0].endswith('200') and lines[-1].endswith('499')
    assert subprocess.run(['sh', str(SCRIPT), '../other'], env=env).returncode == 2
    print('PASS: logs are isolated, capped at 300 lines, and clearing preserves system and other-section logs')
