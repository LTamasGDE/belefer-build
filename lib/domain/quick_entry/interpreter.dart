import '../calendar.dart';
import '../categories.dart';
import '../models.dart';
import '../recurring.dart';
import '../text_fold.dart';
import '../validation.dart';
import 'amount_parser.dart';
import 'date_parser.dart';
import 'lexicon.dart';
import 'tokens.dart';

/// Mit szeretne a felhasználó a beírt mondattal.
enum QuickIntent {
  /// Egy kiadás vagy bevétel rögzítése.
  record,

  /// Új ismétlődő tétel (pl. „előfizettem a Spotify-ra, havi 1990”).
  createRecurring,

  /// Ismétlődő tétel lemondása (pl. „lemondtam a Netflixet”).
  cancelRecurring,

  /// Ismétlődő tétel összegének módosítása (pl. „mostantól 150 000 a lakbér”).
  changeRecurring,
}

/// A rögzítéshez szükséges kérdések.
enum QuickQuestion {
  /// Mennyi? (kötelező)
  amount,

  /// Mire / hol? (kötelező)
  what,

  /// Mikor? (alapból ma)
  when,

  /// Kiadás vagy bevétel? (alapból kiadás)
  type,

  /// Milyen gyakran? (ismétlődő tételnél)
  frequency,

  /// Melyik ismétlődő tétel? (lemondásnál, módosításnál)
  which,
}

/// A mondat értelmezése.
class QuickEntryResult {
  const QuickEntryResult({
    required this.intent,
    required this.type,
    required this.typeExplicit,
    required this.amount,
    required this.title,
    required this.merchant,
    required this.categoryId,
    required this.categoryGuessed,
    required this.date,
    required this.dateExplicit,
    this.frequency,
    this.interval = 1,
    this.targetRule,
    this.notes = const [],
    this.fromAi = false,
  });

  final QuickIntent intent;
  final EntryType type;
  final bool typeExplicit;
  final int? amount;
  final String? title;
  final String? merchant;

  /// A kategória (ha nem derült ki, a típus „Egyéb” kategóriája).
  final String categoryId;

  /// Nem a szövegből derült ki, hanem alapértelmezés.
  final bool categoryGuessed;
  final CalendarDay date;
  final bool dateExplicit;
  final Frequency? frequency;
  final int interval;

  /// Lemondásnál és módosításnál az érintett ismétlődő tétel.
  final RecurringRule? targetRule;

  /// Figyelmeztetések, pl. több szám is szerepelt.
  final List<String> notes;

  /// Az AI értelmezte (nem csak a beépített értelmező).
  final bool fromAi;

  bool get hasAmount => amount != null && amount! > 0;
  bool get hasWhat => title != null && title!.trim().isNotEmpty;

  /// Melyik kérdésre van már válasz.
  bool isAnswered(QuickQuestion question) => switch (question) {
    QuickQuestion.amount => hasAmount,
    QuickQuestion.what => hasWhat,
    QuickQuestion.when => dateExplicit,
    QuickQuestion.type => typeExplicit,
    QuickQuestion.frequency => frequency != null,
    QuickQuestion.which => targetRule != null,
  };

  /// A szándékhoz tartozó kérdések, a kötelezők elöl.
  List<QuickQuestion> get questions => switch (intent) {
    QuickIntent.record => const [
      QuickQuestion.amount,
      QuickQuestion.what,
      QuickQuestion.when,
      QuickQuestion.type,
    ],
    QuickIntent.createRecurring => const [
      QuickQuestion.amount,
      QuickQuestion.what,
      QuickQuestion.frequency,
      QuickQuestion.when,
    ],
    QuickIntent.cancelRecurring => const [QuickQuestion.which],
    QuickIntent.changeRecurring => const [
      QuickQuestion.which,
      QuickQuestion.amount,
      QuickQuestion.when,
    ],
  };

  /// A még megválaszolandó kötelező kérdések.
  List<QuickQuestion> get missing => [
    for (final question in questions)
      if (_isRequired(question) && !isAnswered(question)) question,
  ];

  bool _isRequired(QuickQuestion question) => switch (question) {
    QuickQuestion.amount => intent != QuickIntent.cancelRecurring,
    QuickQuestion.what =>
      intent == QuickIntent.record || intent == QuickIntent.createRecurring,
    QuickQuestion.which =>
      intent == QuickIntent.cancelRecurring ||
          intent == QuickIntent.changeRecurring,
    QuickQuestion.frequency => false,
    QuickQuestion.when => false,
    QuickQuestion.type => false,
  };

  /// Automatikusan elkönyvelhető-e.
  bool get isComplete => missing.isEmpty;

  /// Rögzítendő tétel (a [QuickIntent.record] szándékhoz).
  Transaction? toTransaction() {
    if (!hasAmount || !hasWhat) return null;
    return Transaction(
      type: type,
      title: title!,
      amount: amount!,
      categoryId: categoryId,
      date: date,
    );
  }

  /// Új ismétlődő szabály (a [QuickIntent.createRecurring] szándékhoz).
  RecurringRule? toRecurringRule({
    ReminderSettings reminder = const ReminderSettings(),
  }) {
    if (!hasAmount || !hasWhat) return null;
    return RecurringRule(
      type: type,
      title: title!,
      categoryId: categoryId,
      amount: amount!,
      frequency: frequency ?? Frequency.monthly,
      interval: interval,
      startDate: date,
      reminder: reminder,
    );
  }
}

/// A felhasználó adatai, amelyekből az értelmező tanul.
class QuickEntryContext {
  const QuickEntryContext({
    required this.today,
    this.history = const [],
    this.rules = const [],
  });

  final CalendarDay today;

  /// Korábbi tételek: a megnevezésekből tanulja a kategóriákat.
  final List<Transaction> history;

  /// Az ismétlődő tételek (lemondáshoz, módosításhoz).
  final List<RecurringRule> rules;
}

class _CategoryVote {
  _CategoryVote(this.categoryId, this.score, this.title, this.tokens);

  final String categoryId;
  final int score;
  final String? title;
  final Set<int> tokens;
}

/// A gyorsrögzítés értelmezője: a beírt mondatból tételt, ismétlődő tételt,
/// lemondást vagy módosítást készít.
///
/// A telefonon fut, internet nélkül. Tűri az elírásokat, a toldalékokat és a
/// szórend felcserélését, és a korábbi tételekből tanul.
QuickEntryResult interpretQuickEntry(String text, QuickEntryContext context) {
  final tokens = tokenize(text);
  final folded = [for (final token in tokens) token.folded];
  final today = context.today;

  // Szándék (előbb, mert a dátum értelmezése függ tőle).
  final cancel = _findAny(folded, recurringCancelWords);
  final change = _findAny(folded, recurringChangeWords);
  const weakCreateWords = {'havi', 'heti', 'eves', 'evi'};
  final createStrong =
      _findAny(folded, recurringCreateWords.difference(weakCreateWords)) ||
      _hasPhrase(folded, ['minden', 'honap']) ||
      _hasPhrase(folded, ['minden', 'het']) ||
      _hasPhrase(folded, ['minden', 'ev']);
  final createWeak = folded.any(weakCreateWords.contains);

  final dateMatch = findDate(
    text,
    tokens,
    today,
    preferFuture: createStrong && !cancel,
  );
  final blocked = <int>{...?dateMatch?.tokenIndexes};

  // Összeg.
  final candidates = findAmountCandidates(folded, blocked: blocked);
  final amountPick = pickAmount(candidates);
  final used = <int>{...blocked, ...?amountPick?.tokenIndexes};
  final notes = <String>[];
  final strongCandidates = candidates.where((c) => c.score >= 6).length;
  if (amountPick != null &&
      candidates.length > 1 &&
      (strongCandidates != 1 || amountPick.score < 6)) {
    notes.add('Több szám is szerepelt – ellenőrizd az összeget.');
  }

  // Típus.
  var incomeScore = 0;
  var expenseScore = 0;
  final verbTokens = <int>{};
  for (var i = 0; i < folded.length; i++) {
    if (used.contains(i)) continue;
    final word = folded[i];
    if (expenseWords.contains(word)) {
      expenseScore += 3;
      verbTokens.add(i);
    } else if (incomeWords.contains(word)) {
      incomeScore += 3;
      verbTokens.add(i);
    } else if (word.length >= 7 && !_lexiconWords.contains(word)) {
      if (_fuzzyIn(word, expenseWords)) {
        expenseScore += 2;
        verbTokens.add(i);
      } else if (_fuzzyIn(word, incomeWords)) {
        incomeScore += 2;
        verbTokens.add(i);
      }
    }
  }
  // „Visszakaptam” és „kaptam” után a kategória szava erősebb a „fizettem”-nél.
  EntryType? explicitType;
  if (incomeScore > expenseScore) explicitType = EntryType.income;
  if (expenseScore > incomeScore) explicitType = EntryType.expense;

  // Kategória és kereskedő.
  final votes = <_CategoryVote>[];
  final merchantVote = _matchMerchant(folded, used, verbTokens);
  if (merchantVote != null) votes.add(merchantVote.$1);
  votes.addAll(_matchKeywords(folded, used, verbTokens));
  votes.addAll(_matchCustomCategories(folded, used));
  votes.addAll(_matchHistory(tokens, used, context.history));

  // A típushoz illő szavazatok; ha nincs kifejezett típus, a legerősebb dönt.
  _CategoryVote? best;
  for (final vote in votes) {
    final category = categoryById(vote.categoryId);
    if (category == null) continue;
    if (explicitType != null && category.type != explicitType) continue;
    if (best == null || vote.score > best.score) best = vote;
  }
  if (best == null && explicitType != null) {
    // A kifejezett típus ellenére sincs illő kategória: a legerősebb jelöltet
    // vesszük, és a típust a kategóriáé adja (pl. „fizettem a lakbért”).
    for (final vote in votes) {
      if (categoryById(vote.categoryId) == null) continue;
      if (best == null || vote.score > best.score) best = vote;
    }
    if (best != null && categoryById(best.categoryId)!.type != explicitType) {
      // Ellentmondás esetén a kifejezett típus marad, a kategória nem.
      best = null;
    }
  }
  final type =
      explicitType ??
      (best != null ? categoryById(best.categoryId)!.type : EntryType.expense);
  final categoryId = best?.categoryId ?? CategoryCatalog.fallbackIdFor(type);

  // Szándék véglegesítése és célszabály.
  var intent = QuickIntent.record;
  RecurringRule? target;
  if (cancel) {
    intent = QuickIntent.cancelRecurring;
    target = _matchRule(folded, used, context.rules, categoryId, best != null);
  } else if (change && amountPick != null) {
    target = _matchRule(folded, used, context.rules, categoryId, best != null);
    intent = target != null
        ? QuickIntent.changeRecurring
        : QuickIntent.createRecurring;
    if (target == null) {
      notes.add('Nincs ilyen ismétlődő tétel, újként veszem fel.');
    }
  } else if (createStrong) {
    intent = QuickIntent.createRecurring;
  } else if (createWeak &&
      explicitType == null &&
      const {
        'subscriptions',
        'housing',
        'utilities',
        'salary',
        'scholarship',
      }.contains(categoryId)) {
    // „Netflix havi 4990”, „havi lakbér 180 000”: rendszeres tétel; a
    // „kifizettem a havi bérletet” viszont egyszeri kiadás.
    intent = QuickIntent.createRecurring;
  }

  // Gyakoriság.
  Frequency? frequency;
  var interval = 1;
  if (intent == QuickIntent.createRecurring) {
    (frequency, interval) = _frequencyOf(folded);
    if (frequency == null &&
        (categoryId == 'subscriptions' ||
            categoryId == 'housing' ||
            categoryId == 'utilities' ||
            categoryId == 'salary' ||
            categoryId == 'scholarship' ||
            _findAny(folded, const {
              'elofizettem',
              'elofizetes',
              'elofizetest',
            }))) {
      frequency = Frequency.monthly;
    }
  }

  // Megnevezés.
  final consumed = <int>{
    ...used,
    ...verbTokens,
    for (var i = 0; i < folded.length; i++)
      if (recurringCreateWords.contains(folded[i]) ||
          recurringCancelWords.contains(folded[i]) ||
          recurringChangeWords.contains(folded[i]))
        i,
  };
  String? title;
  String? merchant;
  if (merchantVote != null && merchantVote.$1.categoryId == categoryId) {
    merchant = merchantVote.$2;
    title = merchant;
  } else if (merchantVote != null && best == null) {
    merchant = merchantVote.$2;
    title = merchant;
  }
  // Megnevezés: kereskedő > kulcsszó (vagy tanult megnevezés) > a mondat
  // maradék szavai > a kategória neve.
  title ??= best?.title ?? _leftoverPhrase(tokens, consumed);
  if (title == null && best != null) title = categoryName(categoryId);
  if (intent == QuickIntent.cancelRecurring ||
      intent == QuickIntent.changeRecurring) {
    title = target?.title ?? title;
  }
  if (title != null && title.length > EntryRules.titleMaxLength) {
    title = title.substring(0, EntryRules.titleMaxLength).trim();
  }

  // Dátum: ismétlődő tételnél a következő alkalom, egyébként alapból ma.
  var date = dateMatch?.day ?? today;
  if (intent == QuickIntent.changeRecurring && dateMatch == null) {
    date = target?.nextOccurrence(today) ?? today;
  }

  return QuickEntryResult(
    intent: intent,
    type: target?.type ?? type,
    typeExplicit: explicitType != null || best != null || target != null,
    amount: amountPick?.value,
    title: title,
    merchant: merchant,
    categoryId: target?.categoryId ?? categoryId,
    categoryGuessed: best == null && target == null,
    date: date,
    dateExplicit: dateMatch != null,
    frequency: intent == QuickIntent.createRecurring
        ? (frequency ?? Frequency.monthly)
        : null,
    interval: interval,
    targetRule: target,
    notes: notes,
  );
}

/// A kategória-kulcsszavak és kereskedőnevek (egy szóból állók): ezeket nem
/// tekintjük elírt igének („fizetés” ≠ „fizetem”).
final Set<String> _lexiconWords = {
  for (final keyword in keywords)
    if (!keyword.key.contains(' ')) keyword.key,
  for (final merchant in merchants)
    for (final key in merchant.keys)
      if (!key.contains(' ')) key,
};

bool _findAny(List<String> words, Set<String> set) {
  for (final word in words) {
    if (set.contains(word)) return true;
    if (word.length >= 7 && _fuzzyIn(word, set)) return true;
  }
  return false;
}

bool _fuzzyIn(String word, Set<String> set) {
  for (final key in set) {
    if (key.length < 6) continue;
    if (editDistance(word, key, maxDistance: 1) <= 1) return true;
  }
  return false;
}

bool _hasPhrase(List<String> words, List<String> phrase) {
  for (var i = 0; i + phrase.length <= words.length; i++) {
    var ok = true;
    for (var j = 0; j < phrase.length; j++) {
      final word = words[i + j];
      if (!(word == phrase[j] ||
          (phrase[j].length >= 3 && word.startsWith(phrase[j])))) {
        ok = false;
        break;
      }
    }
    if (ok) return true;
  }
  return false;
}

/// Illeszkedik-e egy (egy- vagy többszavas) kulcs a szöveg egy pontján.
/// Visszaadja a felhasznált tokenek indexeit.
Set<int>? _matchKey(
  List<String> words,
  String key,
  Set<int> skip, {
  bool strictShort = true,
}) {
  final parts = key.split(' ');
  if (parts.length > 1) {
    for (var i = 0; i + parts.length <= words.length; i++) {
      var ok = true;
      for (var j = 0; j < parts.length; j++) {
        if (skip.contains(i + j)) {
          ok = false;
          break;
        }
        final word = words[i + j];
        final part = parts[j];
        final last = j == parts.length - 1;
        final matches =
            word == part ||
            (last && part.length >= 3 && fuzzyWordMatch(word, part));
        if (!matches) {
          ok = false;
          break;
        }
      }
      if (ok) return {for (var j = 0; j < parts.length; j++) i + j};
    }
    // Egybeírva: „burgerking”, „wcpapir”.
    final joined = parts.join();
    for (var i = 0; i < words.length; i++) {
      if (skip.contains(i)) continue;
      if (words[i] == joined || fuzzyWordMatch(words[i], joined)) return {i};
    }
    return null;
  }
  for (var i = 0; i < words.length; i++) {
    if (skip.contains(i)) continue;
    final word = words[i];
    if (RegExp(r'^\d').hasMatch(word)) continue;
    if (key.length <= 2) {
      if (word == key) return {i};
      continue;
    }
    if (key.length == 3 && strictShort) {
      if (word == key ||
          (word.startsWith(key) &&
              hungarianSuffixes.contains(word.substring(3)))) {
        return {i};
      }
      continue;
    }
    if (fuzzyWordMatch(word, key)) return {i};
  }
  return null;
}

(_CategoryVote, String)? _matchMerchant(
  List<String> words,
  Set<int> used,
  Set<int> verbs,
) {
  final skip = {...used, ...verbs};
  (_CategoryVote, String)? best;
  for (final merchant in merchants) {
    for (final key in merchant.keys) {
      final hit = _matchKey(words, key, skip);
      if (hit == null) continue;
      final exact =
          hit.length > 1 ||
          words[hit.first] == key ||
          words[hit.first].startsWith(key);
      final score = exact ? 12 + key.length ~/ 4 : 9;
      if (best == null || score > best.$1.score) {
        best = (
          _CategoryVote(merchant.categoryId, score, merchant.name, hit),
          merchant.name,
        );
      }
    }
  }
  return best;
}

List<_CategoryVote> _matchKeywords(
  List<String> words,
  Set<int> used,
  Set<int> verbs,
) {
  final skip = {...used};
  final votes = <_CategoryVote>[];
  for (final keyword in keywords) {
    final hit = _matchKey(words, keyword.key, skip);
    if (hit == null) continue;
    // Igéből (pl. „tankoltam”) csak akkor, ha a kulcsszó pontosan az.
    if (hit.length == 1 &&
        verbs.contains(hit.first) &&
        words[hit.first] != keyword.key) {
      continue;
    }
    final exact = hit.length > 1 || words[hit.first] == keyword.key;
    votes.add(
      _CategoryVote(
        keyword.categoryId,
        keyword.weight + (exact ? 2 : 0) + (hit.length > 1 ? 2 : 0),
        keyword.title,
        hit,
      ),
    );
  }
  return votes;
}

List<_CategoryVote> _matchCustomCategories(List<String> words, Set<int> used) {
  final votes = <_CategoryVote>[];
  for (final category in currentCatalog.custom) {
    final key = foldForMatching(category.name);
    if (key.isEmpty) continue;
    final hit = _matchKey(words, key, used);
    if (hit != null) {
      votes.add(_CategoryVote(category.id, 10, category.name, hit));
    }
  }
  return votes;
}

List<_CategoryVote> _matchHistory(
  List<QuickToken> tokens,
  Set<int> used,
  List<Transaction> history,
) {
  if (history.isEmpty) return const [];
  final votes = <_CategoryVote>[];
  // A legutóbbi tételek számítanak a legtöbbet.
  final recent = [...history]..sort((a, b) => b.date.compareTo(a.date));
  final seenTitles = <String>{};
  for (final transaction in recent.take(400)) {
    final titleKey = foldForMatching(transaction.title);
    if (titleKey.isEmpty || !seenTitles.add(titleKey)) continue;
    if (categoryById(transaction.categoryId) == null) continue;
    final parts = titleKey
        .split(' ')
        .where((part) => part.length >= 3 && !stopWords.contains(part))
        .toList();
    if (parts.isEmpty) continue;
    final words = [for (final token in tokens) token.folded];
    final hits = <int>{};
    for (final part in parts) {
      final hit = _matchKey(words, part, used);
      if (hit != null) hits.addAll(hit);
    }
    if (hits.isEmpty) continue;
    final complete = hits.length >= parts.length;
    votes.add(
      _CategoryVote(
        transaction.categoryId,
        complete ? 13 : 7,
        transaction.title,
        hits,
      ),
    );
  }
  return votes;
}

RecurringRule? _matchRule(
  List<String> words,
  Set<int> used,
  List<RecurringRule> rules,
  String categoryId,
  bool categoryKnown,
) {
  RecurringRule? best;
  var bestScore = 0;
  for (final rule in rules) {
    var score = 0;
    final titleParts = foldForMatching(
      rule.title,
    ).split(' ').where((part) => part.length >= 3 && !stopWords.contains(part));
    for (final part in titleParts) {
      if (_matchKey(words, part, used) != null) score += 5;
    }
    if (categoryKnown && rule.categoryId == categoryId) score += 3;
    if (score > bestScore) {
      bestScore = score;
      best = rule;
    }
  }
  return best;
}

(Frequency?, int) _frequencyOf(List<String> words) {
  for (final word in words) {
    switch (word) {
      case 'hetente' || 'heti' || 'hetenkent':
        return (Frequency.weekly, 1);
      case 'kethetente' || 'ketheti' || 'ketheteknt':
        return (Frequency.weekly, 2);
      case 'havonta' ||
          'havi' ||
          'honaponta' ||
          'havonkent' ||
          'ho' ||
          'havidij' ||
          'havidijas':
        return (Frequency.monthly, 1);
      case 'kethavonta' || 'kethavi':
        return (Frequency.monthly, 2);
      case 'negyedevente' || 'negyedeves' || 'negyedevi':
        return (Frequency.monthly, 3);
      case 'felevente' || 'feleves' || 'felevi':
        return (Frequency.monthly, 6);
      case 'evente' || 'eves' || 'evi' || 'evenkent':
        return (Frequency.yearly, 1);
    }
  }
  if (_hasPhrase(words, ['minden', 'het'])) return (Frequency.weekly, 1);
  if (_hasPhrase(words, ['minden', 'honap'])) return (Frequency.monthly, 1);
  if (_hasPhrase(words, ['minden', 'ev'])) return (Frequency.yearly, 1);
  return (null, 1);
}

/// A fel nem használt, értelmes szavakból képzett megnevezés.
String? _leftoverPhrase(List<QuickToken> tokens, Set<int> consumed) {
  final parts = <String>[];
  for (var i = 0; i < tokens.length && parts.length < 4; i++) {
    if (consumed.contains(i)) continue;
    final token = tokens[i];
    final word = token.folded;
    if (word.length < 2) continue;
    if (RegExp(r'^\d').hasMatch(word)) continue;
    if (stopWords.contains(word)) continue;
    parts.add(_trimAccusative(token.original));
  }
  if (parts.isEmpty) return null;
  final phrase = parts.join(' ');
  return phrase[0].toUpperCase() + phrase.substring(1);
}

/// Tárgyrag levágása a megjelenített szóról („telefontokot” → „telefontok”).
String _trimAccusative(String word) {
  final lower = word.toLowerCase();
  for (final suffix in ['ot', 'et', 'öt', 'at']) {
    if (lower.length > 6 && lower.endsWith(suffix)) {
      return word.substring(0, word.length - suffix.length);
    }
  }
  return word;
}
