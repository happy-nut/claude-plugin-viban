#!/usr/bin/env python3
"""Persistent Python coprocess for TUI rendering.

Stays resident and handles Unicode display width calculations
via stdin/stdout protocol, eliminating per-frame Python spawn overhead.

Protocol:
  BATCH_TRUNC        - truncate strings + compute display widths
  BATCH_WIDTH        - compute display widths only
  QUIT               - shutdown
"""

import sys
import unicodedata


def display_width(s):
    return sum(2 if unicodedata.east_asian_width(c) in 'FW' else 1 for c in s)


def truncate(s, max_w):
    w = 0
    for i, c in enumerate(s):
        cw = 2 if unicodedata.east_asian_width(c) in 'FW' else 1
        if w + cw > max_w:
            return s[:i]
        w += cw
    return s


def handle_batch_trunc():
    results = []
    for line in sys.stdin:
        line = line.rstrip('\n')
        if line == 'END':
            break
        if not line:
            continue
        parts = line.split('\t', 2)
        max_w = int(parts[0])
        pfx = parts[1]
        txt = parts[2] if len(parts) > 2 else ''
        t = truncate(txt, max_w)
        results.append(f'{t}\t{display_width(pfx + t)}')
    sys.stdout.write('\n'.join(results) + '\nEND\n')
    sys.stdout.flush()


def handle_batch_width():
    results = []
    for line in sys.stdin:
        line = line.rstrip('\n')
        if line == 'END':
            break
        results.append(str(display_width(line)))
    sys.stdout.write('\n'.join(results) + '\nEND\n')
    sys.stdout.flush()


def main():
    for line in sys.stdin:
        cmd = line.strip()
        if cmd == 'QUIT':
            break
        elif cmd == 'BATCH_TRUNC':
            handle_batch_trunc()
        elif cmd == 'BATCH_WIDTH':
            handle_batch_width()


if __name__ == '__main__':
    main()
