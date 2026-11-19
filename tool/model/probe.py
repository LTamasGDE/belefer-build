"""A kész modellfájl beolvasása és kipróbálása (a Dart-oldali olvasó mása).

    python3 tool/model/probe.py "tegnap a lidlben 4500" "lemondtam a netflixet"
"""

from __future__ import annotations

import math
import struct
import sys
from pathlib import Path

from textproc import raw_tokens, sequence_features, token_features, vectorize, words

ROOT = Path(__file__).resolve().parents[2]


class Reader:
    def __init__(self, data: bytes):
        self.data = data
        self.offset = 0

    def take(self, n):
        chunk = self.data[self.offset:self.offset + n]
        self.offset += n
        return chunk

    def u8(self):
        return self.take(1)[0]

    def unpack(self, fmt):
        size = struct.calcsize(fmt)
        return struct.unpack(fmt, self.take(size))[0]

    def varint(self):
        result = shift = 0
        while True:
            byte = self.u8()
            result |= (byte & 0x7F) << shift
            if not byte & 0x80:
                return result
            shift += 7

    def short(self):
        return self.take(self.u8()).decode('ascii')


def load(path=ROOT / 'assets/model/belefer_model.bin'):
    r = Reader(path.read_bytes())
    assert r.take(4) == b'BLFM'
    version = r.unpack('<H')
    dim_bits = r.u8()
    flags = {}
    for _ in range(r.u8()):
        name = r.short()
        raw = r.take(r.unpack('<I')).decode('ascii')
        flags[name] = set(raw.split('\n')) if raw else set()
    heads = {}
    for _ in range(r.u8()):
        name = r.short()
        kind = r.u8()
        labels = [r.short() for _ in range(r.u8())]
        scale = r.unpack('<f')
        bias = [r.unpack('<f') for _ in labels]
        entries = {}
        col = 0
        for _ in range(r.unpack('<I')):
            col += r.varint()
            label = r.u8()
            value = r.unpack('<b')
            entries.setdefault(col, []).append((label, value))
        heads[name] = (kind, labels, scale, bias, entries)
    return version, dim_bits, flags, heads


def probs(head, idx, weight):
    _, labels, scale, bias, entries = head
    sums = [0] * len(labels)
    for col in idx:
        for label, value in entries.get(col, ()):
            sums[label] += value
    logits = [bias[c] + scale * weight * sums[c] for c in range(len(labels))]
    top = max(logits)
    exps = [math.exp(v - top) for v in logits]
    total = sum(exps)
    return [e / total for e in exps]


def main(texts):
    version, dim_bits, flags, heads = load()
    for text in texts:
        print(f'„{text}”')
        idx, weight = vectorize(sequence_features(words(text)))
        for name in ('category', 'intent', 'status'):
            p = probs(heads[name], idx, weight)
            ranked = sorted(zip(heads[name][1], p), key=lambda x: -x[1])[:3]
            print(f'  {name:9s}', ', '.join(f'{l} {v:.2f}' for l, v in ranked))
        tokens = raw_tokens(text)
        tags = []
        for i in range(len(tokens)):
            idx_t, w_t = vectorize(token_features(tokens, i, flags))
            tags.append(f'{tokens[i]}:{probs(heads["title"], idx_t, w_t)[1]:.2f}')
        print('  title    ', ' '.join(tags))


if __name__ == '__main__':
    main(sys.argv[1:])
