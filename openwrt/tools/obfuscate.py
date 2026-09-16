#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 dreamboxone
"""Strip the shipped shell, JavaScript and CSS files down before packaging.

What ends up on a router is then the working code and nothing else: no comments
explaining how it works, no blank lines, no indentation to read it by. The SPDX
and copyright header of every file is kept, because the licence requires it and
because it is the part worth leaving behind.

This is deliberately conservative. Nothing is renamed and nothing is re-encoded,
so a file that worked before is the same program afterwards. It raises the cost
of lifting the code; it is not a lock, and it cannot be one: AGPL-3.0 gives every
recipient the right to the real source, which lives in the repository. The thing
that stops someone republishing this under their own name is the licence and the
trademark notice, not this script.

    obfuscate.py <file-or-directory>...
    obfuscate.py --check <file-or-directory>...   report, change nothing
"""

import argparse
import os
import re
import sys

SHELL_SUFFIXES = ('.sh',)
HEREDOC = re.compile(r'<<-?\s*(["\']?)([A-Za-z_][A-Za-z0-9_]*)\1')


def is_shell(path):
    if path.endswith(SHELL_SUFFIXES):
        return True
    try:
        with open(path, 'rb') as handle:
            first = handle.readline()
    except OSError:
        return False
    return first.startswith(b'#!') and (b'sh' in first or b'rc.common' in first)


def license_header(lines, comment='#'):
    """The leading comment block, as long as it mentions the licence."""
    header = []
    for line in lines:
        stripped = line.strip()
        if comment == '#':
            if stripped.startswith('#!') or stripped.startswith('#'):
                header.append(line)
                continue
        else:
            if stripped.startswith('/*') or stripped.startswith('*') or stripped.startswith('//'):
                header.append(line)
                if stripped.endswith('*/'):
                    break
                continue
        break
    return header if any('SPDX-License-Identifier' in line for line in header) else []


def strip_shell(text):
    lines = text.split('\n')
    header = license_header(lines)
    out = list(header)
    terminator = None
    for index, line in enumerate(lines):
        if index < len(header):
            continue
        if terminator is not None:
            out.append(line)
            if line.strip() == terminator:
                terminator = None
            continue
        stripped = line.strip()
        # A line whose first non-blank character is # is always a comment in sh,
        # and an empty line never carries meaning outside a here-document.
        if not stripped or (stripped.startswith('#') and not stripped.startswith('#!')):
            continue
        out.append(line.rstrip())
        match = HEREDOC.search(line)
        if match:
            terminator = match.group(2)
    return '\n'.join(out).rstrip() + '\n'


def strip_c_comments(text, keep):
    """Remove /* */ and // comments without touching strings or regex literals."""
    out = []
    i = 0
    length = len(text)
    while i < length:
        char = text[i]
        if char in '"\'`':
            quote = char
            out.append(char)
            i += 1
            while i < length:
                out.append(text[i])
                if text[i] == '\\':
                    i += 1
                    if i < length:
                        out.append(text[i])
                    i += 1
                    continue
                if text[i] == quote:
                    i += 1
                    break
                i += 1
            continue
        if char == '/' and i + 1 < length and text[i + 1] == '*':
            end = text.find('*/', i + 2)
            end = length if end < 0 else end + 2
            block = text[i:end]
            if block in keep:
                out.append(block)
            i = end
            continue
        if char == '/' and i + 1 < length and text[i + 1] == '/':
            # Only a line comment when nothing but whitespace precedes it on the
            # line; anything else could be a division or a regular expression.
            line_start = text.rfind('\n', 0, i) + 1
            if text[line_start:i].strip() == '':
                end = text.find('\n', i)
                i = length if end < 0 else end
                continue
            out.append(char)
            i += 1
            continue
        out.append(char)
        i += 1
    return ''.join(out)


def c_license_header(text):
    """The leading /* */ block reduced to its licence and copyright lines."""
    match = re.match(r'\s*/\*.*?\*/', text, re.S)
    if not match or 'SPDX-License-Identifier' not in match.group(0):
        return ''
    kept = [
        re.sub(r'^\s*(?:/\*|\*)?\s?', '', line).rstrip()
        for line in match.group(0).split('\n')
        if 'SPDX-License-Identifier' in line or 'Copyright' in line
    ]
    return '/* ' + '\n * '.join(kept) + ' */'


def strip_js(text):
    header = c_license_header(text)
    lines = strip_c_comments(text, set()).split('\n')
    lines = [line.strip('\t ') for line in lines if line.strip()]
    out = '\n'.join(lines).strip()
    return (header + '\n' + out if header else out) + '\n'


def strip_css(text):
    header = c_license_header(text)
    body = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    body = re.sub(r'\s*([{}:;,>])\s*', r'\1', body)
    body = re.sub(r';\}', '}', body)
    body = re.sub(r'\s+', ' ', body).strip()
    return (header + '\n' + body if header else body) + '\n'


def process(path, check):
    with open(path, encoding='utf-8') as handle:
        original = handle.read()
    if path.endswith('.js'):
        result = strip_js(original)
    elif path.endswith('.css'):
        result = strip_css(original)
    elif is_shell(path):
        result = strip_shell(original)
    else:
        return None
    if not check and result != original:
        with open(path, 'w', encoding='utf-8', newline='\n') as handle:
            handle.write(result)
    return len(original), len(result)


def walk(targets):
    for target in targets:
        if os.path.isfile(target):
            yield target
        for root, _dirs, files in os.walk(target):
            for name in sorted(files):
                yield os.path.join(root, name)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('targets', nargs='+')
    parser.add_argument('--check', action='store_true', help='report without writing')
    args = parser.parse_args()

    before = after = 0
    for path in walk(args.targets):
        sizes = process(path, args.check)
        if sizes is None:
            continue
        before += sizes[0]
        after += sizes[1]
        print('%-60s %6d -> %6d bytes' % (path, sizes[0], sizes[1]))
    if before:
        print('total %d -> %d bytes (%.0f%% smaller)' % (before, after, (1 - after / before) * 100))
    return 0


if __name__ == '__main__':
    sys.exit(main())
