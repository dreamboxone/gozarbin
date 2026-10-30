#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
"""Exercise isolated core updates without changing the router or fetching releases."""
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'openwrt/files/usr/libexec/gozarbin/aether-core.sh'
SCHEMA = ROOT / 'openwrt/files/usr/share/gozarbin/core-options.json'


def executable(path, body):
    path.write_text(body)
    path.chmod(0o755)


def fixture(base, corrupt=False, unsafe=False, running=False, restart_fail=False, provider="aether", prerelease=False, release_version=None):
    for directory in ['lib', 'bin', 'run', 'core', 'release']:
        (base / directory).mkdir()
    version = release_version or ('1.14.4' if provider == 'singbox' else '2.4.0')
    asset = f'sing-box-{version}-linux-armv7.tar.gz' if provider == 'singbox' else 'aether-linux-armv7-musl.tar.gz'
    prefix = f'sing-box-{version}-linux-armv7/' if provider == 'singbox' else ''
    (base / 'lib/releases.sh').write_text((ROOT / 'openwrt/files/usr/libexec/gozarbin/releases.sh').read_text())
    executable(base / 'bundled', '#!/bin/sh\necho "' + ('sing-box version 1.13.0' if provider == 'singbox' else 'aether 2.3.0') + '"\n')
    executable(base / 'service', '''#!/bin/sh
echo "$1" >> "$FIXTURE/service.log"
case "$1" in
 running) test -e "$FIXTURE/running" ;;
 restart) if test -e "$FIXTURE/restart-fail"; then rm "$FIXTURE/restart-fail"; exit 1; fi ;;
esac
''')
    if running:
        (base / 'running').touch()
    if restart_fail:
        (base / 'restart-fail').touch()
    executable(base / 'bin/jsonfilter', r'''#!/usr/bin/env python3
import json,sys,re
a=sys.argv
with open(a[a.index('-i')+1]) as f: data=json.load(f)
expr=a[a.index('-e')+1][1:]
if expr=='.options[*].env':
 for row in data['options']: print(row['env'])
else:
 for item in re.findall(r'\.([\w]+)|\[(\d+)\]',expr): data=data[item[0]] if item[0] else data[int(item[1])]
 print(json.dumps(data) if isinstance(data,(dict,list,bool)) else data)
''')
    executable(base / 'bin/uci', '#!/bin/sh\nexit 1\n')
    (base / 'lib/fetch.sh').write_text('''fetch() {
 case "$1" in
  */releases/latest|*/releases?per_page=20) cp "$FIXTURE/release/release.json" "$2" ;;
  */SHA256SUMS.txt) cp "$FIXTURE/release/SHA256SUMS.txt" "$2" ;;
  *.tar.gz) cp "$FIXTURE/release/archive.tar.gz" "$2" ;;
  *) return 1 ;;
 esac
}
''')
    archive = base / 'release/archive.tar.gz'
    with tarfile.open(archive, 'w:gz') as tar:
        for name, data in [
            ('sing-box' if provider == 'singbox' else 'aether', ('#!/bin/sh\necho "' + ('sing-box version ' if provider == 'singbox' else 'aether ') + version + '"\n').encode()),
            ('LICENSES/NOTICE', b'required notices'),
            ('pt/psiphon-tunnel-core', b'#!/bin/sh\nexit 0\n'),
        ] + ([('../escape', b'unsafe')] if unsafe else []):
            entry = tarfile.TarInfo(prefix + name if not name.startswith("../") else name)
            entry.size = len(data)
            entry.mode = 0o755 if name != 'LICENSES/NOTICE' else 0o644
            tar.addfile(entry, io.BytesIO(data))
    checksum = '0' * 64 if corrupt else hashlib.sha256(archive.read_bytes()).hexdigest()
    (base / 'release/SHA256SUMS.txt').write_text(checksum + '  ' + asset + '\n')
    release = {'tag_name': 'v' + version, 'prerelease': prerelease, 'draft': False, 'assets': [
        {'name': asset, 'size': archive.stat().st_size, 'digest': 'sha256:' + checksum}]}
    if prerelease:
        release = [{'tag_name': 'v99.0.0', 'draft': True}, release, {'tag_name': 'v1.0.0', 'prerelease': False}]
    (base / 'release/release.json').write_text(json.dumps(release))
    return {**os.environ, 'PATH': str(base / 'bin') + ':' + os.environ['PATH'],
            'FIXTURE': str(base), 'GOZARBIN_LIB': str(base / 'lib'),
            'GOZARBIN_CORE_ROOT': str(base / 'core'), 'GOZARBIN_CORE_RUN': str(base / 'run'),
            'GOZARBIN_CORE_ARCH': 'armv7l', 'GOZARBIN_CORE_PROVIDER': provider, 'GOZARBIN_BUNDLED_CORE': str(base / 'bundled'),
            'GOZARBIN_CORE_SERVICE': str(base / 'service'), 'GOZARBIN_CORE_SCHEMA': str(SCHEMA)}


def run_case(name, *, action='worker-install', expected='done', **options):
    with tempfile.TemporaryDirectory(prefix='gozarbin-core-') as directory:
        base = Path(directory)
        env = fixture(base, **options)
        result = subprocess.run(['sh', str(SCRIPT), action], env=env, capture_output=True, text=True)
        state = json.loads((base / 'run/state.json').read_text())
        if options.get('prerelease'):
            assert state['prerelease'] is True
        assert state['state'] == expected, (name, state, result.stderr, result.stdout)
        assert (result.returncode == 0) == (expected != 'error'), (name, result.stderr)
        installed = base / ('core/current/sing-box' if options.get('provider') == 'singbox' else 'core/current/gozarbin')
        if name.endswith('verified install'):
            assert installed.is_file()
            assert (base / 'core/current/LICENSES/NOTICE').read_text() == 'required notices'
            assert not (base / 'service.log').read_text().strip().endswith('restart')
        elif expected == 'error':
            assert not installed.exists(), (name, 'previous bundled core must remain selected')
            assert not (base / 'escape').exists()
        elif action == 'worker-check':
            assert not installed.exists()
            assert not (base / 'service.log').exists()
        if options.get('restart_fail'):
            assert (base / 'service.log').read_text().splitlines()[-2:] == ['restart', 'restart']
        print('PASS:', name)


run_case('release check does not install', action='worker-check', expected='available')
run_case('verified install')
run_case('sing-box verified install', provider='singbox')
run_case('sing-box digest mismatch rejected', provider='singbox', corrupt=True, expected='error')
run_case('corrupt download rejected', corrupt=True, expected='error')
run_case('unsafe archive rejected', unsafe=True, expected='error')
run_case('restart failure restores bundled core', running=True, restart_fail=True, expected='error')
run_case('Aether prerelease verified install', prerelease=True, release_version='2.5.0-beta.1')
run_case('sing-box prerelease verified install', provider='singbox', prerelease=True, release_version='1.15.0-alpha.1')

with tempfile.TemporaryDirectory(prefix='gozarbin-register-') as directory:
    base = Path(directory)
    env = fixture(base)
    executable(base / 'bin/timeout', '#!/bin/sh\nexit 127\n')
    executable(base / 'bundled', '''#!/bin/sh
if [ "$1" = --register ]; then
 [ "$2" = all ] && [ "$3" = --config ] || exit 2
 echo registered > "$FIXTURE/registered"
else echo 'aether 2.3.0'; fi
''')
    result = subprocess.run(['sh', str(SCRIPT), 'worker-register'], env=env, capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, result.stderr
    assert (base / 'registered').exists()
    assert json.loads((base / 'run/state.json').read_text())['detail'] == 'registered'
    print('PASS: registration works without a timeout utility')

bounded = SCRIPT.read_text().split('bounded_run() {', 1)[1].split('\ncore_path()', 1)[0]
result = subprocess.run(['sh', '-c', 'bounded_run() {' + bounded + '\nbounded_run 1 sleep 10'], capture_output=True, text=True, timeout=5)
assert result.returncode != 0
print('PASS: registration watchdog terminates an unresponsive process')

with tempfile.TemporaryDirectory(prefix='gozarbin-version-cache-') as directory:
    base = Path(directory)
    env = fixture(base)
    executable(base / 'bin/stat', '#!/bin/sh\nexit 127\n')
    executable(base / 'bundled', '#!/bin/sh\necho version >> "$FIXTURE/version-calls"\necho "aether 2.3.0"\n')
    for _ in range(2):
        result = subprocess.run(['sh', str(SCRIPT), 'version'], env=env, capture_output=True, text=True)
        assert result.returncode == 0 and result.stdout.strip() == '2.3.0', result.stderr
    assert (base / 'version-calls').read_text().splitlines() == ['version']
    executable(base / 'replacement', '#!/bin/sh\necho version >> "$FIXTURE/version-calls"\necho "aether 2.4.0"\n')
    (base / 'replacement').replace(base / 'bundled')
    result = subprocess.run(['sh', str(SCRIPT), 'version'], env=env, capture_output=True, text=True)
    assert result.stdout.strip() == '2.4.0'
    assert len((base / 'version-calls').read_text().splitlines()) == 2
    print('PASS: version cache works without stat and refreshes after core replacement')

schema = json.loads(SCHEMA.read_text())
import re
cli = (ROOT / 'aether/src/cli.rs').read_text()
help_text = cli.split('Environment variables:', 1)[1].split('After startup', 1)[0]
advertised = set(re.findall(r'^  (AETHER_[A-Z0-9_]+)', help_text, re.MULTILINE))
mapped = set(schema['integrated']) | set(schema['lifecycle']) | {row['env'] for row in schema['options']}
assert advertised == mapped, (advertised - mapped, mapped - advertised)
assert len(schema['options']) == len({row['key'] for row in schema['options']})
for option in schema['options']:
    assert len(option['help']['fa']) > 25 and len(option['help']['en']) > 25
    assert option['default_hint']['fa'] and option['default_hint']['en']
print('PASS: all', len(advertised), 'advertised Aether variables have a documented control or operation')
