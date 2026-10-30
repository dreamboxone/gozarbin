#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
"""Verify independent rule downloads and successful-update timestamps."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / 'openwrt/files/usr/libexec/gozarbin'

def executable(path, body):
    path.write_text(body)
    path.chmod(0o755)

with tempfile.TemporaryDirectory(prefix='gozarbin-geo-') as directory:
    base = Path(directory)
    for name in ['bin', 'lib', 'geo', 'run']:
        (base / name).mkdir()
    (base / 'functions.sh').write_text('''config_load() { :; }
config_get() { eval "$1=fixture:$1"; }
config_get_bool() { eval "$1=0"; }
''')
    (base / 'lib/fetch.sh').write_text('''fetch() {
 echo "$1" >> "$FIXTURE/downloads"
 if [ "$1" = fixture:geosite_url ] && [ -e "$FIXTURE/fail" ]; then printf invalid > "$2"
 else printf SRSfixture > "$2"; fi
}
''')
    executable(base / 'bin/uci', '#!/bin/sh\nexit 1\n')
    executable(base / 'bin/logger', '#!/bin/sh\nexit 0\n')
    script = (LIB / 'geo-update.sh').read_text().replace('/lib/functions.sh', str(base / 'functions.sh')).replace('/usr/libexec/gozarbin/fetch.sh', str(base / 'lib/fetch.sh'))
    executable(base / 'update.sh', script)
    env = {**os.environ, 'PATH': str(base / 'bin') + ':' + os.environ['PATH'], 'FIXTURE': str(base),
           'GOZARBIN_GEO_DIR': str(base / 'geo'), 'GOZARBIN_GEO_RUN': str(base / 'run'), 'GOZARBIN_LIB': str(base / 'lib')}
    def download(target, expected=0):
        result = subprocess.run(['sh', str(base / 'update.sh'), target], env=env, capture_output=True, text=True)
        assert result.returncode == expected, result.stderr
    download('geoip')
    assert (base / 'geo/geoip-ir.srs').read_bytes() == b'SRSfixture'
    assert int((base / 'geo/.geoip-ir.updated').read_text()) > 0
    assert not (base / 'geo/geosite-ir.srs').exists()
    (base / 'geo/geosite-ir.srs').write_bytes(b'SRSprevious')
    (base / 'geo/.geosite-ir.updated').write_text('123')
    (base / 'fail').touch()
    download('geosite', 1)
    assert (base / 'geo/geosite-ir.srs').read_bytes() == b'SRSprevious'
    assert (base / 'geo/.geosite-ir.updated').read_text() == '123'
    download('ads')
    assert (base / 'geo/geosite-ads.srs').is_file()
    assert int((base / 'geo/.geosite-ads.updated').read_text()) > 0
    assert (base / 'downloads').read_text().splitlines() == ['fixture:geoip_url', 'fixture:geosite_url', 'fixture:ads_url']
    executable(base / 'lib/aether-core.sh', '''#!/bin/sh
if [ "$1" = status ]; then echo '{"state":"idle","detail":""}'
else printf '%s' "$GOZARBIN_GEO_TARGET" > "$FIXTURE/selected"; fi
''')
    wrapper = LIB / 'geo-core.sh'
    result = subprocess.run(['sh', str(wrapper), 'update', 'ads'], env=env, capture_output=True, text=True)
    assert result.returncode == 0 and (base / 'selected').read_text() == 'ads', result.stderr
    result = subprocess.run(['sh', str(wrapper), 'status'], env=env, capture_output=True, text=True)
    state = json.loads(result.stdout)
    assert state['target'] == 'ads' and state['files']['geosite'] == 123 and state['files']['geoip'] > 0 and state['files']['ads'] > 0
    assert subprocess.run(['sh', str(wrapper), 'update', '../invalid'], env=env).returncode == 2
    print('PASS: each rule downloads independently, failed downloads preserve files and timestamps, status reports each successful update')
