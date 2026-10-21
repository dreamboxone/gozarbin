#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
"""Publish one install bundle per target with a differential manifest."""
import io
import json
import pathlib
import re
import sys
import tarfile
import tempfile
from package_chunks import normalize, index, compress_ranges


def build(directory):
    for archive in directory.glob('gozarbin-openwrt-*.tar.gz'):
        match = re.fullmatch(r'gozarbin-openwrt-(\d+\.\d+)\.\d+-(.+)\.tar\.gz', archive.name)
        if not match:
            raise ValueError(f'Unexpected archive: {archive.name}')
        packages = []
        with tarfile.open(archive) as bundle:
            for member in bundle.getmembers():
                name = pathlib.PurePosixPath(member.name).name
                if not member.isfile() or not re.fullmatch(r'[A-Za-z0-9_.+-]+\.(apk|ipk)', name):
                    continue
                if member.size > 134217728:
                    raise ValueError(f'Package too large: {name}')
                packages.append((name, bundle.extractfile(member).read()))
        names = [name for name, _ in packages]
        if (len(names) != 2 or len(set(names)) != 2 or
                sum(bool(re.fullmatch(r'gozarbin[-_][0-9].*\.(apk|ipk)', n)) for n in names) != 1 or
                sum(bool(re.fullmatch(r'luci-app-gozarbin[-_][0-9].*\.(apk|ipk)', n)) for n in names) != 1 or
                len({pathlib.Path(n).suffix for n in names}) != 1):
            raise ValueError(f'Bundle must contain matching gozarbin and LuCI packages: {archive.name}')
        raw = io.BytesIO()
        with tempfile.TemporaryDirectory(prefix='gozarbin-packages-') as temporary:
            with tarfile.open(fileobj=raw, mode='w', format=tarfile.GNU_FORMAT) as output:
                for name, data in sorted(packages):
                    target = pathlib.Path(temporary) / name
                    target.write_bytes(data)
                    normalize(target)
                    data = target.read_bytes()
                    entry = tarfile.TarInfo(archive.name.removesuffix('.tar.gz') + '/' + name)
                    entry.size = len(data)
                    entry.mode = 0o644
                    output.addfile(entry, io.BytesIO(data))
        archive.write_bytes(compress_ranges(raw.getvalue(), 31))
        archive.with_name(archive.name + '.chunks.json').write_text(
            json.dumps(index(archive), separators=(',', ':')), encoding='utf-8')


if __name__ == '__main__':
    build(pathlib.Path(sys.argv[1]))
