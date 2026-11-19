"""A Belefér-modell szövegfeldolgozása.

Ez a fájl a Dart-oldali `lib/domain/model/features.dart` pontos mása: ugyanaz
az egyszerűsítés, szavakra bontás, jellemzők és hash. Ha itt bármi változik,
ott is változnia kell (a `test/fixtures/model_golden.json` ezt ellenőrzi).
"""

from __future__ import annotations

import math
import re

ACCENTS = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'ő': 'o', 'õ': 'o', 'ỗ': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ű': 'u', 'ũ': 'u',
    'ç': 'c', 'ñ': 'n', 'ß': 'ss',
}

TOKEN = re.compile(r'\d+(?:[.,]\d+)*[a-z]*|[a-z]+')
NUMBER = re.compile(r'^\d+(?:[.,]\d+)*([a-z]*)$')

DIM_BITS = 18
DIM = 1 << DIM_BITS


def light_fold(text: str) -> str:
    """`foldKeepingPunctuation`: kisbetű, ékezet nélkül, karakterenként."""
    out = []
    for ch in text:
        low = ch.lower()
        folded = ''.join(ACCENTS.get(c, c) for c in (low or ch))
        out.append(folded[0] if folded else ' ')
    return ''.join(out)


def words(text: str) -> list[str]:
    """Szavak: a számok helyén `#`, a számhoz tapadt betűk külön szóként."""
    result = []
    for token in TOKEN.findall(light_fold(text)):
        match = NUMBER.match(token)
        if match:
            result.append('#')
            if match.group(1):
                result.append(match.group(1))
        else:
            result.append(token)
    return result


def raw_tokens(text: str) -> list[str]:
    """A Dart `tokenize` egyszerűsített tokenjei (a megnevezés-jelölőhöz)."""
    return TOKEN.findall(light_fold(text))


def fnv1a(text: str) -> int:
    h = 0x811C9DC5
    for byte in text.encode('ascii'):
        h ^= byte
        h = (h * 0x01000193) & 0xFFFFFFFF
    return h


def bucket(feature: str) -> int:
    return fnv1a(feature) & (DIM - 1)


def sequence_features(ws: list[str]) -> list[str]:
    feats = []
    for i, w in enumerate(ws):
        feats.append('w:' + w)
        if i + 1 < len(ws):
            feats.append('b:' + w + '_' + ws[i + 1])
        if w != '#' and len(w) >= 3:
            padded = '<' + w + '>'
            for n in (3, 4, 5):
                for j in range(len(padded) - n + 1):
                    feats.append('c:' + padded[j:j + n])
    return feats


def vectorize(feats: list[str]) -> tuple[list[int], float]:
    """Egyedi hash-indexek és az egyenletes súly (1/√n)."""
    idx = sorted({bucket(f) for f in feats})
    if not idx:
        return [], 0.0
    return idx, 1.0 / math.sqrt(len(idx))


def token_features(tokens: list[str], i: int, flags: dict[str, set[str]]) -> list[str]:
    def norm(t: str) -> str:
        return '#' if t[0].isdigit() else t

    w = norm(tokens[i])
    prev1 = norm(tokens[i - 1]) if i > 0 else '^'
    prev2 = norm(tokens[i - 2]) if i > 1 else '^'
    next1 = norm(tokens[i + 1]) if i + 1 < len(tokens) else '$'
    next2 = norm(tokens[i + 2]) if i + 2 < len(tokens) else '$'
    feats = [
        't:' + w,
        'p1:' + prev1,
        'p2:' + prev2,
        'n1:' + next1,
        'n2:' + next2,
        'pw:' + prev1 + '_' + w,
        'wn:' + w + '_' + next1,
        'len:' + str(min(len(w), 9)),
    ]
    if w != '#':
        feats += ['s2:' + w[-2:], 's3:' + w[-3:], 's4:' + w[-4:], 'f3:' + w[:3]]
    if i == 0:
        feats.append('first')
    if i == len(tokens) - 1:
        feats.append('last')
    for name, members in flags.items():
        if w in members:
            feats.append('in:' + name)
        if prev1 in members:
            feats.append('pin:' + name)
        if next1 in members:
            feats.append('nin:' + name)
    return feats


def fold_for_matching(text: str) -> str:
    """`foldForMatching` (a lexikon kulcsaihoz)."""
    lower = ''.join(ACCENTS.get(c, c) for c in text.lower())
    out = []
    for c in lower:
        if 'a' <= c <= 'z' or '0' <= c <= '9' or c in '.,':
            out.append(c)
        else:
            out.append(' ')
    return re.sub(r'\s+', ' ', ''.join(out)).strip()
