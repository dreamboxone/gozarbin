#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
"""Publish architecture-specific packages and authenticated chunk manifests."""
import json
import pathlib
import re
import sys
import tarfile
from package_chunks import normalize, index


def build(directory):
    for archive in directory.glob('gozarbin-openwrt-*.tar.gz'):
        match = re.fullmatch(r'gozarbin-openwrt-(\d+\.\d+)\.\d+-(.+)\.tar\.gz', archive.name)
        if not match:
            raise ValueError(f'Unexpected archive: {archive.name}')
        release, arch = match.groups()
        with tarfile.open(archive) as bundle:
            for member in bundle.getmembers():
                name = pathlib.PurePosixPath(member.name).name
                if not member.isfile() or not re.fullmatch(r'[A-Za-z0-9_.+-]+\.(apk|ipk)', name):
                    continue
                target = directory / f'{release}-{arch}-{name}'
                target.write_bytes(bundle.extractfile(member).read())
                normalize(target)
                target.with_name(target.name + '.chunks.json').write_text(
                    json.dumps(index(target), separators=(',', ':')), encoding='utf-8')


if __name__ == '__main__':
    build(pathlib.Path(sys.argv[1]))
