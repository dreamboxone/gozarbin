#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
"""Measure HTTP URL-test timing through the proxy, with no direct fallback."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

SCRIPT = Path(__file__).resolve().parents[1] / 'openwrt/files/usr/libexec/gozarbin/connectivity.sh'
with tempfile.TemporaryDirectory(prefix='gozarbin-connectivity-test-') as directory:
    base = Path(directory)
    (base / 'bin').mkdir()
    def executable(name, body):
        path = base / 'bin' / name
        path.write_text(body)
        path.chmod(0o755)
    executable('uci', '#!/bin/sh\ncase "$*" in *socks_port) echo 1819 ;; *socks_address) echo 0.0.0.0 ;; esac\n')
    executable('curl', '''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
a=sys.argv[1:]; base=Path(os.environ['FIXTURE'])
assert a[a.index('--proxy')+1]=='socks5h://127.0.0.1:1819'
assert a[a.index('--noproxy')+1]==''
assert '--max-time' in a
with (base/'calls').open('a') as output: output.write(json.dumps(a)+'\\n')
if 'https://www.gstatic.com/generate_204' in a:
 if (base/'fail').exists(): sys.exit(7)
 print('200 0.1234' if (base/'wrong-code').exists() else '204 0.1234')
else:
 assert 'https://www.cloudflare.com/cdn-cgi/trace' in a
 Path(a[a.index('-o')+1]).write_text('loc=SE\\nip=fixture\\n')
''')
    env = {**os.environ, 'PATH': str(base / 'bin') + ':' + os.environ['PATH'], 'FIXTURE': str(base),
           'GOZARBIN_CONNECT_RUN': str(base / 'run'), 'GOZARBIN_CONNECT_PID': '123'}
    def run(action):
        result = subprocess.run(['sh', str(SCRIPT), action], env=env, capture_output=True, text=True)
        assert result.returncode == 0, result.stderr
        return result.stdout
    run('worker')
    state = json.loads((base / 'run/state.json').read_text())
    assert state == {'ping': 123, 'country': 'SE'}
    assert json.loads(run('status')) == state
    assert len((base / 'calls').read_text().splitlines()) == 2
    (base / 'fail').touch()
    run('worker')
    assert json.loads((base / 'run/state.json').read_text()) == {'ping': None, 'country': 'SE'}
    (base / 'fail').unlink()
    (base / 'wrong-code').touch()
    run('worker')
    assert json.loads((base / 'run/state.json').read_text())['ping'] is None
    assert len((base / 'calls').read_text().splitlines()) == 6
    print('PASS: URL-test uses actual HTTP time through Gozarbin, caches results, reads exit country and rejects failures/non-204 responses')
