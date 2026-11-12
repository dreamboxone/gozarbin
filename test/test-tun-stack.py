#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
"""Check TUN configuration compatibility across sing-box core versions."""
import json
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = (root / 'openwrt/files/usr/libexec/gozarbin/firewall.sh').read_bytes().decode('latin1')
functions = source[source.index('legacy_tun_stack() {'):source.index('\n# The resolver the WAN')]
fixture = '''
fake_box() { printf 'sing-box version %s\\n' "$version"; }
singbox=fake_box
mode=tun
tun_name=test-tun
tun_address=172.19.0.1/30
tun_address6=fdfe:dcba:9876::1/126
tun_mtu=9000
'''
for version, legacy in [('1.14.4', True), ('1.9.7', True), ('1.15.0-alpha.13', False),
                        ('1.15.0', False), ('1.16.0', False), ('2.0.0', False), ('unknown', True)]:
    result = subprocess.run(['sh'], input=functions + fixture + f'\nversion={version}\ninbound\n',
                            text=True, capture_output=True, check=True)
    config = json.loads(result.stdout)
    assert (config.get('stack') == 'system') == legacy, (version, config)
    assert legacy or 'stack' not in config, (version, config)
    assert config['address'] == ['172.19.0.1/30', 'fdfe:dcba:9876::1/126']
    assert config['auto_route'] and config['strict_route'] and config['mtu'] == 9000
print('PASS: new TUN stack on sing-box 1.15+, legacy stack on older or unknown cores')
