"""Tanítóadatok generálása a Belefér-modellhez.

Változatos, magyar (és a banki értesítéseknél angol) mondatokat állít elő
sablonokból, a szókincsből és a lexikonból, toldalékolással, elírásokkal,
töltelékszavakkal és felcserélt szórenddel. Minden példához tartozik címke:
kategória, szándék, a megnevezés szavai, illetve az értesítés állapota.
"""

from __future__ import annotations

import random
from dataclasses import dataclass, field

import lexicon
import vocab
from textproc import raw_tokens

BACK = set('aáoóuú')
FRONT_ROUNDED = set('öőüű')
FRONT = set('eéií') | FRONT_ROUNDED
VOWELS = BACK | FRONT

EXPENSE_CATEGORIES = [
    'housing', 'utilities', 'groceries', 'dining', 'transport', 'health',
    'clothing', 'entertainment', 'subscriptions', 'education', 'gifts',
    'other_expense',
]
INCOME_CATEGORIES = [
    'salary', 'side_income', 'scholarship', 'gift_income', 'refund',
    'other_income',
]
RECURRING_CATEGORIES = {
    'subscriptions': 6, 'housing': 3, 'utilities': 3, 'salary': 2,
    'entertainment': 1, 'transport': 1, 'education': 1, 'side_income': 1,
    'scholarship': 1, 'other_expense': 1,
}


@dataclass
class Example:
    text: str
    category: str | None = None
    intent: str | None = None
    status: str | None = None
    # Szavanként: a megnevezés része-e (a Dart `tokenize` tokenjeire).
    title_mask: list[int] | None = None
    tags: list[str] = field(default_factory=list)


class Builder:
    """Mondat építése szakaszokból; a megnevezés szakaszai jelölve."""

    def __init__(self) -> None:
        self.parts: list[tuple[str, bool, bool]] = []  # (szöveg, cím, tapad)

    def add(self, text: str, title: bool = False, glue: bool = False) -> 'Builder':
        if text:
            self.parts.append((text, title, glue))
        return self

    def build(self) -> tuple[str, list[int]]:
        text = ''
        mask: list[int] = []
        for chunk, title, glue in self.parts:
            if text and not glue:
                text += ' '
            text += chunk
            mask += [1 if title else 0] * len(raw_tokens(chunk))
        return text, mask


# --- Toldalékolás -----------------------------------------------------------

def _last_vowel(word: str) -> str:
    for ch in reversed(word.lower()):
        if ch in VOWELS:
            return ch
    return 'e'


def harmony(word: str) -> str:
    v = _last_vowel(word)
    if v in BACK:
        return 'back'
    if v in FRONT_ROUNDED:
        return 'round'
    return 'front'


def _lengthen(word: str) -> str:
    if word.endswith('a'):
        return word[:-1] + 'á'
    if word.endswith('e'):
        return word[:-1] + 'é'
    if word.endswith('o') and word[-2:-1].isalpha():
        return word[:-1] + 'ó'
    return word


CASES = {
    'iness': ('ban', 'ben', 'ben'),
    'illat': ('ba', 'be', 'be'),
    'elat': ('ból', 'ből', 'ből'),
    'adess': ('nál', 'nél', 'nél'),
    'ablat': ('tól', 'től', 'től'),
    'sublat': ('ra', 're', 're'),
    'delat': ('ról', 'ről', 'ről'),
    'causal': ('ért', 'ért', 'ért'),
    'allat': ('hoz', 'hez', 'höz'),
    'dat': ('nak', 'nek', 'nek'),
    'instr': ('val', 'vel', 'vel'),
}


def inflect(phrase: str, case: str, rng: random.Random) -> tuple[str, str]:
    """(tő, toldalék): a többszavas kifejezésnek az utolsó szava kapja.

    Néha kötőjellel („Lidl-ben”), mint a márkanevek írásakor szokás.
    """
    if case == 'nom':
        return phrase, ''
    last = phrase.split(' ')[-1]
    h = harmony(last)
    if case == 'acc':
        if last[-1:].lower() in VOWELS:
            stem = phrase[: len(phrase) - len(last)] + _lengthen(last)
            return stem, 't'
        suffix = {'back': 'ot', 'front': 'et', 'round': 'öt'}[h]
        if last[-1:].lower() in 'lnrsjyz' and rng.random() < 0.5:
            suffix = 't'
        return phrase, suffix
    back, front, round_ = CASES[case]
    suffix = {'back': back, 'front': front, 'round': round_}[h]
    if last[-1:].isupper() or not last[-1:].isalpha() or rng.random() < 0.12:
        return phrase, '-' + suffix
    stem = phrase[: len(phrase) - len(last)] + _lengthen(last)
    if case == 'instr' and last[-1:].lower() not in VOWELS:
        suffix = last[-1] + suffix[1:]
    return stem, suffix


# --- Zaj --------------------------------------------------------------------

KEY_NEIGHBORS = {
    'a': 'sqy', 'b': 'vn', 'c': 'xv', 'd': 'sf', 'e': 'wr', 'f': 'dg', 'g': 'fh',
    'h': 'gj', 'i': 'uo', 'j': 'hk', 'k': 'jl', 'l': 'k', 'm': 'n', 'n': 'bm',
    'o': 'ip', 'p': 'o', 'r': 'et', 's': 'ad', 't': 'rz', 'u': 'zi', 'v': 'cb',
    'z': 'tu', 'y': 'x',
}
STRIP_ACCENT = str.maketrans('áéíóöőúüűÁÉÍÓÖŐÚÜŰ', 'aeiooouuuAEIOOOUUU')


def typo(word: str, rng: random.Random) -> str:
    if len(word) < 4 or any(ch.isdigit() for ch in word):
        return word
    i = rng.randrange(1, len(word) - 1)
    kind = rng.random()
    if kind < 0.3:
        return word[:i] + word[i + 1:]
    if kind < 0.5:
        return word[:i] + word[i] + word[i:]
    if kind < 0.75:
        return word[: i - 1] + word[i] + word[i - 1] + word[i + 1:]
    ch = word[i].lower()
    if ch in KEY_NEIGHBORS:
        return word[:i] + rng.choice(KEY_NEIGHBORS[ch]) + word[i + 1:]
    return word


def noisy(text: str, rng: random.Random, rate: float = 0.1) -> str:
    out = []
    for word in text.split(' '):
        if rng.random() < rate:
            word = typo(word, rng)
        out.append(word)
    text = ' '.join(out)
    if rng.random() < 0.35:
        text = text.translate(STRIP_ACCENT)
    if rng.random() < 0.15:
        text = text.upper()
    elif rng.random() < 0.4:
        text = text.lower()
    return text


# --- Összegek ---------------------------------------------------------------

AMOUNT_RANGES = {
    'housing': (60000, 350000), 'utilities': (3000, 45000),
    'groceries': (300, 40000), 'dining': (600, 25000),
    'transport': (350, 40000), 'health': (800, 60000),
    'clothing': (1500, 60000), 'entertainment': (1500, 80000),
    'subscriptions': (990, 12000), 'education': (1000, 250000),
    'gifts': (1000, 40000), 'other_expense': (200, 300000),
    'salary': (180000, 1200000), 'side_income': (3000, 300000),
    'scholarship': (10000, 200000), 'gift_income': (2000, 100000),
    'refund': (500, 80000), 'other_income': (2000, 300000),
}


def _round(value: int, rng: random.Random) -> int:
    if value >= 100000:
        return round(value, -3)
    if value >= 10000:
        return round(value, -2) if rng.random() < 0.7 else value
    if value >= 1000:
        return round(value, -1) if rng.random() < 0.6 else value
    return value


def amount_text(category: str, rng: random.Random, case: str | None = None) -> str:
    low, high = AMOUNT_RANGES.get(category, (500, 50000))
    value = _round(int(rng.uniform(low, high)), rng)
    r = rng.random()
    if r < 0.05:
        return rng.choice(vocab.AMOUNT_WORDS)
    thousands = f'{value:,}'.replace(',', rng.choice([' ', '.', '']))
    if value % 1000 == 0 and rng.random() < 0.4:
        k = value // 1000
        base = rng.choice([f'{k}e', f'{k} ezer', f'{k}ezer', f'{k}k', f'{k} rugó'])
    elif value % 100 == 0 and value >= 1000 and rng.random() < 0.15:
        base = f'{value / 1000:.1f}'.replace('.', rng.choice([',', '.'])) + rng.choice(['e', 'k', ' ezer'])
    else:
        base = rng.choice([str(value), thousands])
    if case and rng.random() < 0.6:
        suffix = {'acc': rng.choice(['-at', '-et', '-ot']), 'causal': '-ért', 'sublat': '-ra'}.get(case, '')
        return base + suffix
    currency = rng.random()
    if currency < 0.25:
        base += rng.choice([' ft', ' Ft', 'ft', ' forint', ' HUF', ',-', ' Ft-ot', '-ot'])
    return base


# --- Szókincs ---------------------------------------------------------------

def _vocabulary():
    merchants, keywords, sets = lexicon.load()
    things: dict[str, list[str]] = {c: list(v) for c, v in vocab.CATEGORY_WORDS.items()}
    places: dict[str, list[str]] = {c: list(v) for c, v in vocab.EXTRA_MERCHANTS.items()}
    for m in merchants:
        places.setdefault(m.category, []).append(m.name)
        places[m.category].extend(k for k in m.keys if len(k) > 2)
    for k in keywords:
        if k.title:
            things.setdefault(k.category, []).append(k.title)
    for c in list(things) + list(places):
        things.setdefault(c, [])
        places.setdefault(c, [])
    return things, places, sets


THINGS, PLACES, SETS = _vocabulary()


def pick_thing(category: str, rng: random.Random) -> str:
    pool = THINGS[category] if THINGS[category] else PLACES[category]
    if PLACES[category] and rng.random() < 0.35:
        pool = PLACES[category]
    return rng.choice(pool)


def pick_place(category: str, rng: random.Random) -> str:
    pool = PLACES[category] or THINGS[category]
    return rng.choice(pool)


def maybe(rng: random.Random, p: float, text: str) -> str:
    return text if rng.random() < p else ''


def article(rng: random.Random, word: str) -> str:
    r = rng.random()
    if r < 0.4:
        return 'az' if word[:1].lower() in VOWELS else 'a'
    if r < 0.5:
        return 'egy'
    if r < 0.53:
        return rng.choice(['pár', 'néhány', 'két', 'új'])
    return ''


# --- Gyorsrögzítés: kiadás --------------------------------------------------

def expense_sentence(category: str, rng: random.Random) -> Example:
    b = Builder()
    thing = pick_thing(category, rng)
    place = pick_place(category, rng)
    verb = rng.choice(vocab.EXPENSE_VERBS)
    date = rng.choice(vocab.DATE_PHRASES)
    filler = rng.choice(vocab.FILLERS)
    t = rng.randrange(15)

    def add_inflected(phrase: str, case: str) -> None:
        stem, suffix = inflect(phrase, case, rng)
        b.add(article(rng, stem))
        b.add(stem, title=True)
        if suffix.startswith('-'):
            b.add(suffix, glue=True)
        elif suffix:
            # A toldalék a szó része (egy token marad).
            text, _ = b.parts[-1][0], None
            b.parts[-1] = (stem + suffix, True, b.parts[-1][2])

    if rng.random() < 0.25:
        b.add(date)
    if t == 0:
        add_inflected(thing, 'nom'); b.add(amount_text(category, rng))
    elif t == 1:
        b.add(amount_text(category, rng)); add_inflected(thing, 'nom')
    elif t == 2:
        b.add(verb); add_inflected(thing, 'acc'); b.add(amount_text(category, rng))
    elif t == 3:
        add_inflected(thing, 'acc'); b.add(verb); b.add(amount_text(category, rng, 'acc'))
    elif t == 4:
        add_inflected(thing, 'sublat'); b.add(amount_text(category, rng)); b.add(rng.choice(['ment el', 'ment', 'költöttem', 'fizettem', 'elment']))
    elif t == 5:
        b.add(amount_text(category, rng, 'acc')); b.add(rng.choice(['költöttem', 'fizettem', 'adtam ki', 'hagytam'])); add_inflected(thing, 'sublat')
    elif t == 6:
        add_inflected(place, 'iness'); b.add(verb); b.add(amount_text(category, rng, 'acc'))
    elif t == 7:
        add_inflected(place, 'iness'); b.add(amount_text(category, rng))
    elif t == 8:
        b.add(amount_text(category, rng)); add_inflected(place, 'iness')
    elif t == 9:
        add_inflected(place, 'iness'); b.add(verb)
        stem, suffix = inflect(thing, 'acc', rng)
        b.add(stem + (suffix if not suffix.startswith('-') else ''))
        b.add(amount_text(category, rng))
    elif t == 10:
        add_inflected(place, 'nom'); b.add(amount_text(category, rng))
    elif t == 11:
        add_inflected(thing, 'causal'); b.add(verb); b.add(amount_text(category, rng))
    elif t == 12:
        b.add(amount_text(category, rng)); add_inflected(place, 'nom'); b.add(maybe(rng, 0.5, thing.lower()))
    elif t == 13:
        b.add(verb); add_inflected(thing, 'acc')
        stem, suffix = inflect(place, rng.choice(['elat', 'delat', 'iness', 'adess']), rng)
        b.add(article(rng, stem)); b.add(stem + suffix.lstrip('-'), title=rng.random() < 0.5)
        b.add(amount_text(category, rng))
    else:
        add_inflected(thing, 'nom'); b.add(amount_text(category, rng)); b.add(rng.choice(['volt', 'lett', 'jött ki', 'ment el', '']))
    if rng.random() < 0.25:
        b.add(date)
    if rng.random() < 0.2:
        b.add(filler)
    text, mask = b.build()
    return Example(text=text, category=category, intent='record', title_mask=mask, tags=['expense'])


# --- Gyorsrögzítés: bevétel -------------------------------------------------

INCOME_VERBS_BY_CATEGORY = {
    'salary': ['megjött', 'jött', 'utalták', 'érkezett', 'megkaptam', 'kifizették', 'jóváírták', 'bejött', 'megérkezett'],
    'side_income': ['kerestem', 'kaptam', 'bejött', 'utalták', 'kifizettek', 'fizettek', 'összejött', 'bezsebeltem', 'megkaptam'],
    'scholarship': ['megjött', 'utalták', 'kaptam', 'érkezett', 'megkaptam', 'jóváírták', 'folyósították'],
    'gift_income': ['kaptam', 'megkaptam', 'kaptunk', 'jött', 'utalt', 'küldött', 'adott'],
    'refund': ['visszakaptam', 'visszautalták', 'visszatérítették', 'jóváírták', 'visszajött', 'visszafizették'],
    'other_income': ['kaptam', 'jött', 'érkezett', 'nyertem', 'megjött', 'utalták', 'befolyt'],
}


def income_sentence(category: str, rng: random.Random) -> Example:
    b = Builder()
    thing = pick_thing(category, rng)
    verb = rng.choice(INCOME_VERBS_BY_CATEGORY[category])
    date = rng.choice(vocab.DATE_PHRASES)
    person = rng.choice(vocab.PEOPLE)
    t = rng.randrange(10)
    if rng.random() < 0.2:
        b.add(date)
    if category == 'gift_income' and rng.random() < 0.6:
        stem, suffix = inflect(person, 'ablat', rng)
        if t % 2:
            b.add(stem + (suffix if not suffix.startswith('-') else suffix), title=True)
            b.add(rng.choice(['kaptam', 'kaptam ajándékba', 'jött', 'utalt', 'küldött']))
            b.add(amount_text(category, rng, 'acc'))
        else:
            b.add(amount_text(category, rng, 'acc'))
            b.add(rng.choice(['kaptam', 'kaptam szülinapra', 'adott']))
            b.add(stem + suffix, title=True)
    elif category == 'side_income' and rng.random() < 0.35:
        item = rng.choice(vocab.CATEGORY_WORDS[rng.choice(['clothing', 'other_expense', 'housing', 'entertainment'])])
        stem, suffix = inflect(item, 'acc', rng)
        b.add('eladtam'); b.add(article(rng, stem)); b.add(stem + suffix.lstrip('-'), title=True)
        b.add(amount_text(category, rng, rng.choice(['causal', None])))
    elif category == 'refund' and rng.random() < 0.4:
        place = pick_place(rng.choice(EXPENSE_CATEGORIES), rng)
        stem, suffix = inflect(place, rng.choice(['ablat', 'elat']), rng)
        b.add(rng.choice(['visszakaptam', 'visszautalták', 'visszatérítették', 'jóváírták']))
        b.add(amount_text(category, rng, 'acc'))
        b.add(article(rng, stem)); b.add(stem + suffix.lstrip('-'), title=True)
    elif t < 3:
        b.add(rng.choice(['megjött', 'jött', 'bejött', 'megérkezett', 'itt a', 'jóváírták']))
        b.add(article(rng, thing)); b.add(thing, title=True); b.add(amount_text(category, rng))
    elif t < 5:
        b.add(thing, title=True); b.add(amount_text(category, rng)); b.add(maybe(rng, 0.6, verb))
    elif t < 7:
        b.add(verb); stem, suffix = inflect(thing, 'acc', rng)
        b.add(stem + suffix.lstrip('-'), title=True); b.add(amount_text(category, rng))
    elif t < 9:
        b.add(amount_text(category, rng)); b.add(thing, title=True)
    else:
        b.add(amount_text(category, rng, 'acc')); b.add(verb); stem, suffix = inflect(thing, 'causal', rng)
        b.add(stem + suffix.lstrip('-'), title=True)
    if rng.random() < 0.2:
        b.add(date)
    text, mask = b.build()
    return Example(text=text, category=category, intent='record', title_mask=mask, tags=['income'])


# --- Ismétlődő tételek -------------------------------------------------------

def _recurring_category(rng: random.Random) -> str:
    cats, weights = zip(*RECURRING_CATEGORIES.items())
    return rng.choices(cats, weights=weights)[0]


def _recurring_thing(category: str, rng: random.Random) -> str:
    if category == 'subscriptions':
        return pick_place(category, rng) if rng.random() < 0.7 else pick_thing(category, rng)
    preferred = {
        'housing': ['lakbér', 'albérlet', 'közös költség', 'hiteltörlesztés', 'bérleti díj', 'törlesztő'],
        'utilities': ['internet', 'telefonszámla', 'villany', 'gáz', 'víz', 'netflix és net', 'távfűtés', 'mobil'],
        'salary': ['fizetés', 'bér', 'munkabér', 'fizu'],
        'entertainment': ['edzőterem', 'konditerem', 'jóga', 'uszodabérlet', 'edzőtermi bérlet'],
        'transport': ['BKK bérlet', 'havibérlet', 'bérlet', 'parkolóbérlet'],
        'education': ['nyelvóra', 'tandíj', 'különóra', 'zeneóra', 'kollégiumi díj'],
        'side_income': ['albérlő', 'lakáskiadás', 'mellékállás', 'megbízás'],
        'scholarship': ['ösztöndíj', 'tanulmányi ösztöndíj'],
        'other_expense': ['biztosítás', 'életbiztosítás', 'tartásdíj', 'takarítónő', 'zsebpénz a gyereknek', 'zsebpénz', 'bébiszitter'],
    }.get(category)
    return rng.choice(preferred) if preferred and rng.random() < 0.85 else pick_thing(category, rng)


FREQ_WORDS = [
    'havi', 'havonta', 'minden hónapban', 'minden hónap', '/hó', 'per hó',
    'hetente', 'heti', 'minden héten', 'évente', 'évi', 'éves', 'negyedévente',
    'kéthetente', 'havidíj', 'havidíjas', 'rendszeresen', 'minden hónap elején',
    'minden hónap 5-én', 'minden hó 10-én', 'havonta egyszer',
]


def create_recurring(rng: random.Random) -> Example:
    category = _recurring_category(rng)
    thing = _recurring_thing(category, rng)
    b = Builder()
    freq = rng.choice(FREQ_WORDS)
    amount = amount_text(category, rng)
    t = rng.randrange(9)
    if t == 0:
        b.add(thing, title=True); b.add(freq); b.add(amount)
    elif t == 1:
        b.add(freq); b.add(amount); b.add(article(rng, thing)); b.add(thing, title=True)
    elif t == 2:
        stem, suffix = inflect(thing, 'sublat', rng)
        b.add(rng.choice(['előfizettem', 'feliratkoztam', 'előfizetek'])); b.add(article(rng, stem))
        b.add(stem + suffix.lstrip('-'), title=True); b.add(freq); b.add(amount)
    elif t == 3:
        b.add(thing, title=True); b.add(amount); b.add(freq)
    elif t == 4:
        stem, suffix = inflect(thing, 'acc', rng)
        b.add(freq); b.add('fizetem'); b.add(article(rng, stem)); b.add(stem + suffix.lstrip('-'), title=True); b.add(amount)
    elif t == 5:
        b.add(amount); b.add(freq); b.add(thing, title=True)
    elif t == 6:
        b.add('új'); b.add(thing, title=True); b.add('előfizetés'); b.add(amount); b.add(freq)
    elif t == 7:
        b.add(thing, title=True); b.add(rng.choice(['rendszeres', 'állandó', 'ismétlődő'])); b.add(amount); b.add(maybe(rng, 0.5, freq))
    else:
        b.add(rng.choice(['mostantól', 'januártól', 'decembertől', 'jövő hónaptól'])); b.add(freq)
        b.add(amount); b.add(thing, title=True)
    text, mask = b.build()
    return Example(text=text, category=category, intent='create_recurring', title_mask=mask)


CANCEL_TEMPLATES = [
    ('lemondtam', 'acc'), ('lemondom', 'acc'), ('leiratkoztam', 'delat'),
    ('felmondtam', 'acc'), ('megszüntettem', 'acc'), ('töröltem', 'acc'),
    ('kiléptem', 'elat'), ('abbahagytam', 'acc'), ('befejeztem', 'acc'),
    ('nem fizetek tovább', 'sublat'), ('nem kell többé', 'nom'),
    ('mondd le', 'acc'), ('töröld', 'acc'), ('állítsd le', 'acc'),
    ('vége', 'dat'), ('lemondtuk', 'acc'), ('kikapcsoltam', 'acc'),
]


def cancel_recurring(rng: random.Random) -> Example:
    category = _recurring_category(rng)
    if category in ('salary', 'scholarship', 'side_income'):
        category = 'subscriptions'
    thing = _recurring_thing(category, rng)
    b = Builder()
    if rng.random() < 0.15:
        b.add(rng.choice(vocab.DATE_PHRASES))
    t = rng.random()
    if t < 0.7:
        verb, case = rng.choice(CANCEL_TEMPLATES)
        stem, suffix = inflect(thing, case, rng)
        word = stem + suffix.lstrip('-')
        if rng.random() < 0.6:
            b.add(verb); b.add(article(rng, word)); b.add(word, title=True)
        else:
            b.add(article(rng, word)); b.add(word, title=True); b.add(verb)
        if rng.random() < 0.3:
            b.add(rng.choice(['előfizetést', 'előfizetésem', 'tagságot', 'bérletet', 'szolgáltatást']))
    elif t < 0.85:
        b.add(thing, title=True)
        b.add(rng.choice(['lemondva', 'megszűnt', 'le van mondva', 'törölve', 'vége', 'leállítva', 'cancel', 'stop']))
    else:
        b.add(rng.choice(['már nincs', 'nincs több', 'nem lesz több', 'nem használom már a']))
        b.add(thing, title=True)
    text, mask = b.build()
    return Example(text=text, category=category, intent='cancel_recurring', title_mask=mask)


def change_recurring(rng: random.Random) -> Example:
    category = _recurring_category(rng)
    thing = _recurring_thing(category, rng)
    b = Builder()
    t = rng.randrange(8)
    amount_plain = amount_text(category, rng)
    if t == 0:
        b.add(rng.choice(['mostantól', 'ezentúl', 'jövő hónaptól', 'januártól', 'decembertől']))
        b.add(amount_plain); b.add(article(rng, thing)); b.add(thing, title=True)
    elif t == 1:
        stem, suffix = inflect(thing, 'acc', rng)
        b.add(rng.choice(['emelték', 'felemelték', 'csökkentették', 'megemelték']))
        b.add(article(rng, stem)); b.add(stem + suffix.lstrip('-'), title=True)
        b.add(amount_text(category, rng, 'sublat'))
    elif t == 2:
        b.add(rng.choice(['drágult', 'olcsóbb lett', 'emelkedett', 'csökkent', 'változott']))
        b.add(article(rng, thing)); b.add(thing, title=True); b.add(maybe(rng, 0.5, 'mostantól')); b.add(amount_plain)
    elif t == 3:
        b.add(article(rng, thing)); b.add(thing, title=True); b.add(rng.choice(['mostantól', 'ezentúl', 'januártól']))
        b.add(amount_plain)
    elif t == 4:
        b.add(amount_plain); b.add('lett'); b.add(article(rng, thing)); b.add(thing, title=True)
    elif t == 5:
        b.add(thing, title=True); b.add(amount_text(category, rng, 'sublat'))
        b.add(rng.choice(['változott', 'emelkedett', 'nőtt', 'csökkent', 'módosult']))
    elif t == 6:
        b.add('új ár'); b.add(thing, title=True); b.add(amount_plain)
    else:
        b.add(rng.choice(['elköltöztem, mostantól', 'új albérlet, mostantól', 'átköltöztünk,']))
        b.add(amount_plain); b.add(rng.choice(['a lakbér', 'a bérleti díj', 'az albérlet']), title=True)
    text, mask = b.build()
    return Example(text=text, category=category, intent='change_recurring', title_mask=mask)


# --- Csak megnevezés (Apple Pay-kereskedő, tételnév, korábbi tételek) -------

def bare_title(category: str, rng: random.Random) -> Example:
    r = rng.random()
    if r < 0.45:
        text = pick_place(category, rng)
        if rng.random() < 0.3:
            text += ' ' + rng.choice(['Budapest', 'Budaörs', 'Debrecen', 'Szeged', 'Győr', 'Pécs', 'Westend', 'Árkád', 'Allee', 'Kft', 'Zrt', 'Bt', '1052', 'H-1117', 'HU', '*'])
        if rng.random() < 0.15:
            text = text.upper()
    else:
        text = pick_thing(category, rng)
        if rng.random() < 0.2:
            text = text + ' ' + pick_thing(category, rng).lower()
    return Example(text=text, category=category, tags=['title'])


# --- Blokk -------------------------------------------------------------------

RECEIPT_ITEMS = {
    'groceries': [w for w in vocab.CATEGORY_WORDS['groceries'] if ' ' not in w or len(w) < 14],
    'dining': ['CAPPUCCINO', 'LATTE', 'ESPRESSO', 'PIZZA MARGHERITA', 'HAMBURGER MENÜ', 'GYROS TÁL',
               'KÓLA 0,5', 'LIMONÁDÉ', 'SZERVIZDÍJ 12%', 'NAPI MENÜ', 'SÜTEMÉNY', 'CROISSANT',
               'SÖR 0,5', 'FRÖCCS', 'RÁNTOTT HÚS', 'GULYÁSLEVES', 'DESSZERT', 'TEA'],
    'transport': ['95 BENZIN', 'DÍZEL', 'GÁZOLAJ', 'EVO 95', 'ABLAKMOSÓ', 'AUTÓMOSÁS PRÉMIUM',
                  'PARKOLÁS', 'E-MATRICA', 'KÚTSZÁM 4', 'ÜZEMANYAG', 'AD BLUE'],
    'health': ['ALGOFLEX', 'CALCIUM', 'C-VITAMIN 1000', 'NUROFEN', 'ORRSPRAY', 'SEBTAPASZ',
               'MAGNÉZIUM', 'KÖHÖGÉS SZIRUP', 'VÉNYKÖTELES', 'TÁMOGATOTT GYÓGYSZER', 'LÁZMÉRŐ'],
    'clothing': ['PÓLÓ', 'FARMERNADRÁG', 'ZOKNI 3PK', 'PULÓVER', 'SPORTCIPŐ', 'KABÁT', 'ING',
                 'SZOKNYA', 'MELLTARTÓ', 'SAPKA', 'SÁL', 'TÁSKA'],
    'housing': ['FÚRÓ', 'CSAVAR', 'DÜBEL', 'FESTÉK 5L', 'ECSET', 'GLETT', 'IZZÓ', 'POLC',
                'KANAPÉPÁRNA', 'FÜGGÖNY', 'SZŐNYEG', 'TÖRÖLKÖZŐ', 'SERPENYŐ', 'VIRÁGFÖLD'],
    'entertainment': ['FELNŐTT JEGY', 'DIÁKJEGY', 'POPCORN', 'BELÉPŐ', 'KABINBÉRLÉS', 'SZAUNA',
                      'BOWLING PÁLYA', 'TÁRSASJÁTÉK', 'LEGO', 'KONCERTJEGY'],
    'education': ['TANKÖNYV', 'FÜZET A4', 'GOLYÓSTOLL', 'CERUZA', 'RADÍR', 'SZAKKÖNYV',
                  'TOLLTARTÓ', 'VONALZÓ', 'SZÖVEGKIEMELŐ'],
    'other_expense': ['TELEFONTOK', 'USB KÁBEL', 'TÖLTŐ', 'FÜLHALLGATÓ', 'ELEM AA', 'NYOMTATÓPATRON',
                      'CSOMAGFELADÁS', 'HAJVÁGÁS', 'BORBÉLY', 'MANIKŰR'],
    'gifts': ['VIRÁGCSOKOR', 'RÓZSA', 'AJÁNDÉKTASAK', 'AJÁNDÉKKÁRTYA', 'DÍSZDOBOZ', 'KÉPESLAP'],
}


def receipt(category: str, rng: random.Random) -> Example:
    lines = []
    if rng.random() < 0.7:
        name = pick_place(category, rng) if rng.random() < 0.6 else rng.choice(['Kft', 'Bt', 'Zrt']) + ' ' + rng.choice(['Alfa', 'Delta', 'Nova', 'Sun', 'Kis', 'Hungária'])
        lines.append(name.upper() + rng.choice(['', ' KFT.', ' ZRT.', ' BT.']))
        lines.append(rng.choice(['1052 Budapest, Váci u. 12.', 'Adószám: 12345678-2-42', 'Tel: 06 1 234 5678', '']))
    items = RECEIPT_ITEMS.get(category, RECEIPT_ITEMS['other_expense'])
    total = 0
    for _ in range(rng.randrange(1, 8)):
        item = rng.choice(items).upper()
        price = rng.randrange(150, 9000)
        total += price
        lines.append(f'{item} {price}')
    lines.append(rng.choice(['ÖSSZESEN', 'FIZETENDŐ', 'Összesen:', 'BANKKÁRTYA']) + f' {total} Ft')
    lines.append(rng.choice(['NYUGTA', 'Köszönjük a vásárlást!', 'ÁFA 27%', '2026.11.14 18:22', '']))
    text = noisy('\n'.join(l for l in lines if l), rng, 0.08)
    return Example(text=text, category=category, tags=['receipt'])


# --- Banki értesítések (Revolut) ---------------------------------------------

def _money(rng: random.Random, low=300, high=60000) -> str:
    value = _round(int(rng.uniform(low, high)), rng)
    r = rng.random()
    if r < 0.45:
        return f'{value:,}'.replace(',', ' ') + rng.choice([' Ft', ' HUF', ' Ft-ot', 'Ft'])
    if r < 0.6:
        return 'HUF ' + f'{value:,}' + rng.choice(['', '.00'])
    if r < 0.75:
        return f'{value / 400:.2f}'.replace('.', rng.choice(['.', ','])) + rng.choice([' €', ' EUR', '€'])
    if r < 0.85:
        return '€' + f'{value / 400:.2f}'
    if r < 0.92:
        return '$' + f'{value / 360:.2f}'
    return f'{value:,}'.replace(',', '.') + ' Ft'


def _merchant_any(rng: random.Random) -> str:
    return pick_place(rng.choice(EXPENSE_CATEGORIES), rng)


VAULTS = ['Megtakarítás', 'Nyaralás', 'Vésztartalék', 'Persely', 'Savings', 'Holiday', 'Rainy day', 'Autó', 'Lakás']


def notification(status: str, rng: random.Random) -> Example:
    m = _merchant_any(rng)
    money = _money(rng)
    person = rng.choice(vocab.PEOPLE)
    vault = rng.choice(VAULTS)
    card = rng.choice(['', ' •• 4821', ' ••7710', ' kártyával', ' (Közös)', ' Joint', ''])
    templates = {
        'expense': [
            (m, f'Fizettél {money}' + rng.choice(['', '-ot', '-et']) + rng.choice(['', ' itt: ' + m])),
            (m, f'{money} kifizetve' + card),
            (m, f'Kártyás fizetés: {money}' + card),
            ('Revolut', f'Fizetés {m} részére: {money}'),
            ('Revolut', f'{m}: -{money}'),
            (m, f'Paid {money} at {m}' + card),
            (m, f'You paid {money}' + card),
            ('Revolut', f'You spent {money} at {m}'),
            ('Revolut', f'Payment of {money} to {m}'),
            (m, f'{money} 💳' + card),
            (m, f'{money}' + card),
            ('Revolut', f'{person} {rng.choice(["fizetett", "költött"])} {money}-ot itt: {m}'),
            ('Revolut', f'{person} spent {money} at {m}'),
            ('Revolut', f'Apple Pay: {money} – {m}'),
            ('Revolut', f'Utaltál {money}-ot {person} részére'),
            ('Revolut', f'You sent {money} to {person}'),
            ('Revolut', f'Előfizetés díja: {m} {money}'),
            ('Revolut', f'Készpénzfelvétel: {money}'),
            ('Revolut', f'ATM withdrawal {money}'),
        ],
        'income': [
            ('Revolut', f'Kaptál {money}-ot {person}-tól'),
            ('Revolut', f'{person} küldött neked {money}-ot'),
            ('Revolut', f'{person} sent you {money}'),
            ('Revolut', f'You received {money} from {person}'),
            ('Revolut', f'Jóváírás: {money}'),
            ('Revolut', f'Beérkező utalás: {money}' + rng.choice(['', ' – ' + person])),
            ('Revolut', f'Visszatérítés: {m} {money}'),
            ('Revolut', f'Refund from {m}: {money}'),
            (m, f'{money} visszatérítve'),
            ('Revolut', f'Fizetés érkezett: {money}'),
            ('Revolut', f'Salary received: {money}'),
            ('Revolut', f'Cashback: {money}'),
            ('Revolut', f'Kamat jóváírva: {money}'),
            ('Revolut', f'{person} visszafizette: {money}'),
            ('Revolut', f'Money in: {money} from {person}'),
        ],
        'failed': [
            ('Revolut', f'Elutasított fizetés: {m} {money}'),
            ('Revolut', f'A fizetés elutasítva: {m}'),
            (m, f'Payment declined{rng.choice([": insufficient funds", "", " – card frozen", " by merchant"])}'),
            ('Revolut', f'Card payment declined at {m}'),
            ('Revolut', f'Nincs elég fedezet a(z) {money} összegű fizetéshez'),
            ('Revolut', 'Nincs elég fedezet a számládon'),
            ('Revolut', f'A {money} fizetés sikertelen volt'),
            ('Revolut', f'Sikertelen kártyás fizetés: {m}'),
            ('Revolut', f'Transaction failed: {m} {money}'),
            ('Revolut', f'Payment to {m} was reverted'),
            ('Revolut', f'A(z) {m} tranzakció visszavonva'),
            ('Revolut', f'Fizetés megszakítva: {m}'),
            ('Revolut', f'Insufficient balance for {money} at {m}'),
            ('Revolut', f'Your payment of {money} was cancelled'),
            ('Revolut', f'Hibás PIN – a fizetés nem sikerült ({m})'),
            ('Revolut', 'A tranzakciót elutasítottuk biztonsági okból'),
        ],
        'internal': [
            ('Revolut', f'{money} átkerült a(z) {vault} perselybe'),
            ('Revolut', f'Moved {money} to {vault}'),
            ('Revolut', f'{money} added to {vault}'),
            ('Revolut', f'Átváltottál {money}-ot'),
            ('Revolut', f'Exchanged {money} to HUF'),
            ('Revolut', f'Átváltás: {money} → EUR'),
            ('Revolut', f'Feltöltés: {money} a számládra'),
            ('Revolut', f'You topped up {money}'),
            ('Revolut', f'Money added via Apple Pay: {money}'),
            ('Revolut', f'Kerekítés: {money} a perselybe'),
            ('Revolut', f'Round-up: {money} to {vault}'),
            ('Revolut', f'Transfer between your accounts: {money}'),
            ('Revolut', f'Utalás saját számlák között: {money}'),
            ('Revolut', f'{money} átutalva a Közös számlára'),
            ('Revolut', f'Added {money} to Joint account'),
            ('Revolut', f'{money} kivéve a(z) {vault} perselyből'),
            ('Revolut', f'Withdrew {money} from {vault}'),
        ],
        'other': [
            ('Revolut', 'Erősítsd meg a bejelentkezést'),
            ('Revolut', 'Új bejelentkezés egy eszközről'),
            ('Revolut', f'A kódod: {rng.randrange(100000, 999999)}'),
            ('Revolut', f'Your verification code is {rng.randrange(100000, 999999)}'),
            ('Revolut', 'Új ajánlat vár rád a Revolut Premiummal'),
            ('Revolut', 'Elkészült a havi kimutatásod'),
            ('Revolut', 'Your monthly statement is ready'),
            ('Revolut', 'Try Revolut Metal free for 1 month'),
            ('Revolut', f'Árfolyamriasztás: EUR/HUF {rng.randrange(380, 420)}'),
            ('Revolut', f'BTC is up {rng.randrange(2, 12)}% today'),
            ('Revolut', 'A kártyád hamarosan lejár'),
            ('Revolut', 'Your card has been delivered'),
            ('Revolut', f'Cashback offer: {rng.randrange(2, 10)}% at {m}'),
            ('Revolut', 'Hagyd jóvá a fizetést az alkalmazásban'),
            ('Revolut', 'Approve this payment in the app'),
            ('Revolut', f'{person} kérést küldött: {money}'),
            ('Revolut', f'{person} requested {money}'),
            ('Revolut', f'{person} {money}-ot kért tőled'),
            ('Revolut', f'{person} pénzt kér: {money}'),
            ('Revolut', f'Fizetési kérelem: {person}, {money}'),
            ('Revolut', 'Frissítsd az alkalmazást'),
            ('Revolut', f'Költési limit: {money} ebben a hónapban'),
            ('Revolut', f'Heti összefoglaló: {money} költés'),
            ('Revolut', 'Ne feledd: holnap esedékes az előfizetésed'),
            ('Revolut', 'A kártyádat zároltuk gyanús tevékenység miatt'),
            ('Revolut', 'Your card has been frozen'),
            ('Revolut', 'Suspicious activity detected on your account'),
            ('Revolut', 'Kártyád befagyasztva'),
            ('Revolut', 'Megváltozott a PIN-kódod'),
            ('Revolut', 'Elérted a havi ingyenes készpénzfelvételi limitet'),
            ('Revolut', 'Hívd meg a barátaidat, és kapj jutalmat'),
            ('Revolut', 'Invite friends and earn rewards'),
            ('Revolut', f'{m}: új ajánlat, {rng.randrange(5, 30)}% kedvezmény'),
            ('Revolut', 'Biztonsági figyelmeztetés: új eszköz'),
            ('Revolut', 'Ellenőrizd a személyazonosságodat'),
            ('Revolut', 'Your virtual card is ready'),
            ('Revolut', 'Szállítás alatt: a kártyád úton van'),
            ('Revolut', 'Revolut Premium: 3 hónapig ingyen'),
            ('Revolut', 'Upgrade to Premium and get more'),
        ],
    }
    title, text = rng.choice(templates[status])
    if rng.random() < 0.3:
        title, text = '', f'{title} {text}'.strip()
    full = f'{title}\n{text}' if title else text
    return Example(text=noisy(full, rng, 0.05), status=status)


# --- Átvezetés saját számlák között (nem bevétel, nem kiadás) -----------------

TRANSFER_PLACES = [
    'saját', 'közös', 'megtakarítás', 'megtakarítási számla', 'közös számla',
    'saját számla', 'széf', 'Revolut', 'revolut saját', 'CIB', 'OTP', 'K&H',
    'Erste', 'MBH', 'Raiffeisen', 'UniCredit', 'Gránit', 'Wise', 'bankszámla',
    'számlám', 'másik számlám', 'Revolut Közös', 'zsebem', 'persely',
]
TRANSFER_VERBS = [
    'átraktam', 'áttettem', 'átutaltam', 'átküldtem', 'átvezettem', 'utaltam',
    'raktam át', 'tettem át', 'küldtem át', 'mozgattam', 'visszaraktam',
    'betettem', 'beraktam', 'kivettem', 'átpakoltam', 'áttoltam',
]


def transfer_sentence(rng: random.Random) -> Example:
    b = Builder()
    amount = amount_text('other_income', rng, rng.choice(['acc', None]))
    src, dst = rng.sample(TRANSFER_PLACES, 2)
    t = rng.randrange(12)
    if rng.random() < 0.2:
        b.add(rng.choice(vocab.DATE_PHRASES))
    src_word = ''.join(inflect(src, rng.choice(['elat', 'delat']), rng)).replace('-', '-')
    dst_word = ''.join(inflect(dst, rng.choice(['illat', 'sublat']), rng))
    if t == 0:
        b.add(rng.choice(TRANSFER_VERBS)); b.add(amount); b.add(article(rng, dst_word)); b.add(dst_word)
    elif t == 1:
        b.add(article(rng, src_word)); b.add(src_word); b.add(article(rng, dst_word)); b.add(dst_word); b.add(amount)
    elif t == 2:
        b.add(rng.choice(TRANSFER_VERBS)); b.add(amount); b.add(article(rng, src_word)); b.add(src_word)
        b.add(article(rng, dst_word)); b.add(dst_word)
    elif t == 3:
        b.add(rng.choice(['félretettem', 'félreraktam', 'spóroltam', 'raktam félre', 'tettem félre']))
        b.add(amount)
    elif t == 4:
        b.add(rng.choice(['felvettem', 'kivettem', 'vettem fel']))
        b.add(amount)
        b.add(rng.choice(['az automatából', 'az ATM-ből', 'készpénzben', 'kp-ban', 'a bankautomatából']))
    elif t == 5:
        b.add(rng.choice(['készpénzfelvétel', 'ATM', 'kp felvétel', 'pénzfelvétel automatából']))
        b.add(amount)
    elif t == 6:
        b.add(rng.choice(['feltöltöttem a Revolutot', 'feltöltöttem a revolut számlát', 'Revolut feltöltés',
                          'feltöltöttem a kártyát', 'topup']))
        b.add(amount)
    elif t == 7:
        b.add(rng.choice(['váltottam', 'átváltottam'])); b.add(f'{rng.randrange(20, 900)}')
        b.add(rng.choice(['eurót', 'dollárt', 'fontot', 'frankot', 'forintot euróra']))
    elif t == 8:
        b.add(rng.choice(['átvezetés', 'saját számlák között', 'belső átvezetés', 'átutalás saját számlára']))
        b.add(amount)
    elif t == 9:
        b.add(dst_word); b.add(amount)
    elif t == 10:
        b.add(rng.choice(['befizettem', 'betettem'])); b.add(amount)
        b.add(rng.choice(['készpénzt a számlámra', 'kp-t a bankba', 'a hitelkártya tartozást', 'a hitelkártyára']))
    else:
        b.add(amount); b.add(article(rng, dst_word)); b.add(dst_word); b.add(rng.choice(TRANSFER_VERBS))
    if rng.random() < 0.15:
        b.add(rng.choice(vocab.FILLERS))
    text, _ = b.build()
    return Example(text=text, intent='transfer')


# --- Kérdések (nem rögzítendők) ----------------------------------------------

QUESTION_TEMPLATES = [
    'mennyit költöttem {period}?', 'mennyi ment el {period}', 'mennyi maradt?',
    'mennyi maradt {period}', 'mennyi volt a bevételem {period}?',
    'mennyit költöttem {thing_sublat} {period}?', 'mennyi ment el {thing_sublat}',
    'mikor jön a fizetés?', 'mikor vonják le a {thing}?', 'mikor kell fizetni a {thing}?',
    'mi lesz a héten?', 'mi várható ebben a hónapban?', 'mik jönnek a héten?',
    'mennyi marad a hónap végére?', 'mennyit szoktam költeni {thing_sublat}?',
    'mennyibe kerül általában a {thing}?', 'hogyan tudok sablont létrehozni?',
    'hogy működik ez?', 'mit tudsz?', 'segíts', 'hány forint ment el {thing_sublat}?',
    'mennyi a kiadásom {period}?', 'mennyi pénzem van még?', 'mikor lesz a {thing}?',
    'mennyit kerestem {period}?', 'mutasd a {period} kiadásokat',
]
QUESTION_PERIODS = [
    'ebben a hónapban', 'a múlt hónapban', 'novemberben', 'októberben', 'tegnap',
    'ma', 'ezen a héten', 'a múlt héten', 'idén', 'tavaly', 'januárban',
]


def question_sentence(rng: random.Random) -> Example:
    category = rng.choice(EXPENSE_CATEGORIES)
    thing = pick_thing(category, rng).lower()
    stem, suffix = inflect(thing, 'sublat', rng)
    text = rng.choice(QUESTION_TEMPLATES).format(
        period=rng.choice(QUESTION_PERIODS),
        thing=thing,
        thing_sublat=stem + suffix.lstrip('-'),
    )
    if rng.random() < 0.3:
        text = text.rstrip('?')
    return Example(text=noisy(text, rng, 0.05), intent='question')


# --- Személyek: utalás, kölcsön, visszafizetés --------------------------------

def person_sentence(rng: random.Random) -> Example:
    person = rng.choice(vocab.PEOPLE)
    b = Builder()
    t = rng.randrange(8)
    if t < 3:
        # Kiadás személynek: „utaltam Petinek 5000-et a pizzáért”.
        category = rng.choice(['dining', 'transport', 'gifts', 'entertainment', 'other_expense'])
        thing = pick_thing(category, rng)
        stem, suffix = inflect(person, 'dat', rng)
        b.add(rng.choice(['utaltam', 'átutaltam', 'adtam', 'küldtem', 'fizettem']))
        b.add(stem + suffix.lstrip('-'), title=True)
        b.add(amount_text(category, rng, 'acc'))
        if category != 'other_expense' or rng.random() < 0.5:
            t_stem, t_suffix = inflect(thing, 'causal', rng)
            b.add(article(rng, t_stem)); b.add(t_stem + t_suffix.lstrip('-'), title=True)
        text, mask = b.build()
        return Example(text=text, category=category, intent='record', title_mask=mask, tags=['expense'])
    if t == 3:
        stem, suffix = inflect(person, 'dat', rng)
        b.add(rng.choice(['kölcsönadtam', 'adtam kölcsön', 'kölcsön adtam']))
        b.add(stem + suffix.lstrip('-'), title=True)
        b.add(amount_text('other_expense', rng, 'acc'))
        text, mask = b.build()
        return Example(text=text, category='other_expense', intent='record', title_mask=mask, tags=['expense'])
    if t == 4:
        b.add(person, title=True)
        b.add(rng.choice(['visszaadta a kölcsönt', 'visszaadta', 'megadta a tartozását', 'visszafizette',
                          'visszautalta']))
        b.add(amount_text('other_income', rng, rng.choice(['acc', None])))
        text, mask = b.build()
        return Example(text=text, category='other_income', intent='record', title_mask=mask, tags=['income'])
    if t == 5:
        b.add(person, title=True)
        b.add(rng.choice(['utalt', 'küldött', 'adott', 'átutalt']))
        b.add(amount_text('gift_income', rng, 'acc'))
        text, mask = b.build()
        return Example(text=text, category='gift_income', intent='record', title_mask=mask, tags=['income'])
    if t == 6:
        b.add(rng.choice(['a párom', 'a lakótársam', 'Peti', 'Anna', 'a tesóm']), title=True)
        b.add(rng.choice(['átutalta a felét', 'kifizette a részét', 'visszautalta a felét']))
        b.add(amount_text('refund', rng))
        text, mask = b.build()
        return Example(text=text, category='refund', intent='record', title_mask=mask, tags=['income'])
    stem, suffix = inflect(person, 'ablat', rng)
    b.add(rng.choice(['kaptam', 'visszakaptam', 'megkaptam']))
    b.add(stem + suffix.lstrip('-'), title=True)
    b.add(amount_text('gift_income', rng, 'acc'))
    text, mask = b.build()
    return Example(text=text, category='gift_income', intent='record', title_mask=mask, tags=['income'])


# --- Összeállítás ------------------------------------------------------------

def dataset(seed: int, scale: float = 1.0) -> list[Example]:
    rng = random.Random(seed)
    data: list[Example] = []
    n = lambda base: max(1, int(base * scale))
    for category in EXPENSE_CATEGORIES:
        for _ in range(n(2600)):
            data.append(expense_sentence(category, rng))
        for _ in range(n(1300)):
            data.append(bare_title(category, rng))
        if category in RECEIPT_ITEMS:
            for _ in range(n(500)):
                data.append(receipt(category, rng))
    for category in INCOME_CATEGORIES:
        for _ in range(n(2600)):
            data.append(income_sentence(category, rng))
        for _ in range(n(700)):
            data.append(bare_title(category, rng))
    for _ in range(n(9000)):
        data.append(create_recurring(rng))
    for _ in range(n(6000)):
        data.append(cancel_recurring(rng))
    for _ in range(n(6000)):
        data.append(change_recurring(rng))
    for _ in range(n(9000)):
        data.append(transfer_sentence(rng))
    for _ in range(n(5000)):
        data.append(question_sentence(rng))
    for _ in range(n(8000)):
        data.append(person_sentence(rng))
    for status, count in [('expense', 9000), ('income', 5000), ('failed', 5000), ('internal', 5000), ('other', 5000)]:
        for _ in range(n(count)):
            data.append(notification(status, rng))
    # Zaj a gyorsrögzítési mondatokon (a megnevezés-maszk megtartásával).
    for example in data:
        if example.title_mask is not None and rng.random() < 0.5:
            noisy_text = noisy(example.text, rng, 0.12)
            if len(raw_tokens(noisy_text)) == len(example.title_mask):
                example.text = noisy_text
    return data


if __name__ == '__main__':
    sample = dataset(1, 0.002)
    for example in random.Random(2).sample(sample, 60):
        print(example.intent or example.status, example.category, '|', example.text.replace('\n', ' / '), example.title_mask)
