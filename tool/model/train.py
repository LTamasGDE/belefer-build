"""A Belefér-modell tanítása és exportálása.

Futtatás (a projekt gyökeréből):
    python3 tool/model/train.py

Kimenet:
    assets/model/belefer_model.bin   – a telefonon futó modell
    test/fixtures/model_golden.json  – ellenőrző kimenetek a Dart-teszthez
"""

from __future__ import annotations

import json
import math
import random
import struct
import sys
import time
from collections import Counter
from pathlib import Path

import numpy as np
from scipy import sparse
from sklearn.linear_model import LogisticRegression

import generate
import lexicon
import vocab
from textproc import (DIM, DIM_BITS, bucket, raw_tokens, sequence_features,
                      token_features, vectorize, words, fold_for_matching)

ROOT = Path(__file__).resolve().parents[2]
MODEL_PATH = ROOT / 'assets/model/belefer_model.bin'
GOLDEN_PATH = ROOT / 'test/fixtures/model_golden.json'
MODEL_VERSION = 1


# --- Jelölő szólisták (a megnevezés-jelölőhöz; a modellfájlba is kerülnek) ---

def flag_sets() -> dict[str, list[str]]:
    _, _, sets = lexicon.load()

    def folded(items):
        out = set()
        for item in items:
            for word in fold_for_matching(item).split(' '):
                if word:
                    out.add(word)
        return out

    date_words = folded(vocab.DATE_PHRASES) | {
        'januar', 'februar', 'marcius', 'aprilis', 'majus', 'junius', 'julius',
        'augusztus', 'szeptember', 'oktober', 'november', 'december', 'jan',
        'feb', 'marc', 'apr', 'maj', 'jun', 'jul', 'aug', 'szept', 'okt', 'nov',
        'dec', 'en', 'an', 'ejen', 'ajan', 'napja', 'hete', 'tol', 'januartol',
        'decembertol', 'honaptol', 'jovo', 'mult',
    }
    return {
        'sw': sorted(sets['stopWords'] | folded(vocab.FILLERS)),
        'exp': sorted(sets['expenseWords'] | folded(vocab.EXPENSE_VERBS)),
        'inc': sorted(sets['incomeWords'] | folded(vocab.INCOME_VERBS)
                      | {w for v in generate.INCOME_VERBS_BY_CATEGORY.values() for w in folded(v)}),
        'rec': sorted(sets['recurringCreateWords'] | sets['recurringCancelWords']
                      | sets['recurringChangeWords'] | folded(generate.FREQ_WORDS)
                      | folded(t for t, _ in generate.CANCEL_TEMPLATES)),
        'date': sorted(date_words),
    }


FLAGS = flag_sets()
FLAG_SETS = {name: set(words_) for name, words_ in FLAGS.items()}


# --- Mátrixok -----------------------------------------------------------------

def sequence_matrix(texts: list[str]):
    rows, cols, vals = [], [], []
    for r, text in enumerate(texts):
        idx, weight = vectorize(sequence_features(words(text)))
        rows += [r] * len(idx)
        cols += idx
        vals += [weight] * len(idx)
    return sparse.csr_matrix((vals, (rows, cols)), shape=(len(texts), DIM), dtype=np.float64)


def token_rows(text: str):
    tokens = raw_tokens(text)
    for i in range(len(tokens)):
        yield token_features(tokens, i, FLAG_SETS)


def token_matrix(examples):
    rows, cols, vals, labels = [], [], [], []
    r = 0
    for example in examples:
        tokens = raw_tokens(example.text)
        if len(tokens) != len(example.title_mask):
            continue
        for i in range(len(tokens)):
            idx, weight = vectorize(token_features(tokens, i, FLAG_SETS))
            rows += [r] * len(idx)
            cols += idx
            vals += [weight] * len(idx)
            labels.append('t' if example.title_mask[i] else 'o')
            r += 1
    return sparse.csr_matrix((vals, (rows, cols)), shape=(r, DIM), dtype=np.float64), labels


# --- Kvantált fej -------------------------------------------------------------

class Head:
    def __init__(self, name: str, kind: int, labels: list[str], coef: np.ndarray,
                 intercept: np.ndarray, keep: float = 0.02):
        self.name = name
        self.kind = kind  # 0: szöveg, 1: szavanként
        self.labels = labels
        if coef.shape[0] == 1 and len(labels) == 2:
            # Kétosztályos: szimmetrikus softmax-alak.
            coef = np.vstack([-coef[0] / 2, coef[0] / 2])
            intercept = np.array([-intercept[0] / 2, intercept[0] / 2])
        coef = np.where(np.abs(coef) < keep, 0.0, coef)
        self.scale = float(np.float32(np.abs(coef).max() / 127.0))
        quant = np.rint(coef / self.scale).astype(np.int32)
        quant = np.clip(quant, -127, 127)
        self.bias = [float(np.float32(b)) for b in intercept]
        self.entries: dict[int, list[tuple[int, int]]] = {}
        nz_labels, nz_cols = np.nonzero(quant)
        for label, col in zip(nz_labels.tolist(), nz_cols.tolist()):
            self.entries.setdefault(col, []).append((label, int(quant[label, col])))

    @property
    def entry_count(self) -> int:
        return sum(len(v) for v in self.entries.values())

    def logits(self, idx: list[int], weight: float) -> list[float]:
        sums = [0] * len(self.labels)
        for col in idx:
            for label, value in self.entries.get(col, ()):
                sums[label] += value
        return [self.bias[c] + self.scale * weight * sums[c] for c in range(len(self.labels))]

    def probs(self, idx: list[int], weight: float) -> list[float]:
        logits = self.logits(idx, weight)
        top = max(logits)
        exps = [math.exp(v - top) for v in logits]
        total = sum(exps)
        return [e / total for e in exps]

    def predict_text(self, text: str) -> list[float]:
        idx, weight = vectorize(sequence_features(words(text)))
        return self.probs(idx, weight)

    def predict_tokens(self, text: str) -> list[list[float]]:
        tokens = raw_tokens(text)
        out = []
        for i in range(len(tokens)):
            idx, weight = vectorize(token_features(tokens, i, FLAG_SETS))
            out.append(self.probs(idx, weight))
        return out

    def serialize(self) -> bytes:
        out = bytearray()
        name = self.name.encode('ascii')
        out += struct.pack('<B', len(name)) + name
        out += struct.pack('<BB', self.kind, len(self.labels))
        for label in self.labels:
            raw = label.encode('ascii')
            out += struct.pack('<B', len(raw)) + raw
        out += struct.pack('<f', self.scale)
        for b in self.bias:
            out += struct.pack('<f', b)
        cols = sorted(self.entries)
        out += struct.pack('<I', self.entry_count)
        previous = 0
        for col in cols:
            for n, (label, value) in enumerate(self.entries[col]):
                delta = col - previous if n == 0 else 0
                out += varint(delta)
                out += struct.pack('<Bb', label, value)
                previous = col
        return bytes(out)


def varint(value: int) -> bytes:
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            out.append(byte | 0x80)
        else:
            out.append(byte)
            return bytes(out)


def write_model(heads: list[Head], path: Path) -> int:
    out = bytearray(b'BLFM')
    out += struct.pack('<HBB', MODEL_VERSION, DIM_BITS, len(FLAGS))
    for name, members in FLAGS.items():
        raw = '\n'.join(members).encode('ascii')
        n = name.encode('ascii')
        out += struct.pack('<B', len(n)) + n + struct.pack('<I', len(raw)) + raw
    out += struct.pack('<B', len(heads))
    for head in heads:
        out += head.serialize()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(bytes(out))
    return len(out)


# --- Tanítás ------------------------------------------------------------------

def fit(name, kind, X, y, C, keep, max_iter=400):
    started = time.time()
    labels = sorted(set(y))
    model = LogisticRegression(C=C, max_iter=max_iter, tol=1e-4)
    model.fit(X, y)
    assert list(model.classes_) == labels
    head = Head(name, kind, labels, model.coef_, model.intercept_, keep=keep)
    print(f'  {name}: {X.shape[0]} példa, {len(labels)} címke, '
          f'{head.entry_count} súly, {time.time() - started:.0f} s', flush=True)
    return head


def accuracy(head: Head, texts, labels) -> float:
    hits = 0
    for text, label in zip(texts, labels):
        probs = head.predict_text(text)
        hits += head.labels[int(np.argmax(probs))] == label
    return hits / max(1, len(texts))


def main(scale: float = 1.0) -> None:
    random.seed(0)
    print('Adatok generálása…', flush=True)
    train = generate.dataset(1, scale)
    valid = generate.dataset(7, 0.06)
    print(f'  {len(train)} tanító, {len(valid)} ellenőrző példa', flush=True)

    rng = random.Random(3)
    cat_train = [e for e in train if e.category]
    intent_train = [e for e in train if e.intent and (e.intent != 'record' or rng.random() < 0.25)]
    status_train = [e for e in train if e.status]
    title_train = [e for e in train if e.title_mask is not None]

    print('Tanítás…', flush=True)
    heads = [
        fit('category', 0, sequence_matrix([e.text for e in cat_train]), [e.category for e in cat_train], C=20, keep=0.03),
        fit('intent', 0, sequence_matrix([e.text for e in intent_train]), [e.intent for e in intent_train], C=10, keep=0.03),
        fit('status', 0, sequence_matrix([e.text for e in status_train]), [e.status for e in status_train], C=10, keep=0.03),
    ]
    X_title, y_title = token_matrix(title_train)
    heads.append(fit('title', 1, X_title, y_title, C=5, keep=0.03))
    by_name = {h.name: h for h in heads}

    print('Ellenőrzés (generált):', flush=True)
    for name, attr in [('category', 'category'), ('intent', 'intent'), ('status', 'status')]:
        items = [e for e in valid if getattr(e, attr)]
        acc = accuracy(by_name[name], [e.text for e in items], [getattr(e, attr) for e in items])
        print(f'  {name}: {acc:.3f} ({len(items)})')
    title_items = [e for e in valid if e.title_mask is not None]
    hits = total = 0
    for e in title_items:
        probs = by_name['title'].predict_tokens(e.text)
        if len(probs) != len(e.title_mask):
            continue
        pred = [1 if p[by_name['title'].labels.index('t')] >= 0.5 else 0 for p in probs]
        hits += pred == e.title_mask
        total += 1
    print(f'  title (teljes egyezés): {hits / max(1, total):.3f} ({total})')

    print('Ellenőrzés (kézzel írt):', flush=True)
    rows = []
    for line in (Path(__file__).parent / 'eval.tsv').read_text(encoding='utf-8').splitlines():
        if not line or line.startswith('#'):
            continue
        task, expected, text = line.split('\t')
        rows.append((task, expected, text.replace('\\n', '\n')))
    per_task = Counter()
    per_task_hit = Counter()
    misses = []
    for task, expected, text in rows:
        head = by_name[task]
        probs = head.predict_text(text)
        best = head.labels[int(np.argmax(probs))]
        per_task[task] += 1
        if best == expected:
            per_task_hit[task] += 1
        else:
            misses.append(f'    {task}: „{text}” → {best} ({max(probs):.2f}), elvárt: {expected}')
    for task in per_task:
        print(f'  {task}: {per_task_hit[task]}/{per_task[task]}')
    print('\n'.join(misses))

    size = write_model(heads, MODEL_PATH)
    print(f'Modell: {MODEL_PATH.relative_to(ROOT)} ({size / 1024:.0f} KiB)')

    golden = []
    for task, _, text in rows[::3]:
        probs = by_name[task].predict_text(text)
        golden.append({'head': task, 'text': text, 'probs': [round(p, 6) for p in probs]})
    for text in ['tegnap a Lidl-ben vettem kenyeret 1200', 'kenyérre ment el 1200', 'megjött a fizetés 420e']:
        probs = by_name['title'].predict_tokens(text)
        golden.append({'head': 'title', 'text': text, 'probs': [round(p[1], 6) for p in probs]})
    features = []
    for text in ['Lidl-ben 4 500 Ft', 'Tescóban vettem kenyeret!', '12e', 'Paid €4.50']:
        idx, weight = vectorize(sequence_features(words(text)))
        features.append({'text': text, 'words': words(text), 'buckets': idx, 'weight': weight})
    GOLDEN_PATH.parent.mkdir(parents=True, exist_ok=True)
    GOLDEN_PATH.write_text(json.dumps({'version': MODEL_VERSION, 'predictions': golden, 'features': features},
                                      ensure_ascii=False, indent=1), encoding='utf-8')
    print(f'Ellenőrző kimenetek: {GOLDEN_PATH.relative_to(ROOT)}')


if __name__ == '__main__':
    main(float(sys.argv[1]) if len(sys.argv) > 1 else 1.0)
