/// A pénz útja a mondatban: melyik számláról vagy számlára, bankból vagy
/// készpénzből megy, saját számlák közötti átvezetés-e, kinek fizettem vagy
/// ki fizetett nekem, és milyen devizában.
library;

import '../accounts.dart';
import '../text_fold.dart';
import 'tokens.dart';

/// Merre megy a pénz egy említett számlához képest.
enum FlowDirection {
  /// Onnan jön: „a közösről”, „CIB számláról”, „az automatából”.
  from,

  /// Oda megy: „a megtakarításba”, „a Revolutra”, „a közös számlára”.
  to,

  /// Azzal fizettem: „közös kártyával”, „revoluttal”.
  via,

  /// Tárgyként szerepel: „feltöltöttem a Revolutot”.
  object,

  /// Csak megemlítettem, rag nélkül: „Megtakarítás kamata”.
  bare,
}

/// Számla, bank vagy készpénz említése.
class FlowEndpoint {
  const FlowEndpoint({
    required this.name,
    required this.tokens,
    required this.direction,
    this.accountId,
    this.isCash = false,
  });

  /// Megjelenített név: a felhasználó számlájáé, egy banké vagy „Készpénz”.
  final String name;
  final int? accountId;
  final bool isCash;
  final Set<int> tokens;
  final FlowDirection direction;
}

/// Saját számlák (bankok, készpénz) közötti átvezetés.
class TransferInfo {
  const TransferInfo({this.from, this.to, required this.tokens});

  final FlowEndpoint? from;
  final FlowEndpoint? to;

  /// Az átvezetésre utaló szavak (nem kerülnek a megnevezésbe).
  final Set<int> tokens;
}

const String cashName = 'Készpénz';

/// Kötőjel utáni önálló ragok („OTP-ről”, „Revolut-ra”, „K&H-s”).
const Set<String> _hyphenSuffixes = {
  'rol', 'rul', 'bol', 'tol', 'ra', 're', 'ba', 'be', 'val', 'vel', 'tal', //
  'tel', 's', 'os', 'es', 'as', 't', 'ot', 'et', 'at', 'hoz', 'hez', 'nal', //
  'nel', 'ban', 'ben', 'h',
};

/// Bankok és pénzügyi szolgáltatók (ékezet nélkül → megjelenített név).
const Map<String, String> _banks = {
  'cib': 'CIB',
  'otp': 'OTP',
  'erste': 'Erste',
  'mbh': 'MBH',
  'raiffeisen': 'Raiffeisen',
  'raifi': 'Raiffeisen',
  'unicredit': 'UniCredit',
  'granit': 'Gránit',
  'magnet': 'Magnet',
  'takarekbank': 'Takarékbank',
  'takarek': 'Takarékbank',
  'mkb': 'MKB',
  'kh': 'K&H',
  'wise': 'Wise',
  'paypal': 'PayPal',
  'revolut': 'Revolut',
  'bunq': 'bunq',
  'n26': 'N26',
};

/// A számlafajtákra utaló szavak.
const Map<AccountKind, List<String>> _kindWords = {
  AccountKind.personal: ['sajat'],
  AccountKind.savings: ['megtakaritas', 'megtakaritasi', 'szef', 'persely'],
  AccountKind.shared: ['kozos'],
};

const Set<String> _cashWords = {
  'keszpenz',
  'kp',
  'kesz',
  'automata',
  'bankautomata',
  'atm',
  'cash',
};

const Set<String> _fromEndings = {'rol', 'bol', 'tol', 'rul', 'bul', 'tul'};
const Set<String> _toEndings = {'ra', 're', 'ba', 'be', 'hoz', 'hez'};
const Set<String> _viaEndings = {'val', 'vel', 'tal', 'tel', 'al', 'el'};
const Set<String> _objectEndings = {'t', 'ot', 'et', 'at'};

/// A szótő utáni toldalék iránya (a birtokos „-m”, „-om”, az „-s” és az
/// „-i” képző mögött is: „számlámra”, „K&H-s”, „megtakarításiba”).
FlowDirection? _directionOf(String rest) {
  var ending = rest;
  for (final prefix in const ['unk', 'om', 'am', 'em', 'm', 'i', 's']) {
    if (ending.startsWith(prefix) && ending.length > prefix.length) {
      final shorter = ending.substring(prefix.length);
      if (_fromEndings.contains(shorter) ||
          _toEndings.contains(shorter) ||
          _viaEndings.contains(shorter) ||
          _objectEndings.contains(shorter)) {
        ending = shorter;
        break;
      }
    }
  }
  if (ending.isEmpty) return FlowDirection.bare;
  if (_fromEndings.contains(ending)) return FlowDirection.from;
  if (_toEndings.contains(ending)) return FlowDirection.to;
  if (_viaEndings.contains(ending)) return FlowDirection.via;
  if (_objectEndings.contains(ending)) return FlowDirection.object;
  if (const {
    'm',
    'om',
    'am',
    'em',
    'unk',
    'i',
    's',
    'os',
    'es',
  }.contains(ending)) {
    return FlowDirection.bare;
  }
  return null;
}

/// A „számla” és „kártya” szó iránya („számláról”, „kártyával”).
FlowDirection? _carrierDirection(String word) {
  for (final carrier in const ['szamla', 'kartya', 'kartyam']) {
    if (word.startsWith(carrier)) {
      return _directionOf(word.substring(carrier.length));
    }
  }
  return null;
}

/// A szó egy kulccsal kezdődik, és utána csak toldalék áll.
FlowDirection? _keyDirection(String word, String key) {
  if (!word.startsWith(key)) return null;
  var rest = word.substring(key.length);
  // „revoluttal”, „revolutot”: a hasonult vagy kötőhangzós toldalék.
  if (rest.isNotEmpty && rest[0] == key[key.length - 1] && rest.length > 1) {
    final direction = _directionOf(rest.substring(1));
    if (direction != null) return direction;
  }
  return _directionOf(rest);
}

/// A mondatban említett számlák, bankok és a készpénz.
List<FlowEndpoint> findEndpoints(
  List<QuickToken> tokens,
  List<Account> accounts,
) {
  final words = [for (final token in tokens) token.folded];
  final endpoints = <FlowEndpoint>[];
  final taken = <int>{};

  // Kötőjellel tapadó rag: „OTP-ről” → otp, rol; „K&H-s” → k, h, s.
  int suffixEnd(int index) {
    var next = index + 1;
    while (next < words.length &&
        next <= index + 2 &&
        _hyphenSuffixes.contains(words[next])) {
      next++;
    }
    return next;
  }

  FlowDirection resolve(int index, FlowDirection direction) {
    final after = suffixEnd(index);
    if (direction == FlowDirection.bare) {
      for (var k = index + 1; k < after; k++) {
        final glued = _directionOf(words[k]);
        if (glued != null && glued != FlowDirection.bare) direction = glued;
      }
    }
    // „a közös számláról”, „CIB számláról”, „saját kártyával”.
    if (direction == FlowDirection.bare && after < words.length) {
      final carried = _carrierDirection(words[after]);
      if (carried != null) return carried;
    }
    return direction;
  }

  Set<int> withCarrier(int index) {
    final after = suffixEnd(index);
    return {
      for (var k = index; k < after; k++) k,
      if (after < words.length && _carrierDirection(words[after]) != null)
        after,
    };
  }

  // A felhasználó számlái: név, felismerő szavak, a számla fajtája.
  for (final account in accounts) {
    final keys = <String>{
      for (final part in foldForMatching(account.name).split(' '))
        if (part.length >= 3) part,
      for (final matcher in account.matchers)
        for (final part in foldForMatching(matcher).split(' '))
          if (part.length >= 3 && !RegExp(r'^\d+$').hasMatch(part)) part,
      ...?_kindWords[account.kind],
    };
    for (var i = 0; i < words.length; i++) {
      if (taken.contains(i)) continue;
      for (final key in keys) {
        final direction = _keyDirection(words[i], key);
        if (direction == null) continue;
        endpoints.add(
          FlowEndpoint(
            name: account.name,
            accountId: account.id,
            tokens: withCarrier(i),
            direction: resolve(i, direction),
          ),
        );
        taken.add(i);
        break;
      }
    }
  }

  // Ha a „revolut” egyik számla felismerője sem, a Revolut a saját számla.
  final personal = accounts.where((a) => a.kind == AccountKind.personal);
  final fallbackPersonal = personal.isEmpty
      ? null
      : personal.firstWhere((a) => a.isDefault, orElse: () => personal.first);

  for (var i = 0; i < words.length; i++) {
    if (taken.contains(i)) continue;
    final word = words[i];
    // K&H: a tokenizáló „k” és „h” betűre bontja.
    if (word == 'k' &&
        i + 1 < words.length &&
        (words[i + 1] == 'h' || words[i + 1].startsWith('h'))) {
      final direction = resolve(
        i,
        _directionOf(words[i + 1].substring(1)) ?? FlowDirection.bare,
      );
      endpoints.add(
        FlowEndpoint(name: 'K&H', tokens: withCarrier(i), direction: direction),
      );
      taken.addAll({i, i + 1});
      continue;
    }
    for (final MapEntry(key: key, value: name) in _banks.entries) {
      final direction = _keyDirection(word, key);
      if (direction == null) continue;
      final account = key == 'revolut' ? fallbackPersonal : null;
      endpoints.add(
        FlowEndpoint(
          name: account?.name ?? name,
          accountId: account?.id,
          tokens: withCarrier(i),
          direction: resolve(i, direction),
        ),
      );
      taken.add(i);
      break;
    }
    if (taken.contains(i)) continue;
    for (final key in _cashWords) {
      final direction = key.length <= 4
          ? (word == key ? FlowDirection.bare : _keyDirection(word, key))
          : _keyDirection(word, key);
      if (direction == null) continue;
      if (key == 'kesz' && !(i + 1 < words.length && words[i + 1] == 'penz')) {
        continue;
      }
      endpoints.add(
        FlowEndpoint(
          name: cashName,
          isCash: true,
          tokens: {i},
          direction: resolve(i, direction),
        ),
      );
      taken.add(i);
      break;
    }
    if (taken.contains(i)) continue;
    // Puszta „számlámra”, „számláról”: a saját (alapértelmezett) számla.
    if (word.startsWith('szamla') && fallbackPersonal != null) {
      final direction = _directionOf(word.substring(6));
      if (direction == FlowDirection.from || direction == FlowDirection.to) {
        endpoints.add(
          FlowEndpoint(
            name: fallbackPersonal.name,
            accountId: fallbackPersonal.id,
            tokens: {i},
            direction: direction!,
          ),
        );
        taken.add(i);
      }
    }
  }
  endpoints.sort((a, b) => a.tokens.first.compareTo(b.tokens.first));
  return endpoints;
}

/// Áthelyezésre utaló igék szótöve („átraktam”, „áttettem”, „félretettem”).
const List<String> _moveStems = [
  'atrak',
  'attet',
  'atutal',
  'atkuld',
  'atvezet',
  'atvalt',
  'atmozgat',
  'felretet',
  'felrerak',
  'betet',
  'berak',
  'kivet',
  'kiveszem',
  'feltolt',
  'visszarak',
  'visszatet',
  'visszautal',
  'mozgat',
  'utal',
  'kuld',
  'tettem',
  'raktam',
  'befizet',
];

/// Más fizet vagy ad nekem pénzt, vagy én fizetek valakinek („adtam”,
/// „visszaadta”, „átutalta”, „kifizettek”).
const List<String> _moneyVerbRoots = [
  'kolcsonad',
  'visszafizet',
  'visszautal',
  'visszaterit',
  'visszaad',
  'visszakuld',
  'atutal',
  'atkuld',
  'kifizet',
  'befizet',
  'megad',
  'jovair',
  'terit',
  'fizet',
  'utal',
  'kuld',
  'ad',
];

const Set<String> _firstPersonEndings = {
  'tam',
  'tem',
  'ttam',
  'ttem',
  'tunk',
  'tuk',
  'ttunk',
  'ottam',
  'ettem',
  'otam',
  'ok',
  'ek',
  'om',
  'em',
  'unk',
};
const Set<String> _thirdPersonEndings = {
  't',
  'tt',
  'ott',
  'ett',
  'ta',
  'te',
  'tta',
  'tte',
  'tak',
  'tek',
  'ttak',
  'ttek',
  'ottak',
  'ettek',
};

/// Pénzt adó ige személye: 1 = én adtam, 3 = más adott (nekem).
int? moneyVerbPerson(String word) {
  for (final root in _moneyVerbRoots) {
    if (!word.startsWith(root)) continue;
    final rest = word.substring(root.length);
    if (_firstPersonEndings.contains(rest)) return 1;
    if (_thirdPersonEndings.contains(rest)) return 3;
    return null;
  }
  return null;
}

/// Rokon, ismerős vagy személynév részeshatározóval („anyának”, „Petinek”).
const Set<String> _relationStems = {
  'anya',
  'anyu',
  'anyuka',
  'anyos',
  'apa',
  'apu',
  'apuka',
  'apos',
  'mama',
  'papa',
  'nagymama',
  'nagypapa',
  'nagyi',
  'mami',
  'tata',
  'teso',
  'tesom',
  'testver',
  'testverem',
  'batyam',
  'ocsem',
  'noverem',
  'hugom',
  'parom',
  'parja',
  'barat',
  'baratom',
  'baratnom',
  'baratnoje',
  'ferjem',
  'felesegem',
  'fiam',
  'lanyom',
  'gyerek',
  'gyerekem',
  'gyereknek',
  'fonok',
  'fonokom',
  'kollega',
  'kollegam',
  'szomszed',
  'szomszedom',
  'ismeros',
  'ismerosom',
  'haver',
  'haverom',
  'unokaocs',
  'keresztlany',
  'keresztfiam',
  'ugyfel',
  'ugyfelem',
  'megrendelo',
};

/// Személy a mondatban, és a pénz iránya hozzá képest.
class PersonMention {
  const PersonMention(this.index, {required this.recipient});

  final int index;

  /// `true`: neki ment a pénz („Petinek”); `false`: tőle jött („anyától”).
  final bool recipient;
}

String? _relationRest(String word) {
  String? best;
  for (final stem in _relationStems) {
    if (word.startsWith(stem) && (best == null || stem.length > best.length)) {
      best = stem;
    }
  }
  return best == null ? null : word.substring(best.length);
}

/// Részeshatározós („-nak/-nek”) vagy „-tól/-től” személy a mondatban.
List<PersonMention> findPeople(
  List<QuickToken> tokens, {
  required bool Function(int index) isKnownName,
}) {
  final people = <PersonMention>[];
  for (var i = 0; i < tokens.length; i++) {
    final word = tokens[i].folded;
    final original = tokens[i].original;
    final rest = _relationRest(word);
    final capitalized =
        original.isNotEmpty &&
        original[0] != original[0].toLowerCase() &&
        !isKnownName(i);
    String? ending;
    if (rest != null) {
      ending = rest;
    } else if (capitalized && word.length >= 5) {
      for (final suffix in const ['nak', 'nek', 'tol', 'tol']) {
        if (word.endsWith(suffix)) ending = suffix;
      }
    }
    if (ending == null) continue;
    // Birtokos személyjel a rag előtt: „anyukámnak”, „barátomtól”.
    for (final prefix in const ['am', 'om', 'em', 'm', 'nk', 'unk', 'ja']) {
      if (ending!.startsWith(prefix) && ending.length > prefix.length) {
        final shorter = ending.substring(prefix.length);
        if (const {'nak', 'nek', 'tol'}.contains(shorter)) ending = shorter;
      }
    }
    if (ending == 'nak' || ending == 'nek') {
      people.add(PersonMention(i, recipient: true));
    } else if (ending == 'tol') {
      people.add(PersonMention(i, recipient: false));
    } else if (rest != null && (ending!.isEmpty || ending == 'm')) {
      // Alanyként: „anya utalt”, „a párom átutalta”.
      people.add(PersonMention(i, recipient: false));
    }
  }
  return people;
}

const Set<String> _feeWords = {
  'dij',
  'dija',
  'dijat',
  'dijak',
  'jutalek',
  'jutaleka',
  'koltseg',
  'koltsege',
  'kezelesi',
};

const Set<String> _currencyWords = {
  'euro',
  'eur',
  'eurot',
  'eurora',
  'eurobol',
  'dollar',
  'dollart',
  'dollarra',
  'usd',
  'forint',
  'forintot',
  'forintra',
  'font',
  'fontot',
  'frank',
  'korona',
  'koronat',
  'zloty',
  'lej',
  'deviza',
  'devizat',
  'valuta',
  'valutat',
};

bool _anyStartsWith(List<String> words, String prefix) =>
    words.any((word) => word.startsWith(prefix));

/// Saját számlák, bankok vagy készpénz közötti mozgás (átvezetés).
///
/// [personRecipient]: valakinek ment a pénz („anyának”) – ez nem átvezetés.
/// [purchase]: vásárlásra utaló szó van a mondatban („pizzáért”, „lakbért”).
TransferInfo? detectTransfer(
  List<QuickToken> tokens,
  List<FlowEndpoint> endpoints, {
  required bool personRecipient,
  required bool purchase,
  bool otherContent = false,
  String? savingsName,
}) {
  final words = _joinSeparatedPrefixes([
    for (final token in tokens) token.folded,
  ]);
  if (words.any(_feeWords.contains) ||
      words.any((w) => w.startsWith('keszpenzfelveteli'))) {
    return null;
  }
  final verbIndexes = <int>{
    for (var i = 0; i < words.length; i++)
      if (_moveStems.any(words[i].startsWith)) i,
  };
  FlowEndpoint? pick(Iterable<FlowDirection> directions) {
    for (final endpoint in endpoints) {
      if (directions.contains(endpoint.direction)) return endpoint;
    }
    return null;
  }

  final used = {
    ...verbIndexes,
    for (final endpoint in endpoints) ...endpoint.tokens,
  };
  final from = pick(const [FlowDirection.from]);
  var to = pick(const [FlowDirection.to]);

  // Készpénzfelvétel: „felvettem 20 ezret az automatából”, „ATM 30000”.
  final cash = endpoints.where((e) => e.isCash).toList();
  final withdrawal =
      _anyStartsWith(words, 'keszpenzfelvet') ||
      (cash.isNotEmpty &&
          (cash.any(
                (e) => const {
                  'atm',
                  'automata',
                  'bankautomata',
                }.any((k) => words[e.tokens.first].startsWith(k)),
              ) ||
              words.any((w) => w.startsWith('felvet') || w == 'felvetel')));
  final deposit =
      cash.isNotEmpty &&
      words.any((w) => w.startsWith('befizet') || w.startsWith('betet'));
  if (deposit && !withdrawal) {
    final account = endpoints.where((e) => !e.isCash);
    return TransferInfo(
      from: cash.first,
      to: account.isEmpty ? null : account.first,
      tokens: used,
    );
  }
  if (withdrawal) {
    final source = endpoints.where(
      (e) => !e.isCash && e.direction != FlowDirection.to,
    );
    return TransferInfo(
      from: source.isEmpty ? null : source.first,
      to: const FlowEndpoint(
        name: cashName,
        isCash: true,
        tokens: {},
        direction: FlowDirection.to,
      ),
      tokens: {
        ...used,
        for (var i = 0; i < words.length; i++)
          if (words[i].startsWith('keszpenzfelvet') ||
              words[i].startsWith('felvet'))
            i,
      },
    );
  }

  // Pénzváltás: „váltottam 100 eurót”, „átváltottam 40 000 forintot euróra”.
  final exchange =
      words.any((w) => w.startsWith('atvalt') || w.startsWith('valtott')) &&
      words.any(_currencyWords.contains);
  if (exchange) return TransferInfo(tokens: used);

  // Hitelkártya-tartozás befizetése.
  if (_anyStartsWith(words, 'hitelkartya') &&
      words.any(
        (w) =>
            w.startsWith('tartoz') ||
            w.startsWith('befizet') ||
            w.startsWith('torleszt'),
      )) {
    return TransferInfo(
      to: const FlowEndpoint(
        name: 'Hitelkártya',
        tokens: {},
        direction: FlowDirection.to,
      ),
      tokens: used,
    );
  }

  if (personRecipient) return null;

  // „Átvezetés saját számlák között”.
  if (_anyStartsWith(words, 'atvezet')) {
    return TransferInfo(from: from, to: to, tokens: used);
  }

  // Félretettem: a megtakarításba.
  if (words.any((w) => w.startsWith('felretet') || w.startsWith('felrerak'))) {
    return TransferInfo(
      from: from,
      to:
          to ??
          FlowEndpoint(
            name: savingsName ?? 'Megtakarítás',
            tokens: const {},
            direction: FlowDirection.to,
          ),
      tokens: used,
    );
  }

  // Feltöltöttem a Revolutot: tárgyként a cél.
  if (to == null && words.any((w) => w.startsWith('feltolt'))) {
    to = pick(const [FlowDirection.object]);
  }
  if (from == null && to == null) return null;
  if (purchase) return null;
  final hasVerb = verbIndexes.isNotEmpty;
  // Csak a cél és az összeg: „közösbe 50 ezer”, „megtakarításba 100 000”.
  if (to != null && from == null && !hasVerb && !otherContent) {
    return TransferInfo(to: to, tokens: used);
  }
  // Két végpont (honnan és hová), vagy egy végpont áthelyező igével.
  if ((from != null && to != null) || hasVerb) {
    // A „fizettem” vagy „vettem” vásárlás; a forrásszámla ilyenkor csak azt
    // mondja meg, honnan fizettem.
    if (from != null && to == null && !_moveFromVerb(words)) return null;
    return TransferInfo(from: from, to: to, tokens: used);
  }
  return null;
}

/// Az ige után álló igekötő visszailleszthető: „raktam félre” → „félreraktam”,
/// „tettem át” → „áttettem”, „vettem ki” → „kivettem”. A szavak száma marad
/// (az igekötő helyén üres szó), hogy az indexek egyezzenek.
List<String> _joinSeparatedPrefixes(List<String> words) {
  final result = [...words];
  for (var i = 0; i + 1 < words.length; i++) {
    final prefix = words[i + 1];
    if (!const {'at', 'felre', 'vissza', 'be', 'ki', 'fel'}.contains(prefix)) {
      continue;
    }
    final verb = words[i];
    if (!RegExp(r'(tt?am|tt?em|tt?unk|tt?uk|tt?a|tt?e)$').hasMatch(verb)) {
      continue;
    }
    result[i] = '$prefix$verb';
    result[i + 1] = '';
  }
  return result;
}

/// Forrásszámlával is átvezetést jelentő ige („kivettem”, „visszaraktam”).
bool _moveFromVerb(List<String> words) => words.any(
  (w) =>
      w.startsWith('kivet') ||
      w.startsWith('kiveszem') ||
      w.startsWith('visszarak') ||
      w.startsWith('visszatet') ||
      w.startsWith('atrak') ||
      w.startsWith('attet') ||
      w.startsWith('atutal') ||
      w.startsWith('atkuld') ||
      w.startsWith('mozgat'),
);

/// Devizás összeg a mondatban.
class ForeignAmount {
  const ForeignAmount(this.amount, this.currency, this.tokens);

  final double amount;

  /// ISO-kód: EUR, USD, GBP, CHF, CZK, PLN, RON …
  final String currency;
  final Set<int> tokens;
}

const Map<String, String> _currencyCodes = {
  'euro': 'EUR',
  'eur': 'EUR',
  'eurot': 'EUR',
  'euros': 'EUR',
  'euroert': 'EUR',
  'dollar': 'USD',
  'dollart': 'USD',
  'dollarert': 'USD',
  'dollaros': 'USD',
  'usd': 'USD',
  'font': 'GBP',
  'fontot': 'GBP',
  'fontert': 'GBP',
  'gbp': 'GBP',
  'frank': 'CHF',
  'frankot': 'CHF',
  'chf': 'CHF',
  'czk': 'CZK',
  'pln': 'PLN',
  'zloty': 'PLN',
  'zlotyt': 'PLN',
  'ron': 'RON',
  'lej': 'RON',
  'lejt': 'RON',
};

/// „25 euró”, „40 €”, „$12”, „200 cseh korona”.
ForeignAmount? findForeignAmount(String text, List<QuickToken> tokens) {
  double? number(String folded) {
    final match = RegExp(r'^(\d+(?:[.,]\d+)?)').firstMatch(folded);
    if (match == null) return null;
    return double.tryParse(match.group(1)!.replaceAll(',', '.'));
  }

  for (var i = 0; i < tokens.length; i++) {
    final value = number(tokens[i].folded);
    if (value == null) continue;
    // Közvetlenül a szám után a deviza neve vagy jele.
    final glued = tokens[i].folded.replaceFirst(RegExp(r'^[\d.,]+'), '');
    final next = i + 1 < tokens.length ? tokens[i + 1].folded : '';
    final afterNext = i + 2 < tokens.length ? tokens[i + 2].folded : '';
    String? code = _currencyCodes[glued] ?? _currencyCodes[next];
    var used = {i, if (_currencyCodes[next] != null) i + 1};
    if (code == null && next == 'cseh' && afterNext.startsWith('korona')) {
      code = 'CZK';
      used = {i, i + 1, i + 2};
    }
    if (code == null && next.startsWith('korona')) {
      code = 'CZK';
      used = {i, i + 1};
    }
    final between = text.substring(
      tokens[i].end.clamp(0, text.length),
      i + 1 < tokens.length ? tokens[i + 1].start : text.length,
    );
    final before = text.substring(
      i > 0 ? tokens[i - 1].end.clamp(0, text.length) : 0,
      tokens[i].start.clamp(0, text.length),
    );
    code ??= _symbolCode(between) ?? _symbolCode(before);
    if (code != null) return ForeignAmount(value, code, used);
  }
  return null;
}

String? _symbolCode(String text) {
  if (text.contains('€')) return 'EUR';
  if (text.contains(r'$')) return 'USD';
  if (text.contains('£')) return 'GBP';
  return null;
}
