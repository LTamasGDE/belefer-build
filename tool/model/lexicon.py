"""A Dart-lexikon (lib/domain/quick_entry/lexicon.dart) beolvasása."""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LEXICON = ROOT / 'lib/domain/quick_entry/lexicon.dart'


@dataclass
class Merchant:
    name: str
    category: str
    keys: list[str]


@dataclass
class Keyword:
    key: str
    category: str
    title: str | None


def _strings(text: str) -> list[str]:
    return re.findall(r"'((?:[^'\\]|\\.)*)'", text)


def load():
    source = LEXICON.read_text(encoding='utf-8')
    merchant_part = source[source.index('const List<MerchantEntry> merchants'):]
    merchant_part = merchant_part[:merchant_part.index('const List<KeywordEntry>')]
    keyword_part = source[source.index('const List<KeywordEntry> keywords'):]
    keyword_part = keyword_part[:keyword_part.index('const Set<String>')]
    merchants = []
    for match in re.finditer(r'MerchantEntry\((.*?)\]\)', merchant_part, re.S):
        parts = _strings(match.group(1))
        merchants.append(Merchant(parts[0], parts[1], parts[2:]))
    keywords = []
    for match in re.finditer(r'KeywordEntry\(\s*(.*?)\),?\n', keyword_part, re.S):
        body = match.group(1)
        parts = _strings(body)
        title = None
        title_match = re.search(r"title:\s*'((?:[^'\\]|\\.)*)'", body)
        if title_match:
            title = title_match.group(1)
        keywords.append(Keyword(parts[0], parts[1], title))

    def word_set(name: str) -> set[str]:
        block = re.search(r'const Set<String> ' + name + r' = \{(.*?)\};', source, re.S)
        return set(_strings(block.group(1)))

    sets = {
        name: word_set(name)
        for name in (
            'expenseWords',
            'incomeWords',
            'recurringCreateWords',
            'recurringCancelWords',
            'recurringChangeWords',
            'stopWords',
        )
    }
    return merchants, keywords, sets


if __name__ == '__main__':
    m, k, s = load()
    print(len(m), 'merchants', len(k), 'keywords', {n: len(v) for n, v in s.items()})
