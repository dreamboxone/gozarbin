#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
"""Exercise counter resets, persistent history and retention with real ucode."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='gozarbin-history-') as temporary:
    base = Path(temporary)
    env = dict(os.environ, GOZARBIN_HISTORY_RAM=str(base / 'ram.json'),
               GOZARBIN_HISTORY_DISK=str(base / 'disk.json'), GOZARBIN_HISTORY_TIME='1792578600')

    def run(mode, up=0, down=0, **extra):
        sample = dict(upload=up, download=down, **extra)
        result = subprocess.run(['ucode', str(ROOT / 'openwrt/files/usr/libexec/gozarbin/history.uc'),
                                 mode, json.dumps(sample), '--flush'], env=env, capture_output=True, text=True)
        assert result.returncode == 0, result.stderr
        return json.loads(result.stdout) if mode == 'report' else json.loads((base / 'ram.json').read_text())

    run('sample', 100, 200)
    value = run('sample', 150, 280)
    assert value['hours'][0][1:] == [150, 280]
    run('sample', 0, 0, counters=False)
    value = run('sample', 170, 300)
    assert value['hours'][0][1:] == [170, 300]
    print('PASS: repeated samples count only deltas; missing counters do not duplicate traffic')
    run('reset')
    value = run('sample', 10, 20)
    assert value['hours'][0][1:] == [180, 320]
    print('PASS: firewall counter resets preserve accumulated history')
    (base / 'ram.json').unlink()
    assert run('report')['hours'][0][1:] == [180, 320]
    print('PASS: persisted history remains readable after volatile state is lost')
    env['GOZARBIN_HISTORY_TIME'] = str(1792578600 + 3600)
    value = run('sample', 20, 40)
    assert value['hours'][-1][1:] == [10, 20] and len(value['hours']) == 2
    env['GOZARBIN_HISTORY_TIME'] = str(1792578600 + 32 * 86400)
    value = run('sample', 30, 50)
    assert len(value['hours']) == 1
    print('PASS: hourly bins and bounded 31-day retention')
