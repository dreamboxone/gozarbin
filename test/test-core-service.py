#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
"""Check actual init arguments and advanced environment without starting services."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


with tempfile.TemporaryDirectory(prefix='gozarbin-service-') as temporary:
    base = Path(temporary)
    lib = base / 'lib'; lib.mkdir()
    share = base / 'share'; share.mkdir()
    (share / 'core-options.json').write_bytes((ROOT / 'openwrt/files/usr/share/gozarbin/core-options.json').read_bytes())

    def script(name, text):
        path = lib / name
        path.write_text(text)
        path.chmod(0o755)
        return path

    core = script('core', '#!/bin/sh\nprintf "%s\\n" "$CORE_HELP"\n')
    script('aether-core.sh', f'''#!/bin/sh
case "$1" in
 path) echo '{core}' ;;
 pt-path) echo '{lib}/pt' ;;
 psiphon-path) echo '{lib}/psiphon' ;;
esac
''')
    script('psiphon', '#!/bin/sh\nexit 0\n')
    for name in ['firewall.sh', 'dns.sh', 'deps.sh']:
        script(name, '#!/bin/sh\nexit 0\n')
    script('passwall2-detect.sh', '#!/bin/sh\nexit 1\n')
    script('singbox.sh', f'#!/bin/sh\necho "{lib}/sing-box"\n')
    script('jsonfilter', r'''#!/usr/bin/env python3
import json,sys
with open(sys.argv[2]) as f: data=json.load(f)
for row in data['options']: print(row['env'])
''')
    config_reader = script('read-config', '''#!/usr/bin/env python3
import json,os,sys
data=json.loads(os.environ['TEST_CONFIG'])
if sys.argv[1] not in data: sys.exit(1)
print(data[sys.argv[1]])
''')
    capture = script('capture', '''#!/usr/bin/env python3
import json,os,sys
with open(os.environ['TEST_LOG'],'a') as f: f.write(json.dumps(sys.argv[1:])+'\\n')
''')
    functions = base / 'functions.sh'
    functions.write_text(f'''config_load() {{ :; }}
config_get() {{
 local raw
 if raw=$({config_reader} "$3"); then :; else raw=${{4:-}}; fi
 eval "$1=\\$raw"
}}
config_get_bool() {{ config_get "$@"; }}
procd_open_instance() {{ :; }}
procd_close_instance() {{ :; }}
procd_set_param() {{ {capture} "$@"; }}
procd_append_param() {{ {capture} "$@"; }}
''')
    source = (ROOT / 'openwrt/files/etc/init.d/gozarbin').read_text()
    source = source.replace('. /lib/functions.sh', f'. {functions}')
    source = source.replace('/usr/libexec/gozarbin', str(lib)).replace('/usr/share/gozarbin', str(share))
    source = source.replace('/var/run/gozarbin', str(base / 'run'))
    init = base / 'init.sh'
    init.write_text(source + '\nstop_psiphon() { :; }\nstart_service\n')

    def run(protocol, tor='off', modern=True):
        log = base / 'calls.jsonl'
        log.write_text('')
        value = 'example.com; $(touch should-not-exist)'
        config = dict(enabled='1', mode='socks', protocol=protocol, psiphon='off', tor=tor,
                      masque_transport='h2', enroll_address='1.1.1.1', peer='1.1.1.1:443',
                      outer_peer='162.159.199.1:443', inner_peer='162.159.193.1:2408',
                      core_masque_sni=value, core_tls13_ciphers='TLS_AES_128_GCM_SHA256')
        env = dict(os.environ, PATH=str(lib) + ':' + os.environ['PATH'],
                   TEST_CONFIG=json.dumps(config), TEST_LOG=str(log),
                   CORE_HELP='--api-address' if modern else '--enroll-address')
        result = subprocess.run(['sh', str(init)], cwd=base, env=env, capture_output=True, text=True)
        assert result.returncode == 0, result.stderr
        calls = [json.loads(row) for row in log.read_text().splitlines()]
        commands = [row[1:] for row in calls if row[0] == 'command']
        command = commands[0]
        for row in commands[1:]:
            if row and row[0].startswith('--'): command += row
        exported = [arg for row in calls if row[0] == 'env' for arg in row[1:]]
        assert 'AETHER_MASQUE_SNI=' + value in exported
        assert 'AETHER_TLS13_CIPHERS=TLS_AES_128_GCM_SHA256' in exported
        assert not (base / 'should-not-exist').exists()
        assert '--h2' in command
        assert ('--api-address' if modern else '--enroll-address') in command
        if protocol == 'gool': assert '--gool-classic' in command and '--wiw-outer' in command and '--wiw-inner' in command
        elif protocol == 'mim': assert '--mim-outer' in command and '--mim-inner' in command
        elif protocol == 'gool_masque': assert '--gool-peer' in command and command[command.index('--protocol') + 1] == 'gool'
        else: assert '--peer' in command
        if tor == 'chain':
            assert '--tor' in command
            assert command[command.index('--bind') + 1] == '127.0.0.1:1826'
            assert command[command.index('--tor-bind') + 1] == '127.0.0.1:1819'
        elif tor == 'only': assert '--tor-only' in command
        elif tor == 'reverse': assert '--tor-reverse' in command
        print('PASS:', protocol, tor, 'modern' if modern else 'legacy', 'arguments and literal advanced settings')

    for protocol in ['masque', 'wg', 'gool', 'mim', 'gool_masque']:
        run(protocol)
    for tor in ['chain', 'reverse', 'only']:
        run('masque', tor)
    run('masque', modern=False)
