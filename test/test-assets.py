#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
"""Verify the release generator publishes reconstructable standard packages."""
import gzip
import hashlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import zlib

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='gozarbin-assets-test-') as temporary:
    directory = Path(temporary)
    content = b'installed payload\0\xff' * 100000
    for release, extension in [('24.10.8', 'ipk'), ('25.12.5', 'apk')]:
        if extension == 'apk':
            compressor = zlib.compressobj(6, zlib.DEFLATED, -15)
            package = b'ADBd' + compressor.compress(content) + compressor.flush()
            name = 'gozarbin-2.2.2-r1.apk'
        else:
            raw = io.BytesIO()
            with tarfile.open(fileobj=raw, mode='w') as tar:
                for member, data in [('debian-binary', b'2.0\n'), ('data.tar.gz', gzip.compress(content))]:
                    entry = tarfile.TarInfo(member); entry.size = len(data)
                    tar.addfile(entry, io.BytesIO(data))
            package = gzip.compress(raw.getvalue())
            name = 'gozarbin_2.2.2-r1_x86_64.ipk'
        with tarfile.open(directory / f'gozarbin-openwrt-{release}-x86_64.tar.gz', 'w:gz') as tar:
            for package_name in [name, 'luci-app-' + name]:
                entry = tarfile.TarInfo(f'bundle/{package_name}'); entry.size = len(package)
                tar.addfile(entry, io.BytesIO(package))
    subprocess.run([sys.executable, str(ROOT / 'scripts/update-assets.py'), str(directory)], check=True)
    for manifest_file in directory.glob('*.chunks.json'):
        manifest = json.loads(manifest_file.read_text())
        path = directory / manifest['name']
        data = path.read_bytes()
        assert len(data) == manifest['size']
        assert hashlib.sha256(data).hexdigest() == manifest['sha256']
        for offset, length, sha in manifest['chunks']:
            assert hashlib.sha256(data[offset:offset + length]).hexdigest() == sha
        assert path.name.startswith('gozarbin-openwrt-') and path.name.endswith('.tar.gz')
        with tarfile.open(path) as bundle:
            members = bundle.getmembers()
            assert len(members) == 2
            assert any('/luci-app-gozarbin' in m.name for m in members)
            assert any('/gozarbin' in m.name for m in members)
            for member in members:
                data = bundle.extractfile(member).read()
                if member.name.endswith('.apk'):
                    assert zlib.decompress(data[4:], -15) == content
                else:
                    with tarfile.open(fileobj=io.BytesIO(data)) as package:
                        assert gzip.decompress(package.extractfile('data.tar.gz').read()) == content
        assert not list(directory.glob('*.ipk')) and not list(directory.glob('*.apk'))
    assert len(list(directory.glob('*.chunks.json'))) == 2
print('PASS: each target publishes one bundle containing both packages, exact payloads and a verified manifest')
