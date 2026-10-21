#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
"""Verify bounded retries and remote DNS fallback in the actual fetch helper."""
import os
from pathlib import Path
import subprocess
import tempfile

source = Path(__file__).resolve().parents[1] / 'openwrt/files/usr/libexec/gozarbin/fetch.sh'
with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    scripts = {
        'sleep': 'exit 0',
        'uci': 'echo 1819',
        'netstat': 'echo "tcp 0 0 127.0.0.1:1819 0.0.0.0:* LISTEN"',
        'curl': '''
n=$(cat "$COUNT" 2>/dev/null || echo 0)
n=$((n+1)); echo "$n" > "$COUNT"
echo "$*" >> "$CALLS"
case "$MODE:$n" in transient:1|transient:2|proxy:1|proxy:2|proxy:3|offline:*) exit 6 ;; missing:*) exit 22 ;; esac
while [ "$#" -gt 0 ]; do
    if [ "$1" = -o ]; then shift; printf complete > "$1"; break; fi
    shift
done
'''
    }
    for name, content in scripts.items():
        script = root / name
        script.write_text('#!/bin/sh\n' + content + '\n')
        script.chmod(0o755)
    env = dict(os.environ, PATH=str(root) + ':' + os.environ['PATH'],
               COUNT=str(root / 'count'), CALLS=str(root / 'calls'))
    for mode, attempts, ok in [('transient', 3, True), ('proxy', 4, True),
                               ('offline', 6, False), ('missing', 2, False)]:
        for name in ['count', 'calls', 'out']:
            (root / name).unlink(missing_ok=True)
        result = subprocess.run(['sh', '-ec', '. "$1"; fetch https://github.com/test "$2" 10',
                                 'test', str(source), str(root / 'out')],
                                env=dict(env, MODE=mode), capture_output=True)
        assert (result.returncode == 0) == ok, result.stderr
        assert int((root / 'count').read_text()) == attempts
        if ok:
            assert (root / 'out').read_text() == 'complete'
        else:
            assert not (root / 'out').exists()
        if mode == 'proxy':
            assert 'socks5h://127.0.0.1:1819' in (root / 'calls').read_text()
        print('PASS:', mode)
