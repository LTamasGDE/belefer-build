import '../accounts.dart';
import '../calendar.dart';
import '../categories.dart';
import '../model/belefer_model.dart';
import '../model/personal_knowledge.dart';
import '../model/personal_memory.dart';
import '../models.dart';
import '../recurring.dart';
import '../text_fold.dart';
import '../validation.dart';
import 'amount_parser.dart';
import 'date_parser.dart';
import 'lexicon.dart';
import 'money_flow.dart';
import 'quick_answers.dart';
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

  /// Saját számlák, bankok vagy készpénz közötti pénzmozgás (pl. „áttettem
  /// 50 ezret a megtakarításba”). Nem bevétel és nem kiadás.
  transfer,

  /// Kérdés (pl. „mennyit költöttem ebben a hónapban?”); a válasz az
  /// [QuickEntryResult.answer].
  question,
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
    this.accountId,
    this.transferFrom,
    this.transferTo,
    this.foreignAmount,
    this.currency,
    this.items = const [],
    this.guessed = const {},
    this.answer,
    this.accountFromHabit = false,
    this.amountFromHabit = false,
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

  /// A mondatban megnevezett számla („a közösről fizettem”); ha `null`, az
  /// alapértelmezett számla.
  final int? accountId;

  /// Átvezetésnél a forrás és a cél neve (számla, bank vagy „Készpénz”).
  final String? transferFrom;
  final String? transferTo;

  /// Devizás összeg („25 euró”): a forintösszeget a felület számolja ki
  /// az árfolyamból, addig az [amount] üres.
  final double? foreignAmount;
  final String? currency;

  /// Több tétel egy mondatban („Lidl 4500 és benzin 20 000”).
  final List<QuickEntryResult> items;

  /// A kérdések, amelyekre csak tippelni tudott (pl. a megnevezést egy
  /// elírástűrő egyezésből vagy a modell bizonytalan jóslatából vette).
  final Set<QuickQuestion> guessed;

  /// Kérdésre adott válasz.
  final String? answer;

  /// A számlát a szokásaidból vette (nem a szövegből).
  final bool accountFromHabit;

  /// Az összeget a szokásaidból vette („kávé” → a szokásos 950 Ft).
  final bool amountFromHabit;

  /// Több tétel van-e.
  bool get isMultiple => items.length > 1;

  bool get hasAmount => amount != null && amount! > 0;
  bool get hasWhat => title != null && title!.trim().isNotEmpty;

  /// Melyik kérdésre van már válasz.
  bool isAnswered(QuickQuestion question) => switch (question) {
    QuickQuestion.amount => hasAmount || currency != null,
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
    QuickIntent.transfer => const [],
    QuickIntent.question => const [],
    QuickIntent.changeRecurring => const [
      QuickQuestion.which,
      QuickQuestion.amount,
      QuickQuestion.when,
    ],
  };

  /// A még megválaszolandó kötelező kérdések.
  List<QuickQuestion> get missing => isMultiple
      ? [
          for (final question in QuickQuestion.values)
            if (items.any((item) => item.missing.contains(question))) question,
        ]
      : [
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

  /// Automatikusan elkönyvelhető-e (deviza esetén előbb át kell váltani).
  bool get isComplete =>
      missing.isEmpty &&
      (intent == QuickIntent.transfer ||
          intent == QuickIntent.question ||
          intent == QuickIntent.cancelRecurring ||
          isMultiple ||
          hasAmount);

  /// Biztos-e minden mező (ha nem, a felület ellenőrzést kér).
  bool get isSure => guessed.isEmpty && items.every((item) => item.isSure);

  /// Az eredmény forintösszeggel (pl. devizaátváltás után).
  QuickEntryResult withAmount(int value, {String? note}) => QuickEntryResult(
    intent: intent,
    type: type,
    typeExplicit: typeExplicit,
    amount: value,
    title: title,
    merchant: merchant,
    categoryId: categoryId,
    categoryGuessed: categoryGuessed,
    date: date,
    dateExplicit: dateExplicit,
    frequency: frequency,
    interval: interval,
    targetRule: targetRule,
    notes: [...notes, ?note],
    accountId: accountId,
    transferFrom: transferFrom,
    transferTo: transferTo,
    foreignAmount: foreignAmount,
    currency: currency,
    guessed: guessed,
    accountFromHabit: accountFromHabit,
  );

  /// Rögzítendő tétel (a [QuickIntent.record] szándékhoz).
  Transaction? toTransaction() {
    if (!hasAmount || !hasWhat) return null;
    return Transaction(
      type: type,
      title: title!,
      amount: amount!,
      categoryId: categoryId,
      date: date,
      accountId: accountId,
    );
  }

  /// Az összes rögzítendő tétel (több tételnél mind, egyébként egy).
  List<Transaction> toTransactions() => isMultiple
      ? [
          for (final item in items)
            if (item.intent == QuickIntent.record) ?item.toTransaction(),
        ]
      : [?toTransaction()];

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
    this.accounts = const [],
    this.lessons = const [],
  });

  final CalendarDay today;

  /// Korábbi tételek: a megnevezésekből tanulja a kategóriákat.
  final List<Transaction> history;

  /// Az ismétlődő tételek (lemondáshoz, módosításhoz).
  final List<RecurringRule> rules;

  /// A számlák (a „közösről fizettem” és az átvezetések felismeréséhez).
  final List<Account> accounts;

  /// A gyorsrögzítésből tanult leckék (beírt szavak → elmentett tétel).
  final List<Lesson> lessons;

  /// A tételekből tanult tudás (szokások, ismétlődések, leckék).
  PersonalKnowledge get knowledge => PersonalKnowledge.of(
    history,
    rules: rules,
    lessons: lessons,
    today: today,
  );
}

class _CategoryVote {
  _CategoryVote(
    this.categoryId,
    this.score,
    this.title,
    this.tokens, {
    this.fuzzy = false,
  });

  final String categoryId;
  final int score;
  final String? title;
  final Set<int> tokens;

  /// Csak elírástűréssel illeszkedett (pl. „kocsit” ≈ „kocsma”).
  final bool fuzzy;
}

/// A gyorsrögzítés értelmezője: a beírt mondatból tételt, ismétlődő tételt,
/// lemondást vagy módosítást készít.
///
/// A telefonon fut, internet nélkül. Tűri az elírásokat, a toldalékokat és a
/// szórend felcserélését, és a korábbi tételekből tanul.
///
/// A [simple] mód (az automatikus rögzítés értesítéseihez) csak egy tételt
/// értelmez: nem keres kérdést, több tételt, átvezetést és devizát, ezeket az
/// értesítés-feldolgozó maga kezeli.
QuickEntryResult interpretQuickEntry(
  String text,
  QuickEntryContext context, {
  bool simple = false,
}) {
  if (simple) return _interpretSingle(text, context, simple: true);
  final question = detectQuestion(text);
  if (question != null) {
    return QuickEntryResult(
      intent: QuickIntent.question,
      type: EntryType.expense,
      typeExplicit: false,
      amount: null,
      title: null,
      merchant: null,
      categoryId: CategoryCatalog.fallbackIdFor(EntryType.expense),
      categoryGuessed: true,
      date: context.today,
      dateExplicit: false,
      answer: answerQuestion(question, context),
    );
  }
  final whole = _interpretSingle(text, context);
  final segments = _splitItems(text);
  if (segments.length < 2) return whole;
  final parts = [
    for (final segment in segments) _interpretSingle(segment, context),
  ];
  final valid = parts.every(
    (part) =>
        part.hasAmount &&
        part.hasWhat &&
        part.intent == QuickIntent.record &&
        part.title != null,
  );
  if (!valid) return whole;
  // A közös dátum („tegnap Tesco 6000 meg tankolás 18 000”) mindegyikre.
  final dated = parts.where((part) => part.dateExplicit).toList();
  final items = [
    for (final part in parts)
      if (!part.dateExplicit && dated.length == 1)
        _withDate(part, dated.first.date)
      else
        part,
  ];
  return QuickEntryResult(
    intent: QuickIntent.record,
    type: items.first.type,
    typeExplicit: true,
    amount: items.fold<int>(0, (sum, item) => sum + item.amount!),
    title: items.map((item) => item.title).join(', '),
    merchant: null,
    categoryId: items.first.categoryId,
    categoryGuessed: false,
    date: items.first.date,
    dateExplicit: items.any((item) => item.dateExplicit),
    items: items,
  );
}

QuickEntryResult _withDate(QuickEntryResult part, CalendarDay date) =>
    QuickEntryResult(
      intent: part.intent,
      type: part.type,
      typeExplicit: part.typeExplicit,
      amount: part.amount,
      title: part.title,
      merchant: part.merchant,
      categoryId: part.categoryId,
      categoryGuessed: part.categoryGuessed,
      date: date,
      dateExplicit: true,
      notes: part.notes,
      accountId: part.accountId,
      guessed: part.guessed,
    );

/// Több tétel tagolása: „, ”, „; ”, „ és ”, „ meg ”, „ + ”. Csak akkor
/// bontunk, ha minden részben van szám (a „kenyér és tej 1200” egy tétel).
List<String> _splitItems(String text) {
  // „nem 4500, hanem 5400”: javítás, nem két tétel.
  if (RegExp(r'\bhanem\b', caseSensitive: false).hasMatch(text)) {
    return const [];
  }
  final parts = text
      .split(
        RegExp(r'\s*[,;]\s+|\s+(?:és|meg|plusz|\+)\s+', caseSensitive: false),
      )
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.length < 2) return const [];
  final hasNumber = RegExp(r'\d|ezer|millió|millio');
  if (!parts.every(hasNumber.hasMatch)) return const [];
  return parts;
}

QuickEntryResult _interpretSingle(
  String text,
  QuickEntryContext context, {
  bool simple = false,
}) {
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

  // Javítás: „nem 4500, hanem 5400” – a „nem” utáni szám érvénytelen.
  final but = folded.indexOf('hanem');
  if (but > 0) {
    final not = folded.lastIndexOf('nem', but);
    if (not >= 0) {
      for (var k = not + 1; k < but; k++) {
        blocked.add(k);
      }
    }
  }

  // Deviza: „25 euró” – a forintösszeget a felület számolja ki.
  final foreign = simple ? null : findForeignAmount(text, tokens);
  if (foreign != null) blocked.addAll(foreign.tokens);

  // Összeg.
  final candidates = findAmountCandidates(folded, blocked: blocked);
  final amountPick = pickAmount(candidates);
  final used = <int>{...blocked, ...?amountPick?.tokenIndexes};
  // Darabszám: „2 x 1500”, „két mozijegy 2900-ával”.
  final multiplied = _multiply(text, folded, amountPick);
  if (multiplied != null) used.addAll(multiplied.$2);
  var amount = multiplied?.$1 ?? amountPick?.value;
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
    } else if (word.length >= 7 &&
        !_lexiconWords.contains(word) &&
        moneyVerbPerson(word) == null) {
      if (_fuzzyIn(word, expenseWords)) {
        expenseScore += 2;
        verbTokens.add(i);
      } else if (_fuzzyIn(word, incomeWords)) {
        incomeScore += 2;
        verbTokens.add(i);
      }
    }
  }
  // Ki adott kinek: „visszaadta”, „átutalta”, „kifizettek” → nekem jött;
  // „kölcsönadtam”, „fizettem” → tőlem ment.
  for (var i = 0; i < folded.length; i++) {
    if (used.contains(i) || verbTokens.contains(i)) continue;
    switch (moneyVerbPerson(folded[i])) {
      case 1:
        expenseScore += 2;
        verbTokens.add(i);
      case 3:
        incomeScore += 4;
        verbTokens.add(i);
    }
  }
  // Számlák, bankok, készpénz és személyek.
  final endpoints = findEndpoints(tokens, context.accounts);
  final endpointTokens = {
    for (final e in endpoints)
      if (e.direction != FlowDirection.bare) ...e.tokens,
  };
  final people = [
    ...findPeople(
      tokens,
      isKnownName: (index) =>
          endpointTokens.contains(index) || _isMerchantWord(folded[index]),
    ),
  ];
  // Névvel kezdődő mondat, harmadik személyű igével: „Peti visszaadta”.
  if (people.isEmpty &&
      tokens.length > 1 &&
      tokens.first.original.length >= 3 &&
      tokens.first.original[0] != tokens.first.original[0].toLowerCase() &&
      !endpointTokens.contains(0) &&
      !_isMerchantWord(folded.first) &&
      !isCommonWord(folded.first) &&
      folded.skip(1).any((word) => moneyVerbPerson(word) == 3)) {
    people.add(const PersonMention(0, recipient: false));
  }
  final senders = people.where((person) => !person.recipient).toList();
  final personTokens = {
    for (final person in people)
      if (tokens[person.index].original[0] !=
          tokens[person.index].original[0].toLowerCase())
        person.index,
  };
  if (senders.isNotEmpty && expenseScore == 0 && incomeScore > 0) {
    incomeScore += 1;
  }
  // „Visszakaptam” és „kaptam” után a kategória szava erősebb a „fizettem”-nél.
  EntryType? explicitType;
  if (incomeScore > expenseScore) explicitType = EntryType.income;
  if (expenseScore > incomeScore) explicitType = EntryType.expense;

  // Kategória és kereskedő.
  final votes = <_CategoryVote>[];
  final merchantVote = _matchMerchant(folded, {
    ...used,
    ...endpointTokens,
    ...personTokens,
  }, verbTokens);
  if (merchantVote != null) votes.add(merchantVote.$1);
  votes.addAll(
    _matchKeywords(folded, {
      ...used,
      ...endpointTokens,
      ...personTokens,
    }, verbTokens),
  );
  votes.addAll(_matchCustomCategories(folded, used));
  // Leckék: amit korábban így írtál, és ahogy elmentetted. Ez a legerősebb
  // jel, mert a te döntésed volt.
  final knowledge = context.knowledge;
  final lessonHit = knowledge.lessons.isEmpty
      ? null
      : knowledge.lessonFor(folded);
  if (lessonHit != null) {
    votes.add(
      _CategoryVote(
        lessonHit.$1.categoryId,
        16,
        lessonHit.$1.title,
        lessonHit.$2,
      ),
    );
  }
  votes.addAll(_matchHistory(tokens, used, context.history));
  // A modell személyes része: a korábbi megnevezésekhez hasonló szavak.
  if (context.history.isNotEmpty) {
    final leftover = [
      for (var i = 0; i < folded.length; i++)
        if (!used.contains(i) && !verbTokens.contains(i))
          RegExp(r'^\d').hasMatch(folded[i]) ? '#' : folded[i],
    ];
    final recalled = PersonalMemory.of(
      context.history,
    ).recall(leftover, threshold: 0.55);
    if (recalled != null) {
      votes.add(
        _CategoryVote(
          recalled.categoryId,
          8 + ((recalled.similarity - 0.55) * 10).round(),
          recalled.title,
          const {},
        ),
      );
    }
  }

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
  // A saját modell: ha a szótár és a korábbi tételek nem döntöttek, vagy
  // csak egy elírástűrő egyezés döntött volna, amivel a modell határozottan
  // nem ért egyet („elvittem a kocsit” ≠ kocsma).
  final model = currentModel;
  String? modelCategoryId;
  var modelConfidence = 0.0;
  if (model != null && (best == null || best.fuzzy)) {
    final allowed = {
      for (final category in [...expenseCategories, ...incomeCategories])
        if (explicitType == null || category.type == explicitType) category.id,
    };
    final prediction = model.classify('category', text).restrictedTo(allowed);
    if (best == null) {
      if (prediction.confidence >= 0.45) {
        modelCategoryId = prediction.best;
        modelConfidence = prediction.confidence;
      }
    } else if (prediction.confidence >= 0.6 &&
        prediction.probabilityOf(best.categoryId) < 0.1) {
      best = null;
      modelCategoryId = prediction.best;
      modelConfidence = prediction.confidence;
    }
  }
  final type =
      explicitType ??
      (best != null
          ? categoryById(best.categoryId)!.type
          : modelCategoryId != null
          ? categoryById(modelCategoryId)!.type
          : EntryType.expense);
  var categoryId =
      best?.categoryId ??
      modelCategoryId ??
      CategoryCatalog.fallbackIdFor(type);
  var categoryKnown = best != null || modelCategoryId != null;
  // Rokontól, ismerőstől kapott pénz: ajándék („kaptam anyától”, „anya
  // utalt”), ha más kategória nem derült ki.
  if (type == EntryType.income &&
      best == null &&
      senders.isNotEmpty &&
      !folded.any((w) => w.startsWith('vissza') || w.startsWith('kolcson'))) {
    categoryId = 'gift_income';
    categoryKnown = true;
    modelCategoryId = null;
  }

  // Szándék véglegesítése és célszabály.
  var intent = QuickIntent.record;
  RecurringRule? target;
  if (cancel) {
    intent = QuickIntent.cancelRecurring;
    target = _matchRule(folded, used, context.rules, categoryId, categoryKnown);
  } else if (change && amountPick != null) {
    target = _matchRule(folded, used, context.rules, categoryId, categoryKnown);
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
  // A saját modell a szótárban nem szereplő megfogalmazásokat is felismeri
  // („nem kell már a Disney”, „leiratkoztam a Spotify-ról”).
  if (model != null && intent == QuickIntent.record) {
    final prediction = model.classify('intent', text);
    final confidence = prediction.confidence;
    switch (prediction.best) {
      case 'cancel_recurring' when confidence >= 0.7:
        final candidate = _matchRule(folded, used, context.rules, '', false);
        if (candidate != null) {
          intent = QuickIntent.cancelRecurring;
          target = candidate;
        }
      case 'change_recurring' when confidence >= 0.75 && amountPick != null:
        final candidate = _matchRule(folded, used, context.rules, '', false);
        if (candidate != null) {
          intent = QuickIntent.changeRecurring;
          target = candidate;
        }
      case 'create_recurring' when confidence >= 0.8 && amountPick != null:
        intent = QuickIntent.createRecurring;
    }
  }

  // Személynek adott vagy személytől kapott pénz: tudjuk, mi történt, akkor
  // is, ha kategória nem derült ki („átutaltam anyának”, „Peti visszaadta”).
  String? personTitle;
  final loan = folded.any(
    (w) => w.startsWith('kolcson') || w.startsWith('tartoz'),
  );
  final weakCategory =
      !categoryKnown ||
      (best == null && modelCategoryId != null && modelConfidence < 0.7);
  if (people.isNotEmpty && (weakCategory || loan)) {
    categoryKnown = true;
    modelCategoryId = null;
    categoryId = CategoryCatalog.fallbackIdFor(type);
    final name = trimCaseSuffix(tokens[people.first.index].original);
    final display = name.isEmpty
        ? name
        : name[0].toUpperCase() + name.substring(1);
    personTitle = loan
        ? (type == EntryType.income
              ? 'Kölcsön vissza: $display'
              : 'Kölcsön: $display')
        : display;
  } else if (loan) {
    categoryKnown = true;
    modelCategoryId = null;
    categoryId = CategoryCatalog.fallbackIdFor(type);
    personTitle = type == EntryType.income ? 'Kölcsön vissza' : 'Kölcsön';
  }

  // Saját számlák, bankok, készpénz közötti mozgás: átvezetés (a „havi”
  // szó ilyenkor csak a szokást jelzi: „betettem a havi 60 ezret”).
  if (!simple &&
      (intent == QuickIntent.record ||
          (intent == QuickIntent.createRecurring && !createStrong))) {
    final purchase =
        best != null &&
        !best.fuzzy &&
        best.tokens.isNotEmpty &&
        categoryById(best.categoryId)?.type == EntryType.expense &&
        best.score >= 7;
    final savings = context.accounts.where(
      (account) => account.kind == AccountKind.savings,
    );
    var transfer = detectTransfer(
      tokens,
      endpoints,
      personRecipient: people.any((person) => person.recipient),
      purchase: purchase,
      otherContent:
          (explicitType != null &&
              !verbTokens.every(
                (i) => const {
                  'ment',
                  'elment',
                  'el',
                  'utaltam',
                  'atutaltam',
                  'kuldtem',
                  'atkuldtem',
                }.contains(folded[i]),
              )) ||
          (best != null && !best.fuzzy && best.tokens.isNotEmpty),
      savingsName: savings.isEmpty ? null : savings.first.name,
    );
    // A saját modell a szabályokból kimaradó megfogalmazásokat is felismeri
    // („átpakoltam a Revolutra 20e-t”); csak ha számla is szerepel.
    if (transfer == null &&
        model != null &&
        !purchase &&
        explicitType == null &&
        (best == null || best.fuzzy) &&
        endpoints.any((e) => e.direction != FlowDirection.bare) &&
        !people.any((person) => person.recipient)) {
      final prediction = model.classify('intent', text);
      if (prediction.best == 'transfer' && prediction.confidence >= 0.85) {
        FlowEndpoint? pick(FlowDirection direction) {
          for (final endpoint in endpoints) {
            if (endpoint.direction == direction) return endpoint;
          }
          return null;
        }

        transfer = TransferInfo(
          from: pick(FlowDirection.from),
          to: pick(FlowDirection.to) ?? pick(FlowDirection.object),
          tokens: const {},
        );
      }
    }
    if (transfer != null) {
      return QuickEntryResult(
        intent: QuickIntent.transfer,
        type: EntryType.expense,
        typeExplicit: true,
        amount: amount,
        title: 'Átvezetés',
        merchant: null,
        categoryId: CategoryCatalog.fallbackIdFor(EntryType.expense),
        categoryGuessed: false,
        date: dateMatch?.day ?? today,
        dateExplicit: dateMatch != null,
        notes: notes,
        transferFrom: transfer.from?.name,
        transferTo: transfer.to?.name,
        foreignAmount: foreign?.amount,
        currency: foreign?.currency,
      );
    }
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
  title ??=
      personTitle ??
      best?.title ??
      _modelTitle(model, tokens, consumed) ??
      _leftoverPhrase(tokens, consumed);
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

  // A mondatban megnevezett számla („a közösről”, „közös kártyával”).
  int? accountId;
  for (final direction in const [FlowDirection.via, FlowDirection.from]) {
    for (final endpoint in endpoints) {
      if (endpoint.direction == direction && endpoint.accountId != null) {
        accountId ??= endpoint.accountId;
      }
    }
  }
  // Szokások: ha nem írtad, a szokásos összeg és számla („kávé” → 950 Ft,
  // „Lidl” → Közös). Kérdezés helyett tipp, amit felülírhatsz.
  final habit = title == null
      ? null
      : knowledge.habitFor(title) ??
            (merchant == null ? null : knowledge.habitFor(merchant));
  var amountFromHabit = false;
  if (amount == null &&
      foreign == null &&
      (intent == QuickIntent.record || intent == QuickIntent.createRecurring) &&
      habit?.usualAmount != null &&
      (habit!.categoryId == categoryId || !categoryKnown)) {
    amount = habit.usualAmount;
    amountFromHabit = true;
  }
  var accountFromHabit = false;
  if (accountId == null &&
      (intent == QuickIntent.record || intent == QuickIntent.createRecurring)) {
    final learned = lessonHit?.$1.accountId ?? habit?.usualAccountId;
    if (learned != null && context.accounts.any((a) => a.id == learned)) {
      accountId = learned;
      accountFromHabit = true;
    }
  }
  final merchantFuzzy =
      merchantVote != null && merchant != null && merchantVote.$1.fuzzy;
  final guessed = <QuickQuestion>{
    if (amountPick != null && notes.any((note) => note.startsWith('Több')))
      QuickQuestion.amount,
    if ((intent == QuickIntent.record ||
            intent == QuickIntent.createRecurring) &&
        (!categoryKnown ||
            merchantFuzzy ||
            (best?.fuzzy ?? false) ||
            (best == null && modelCategoryId != null && modelConfidence < 0.7)))
      QuickQuestion.what,
  };

  return QuickEntryResult(
    intent: intent,
    type: target?.type ?? type,
    typeExplicit: explicitType != null || best != null || target != null,
    amount: amount,
    title: title,
    merchant: merchant,
    categoryId: target?.categoryId ?? categoryId,
    categoryGuessed: !categoryKnown && target == null,
    date: date,
    dateExplicit: dateMatch != null,
    frequency: intent == QuickIntent.createRecurring
        ? (frequency ?? Frequency.monthly)
        : null,
    interval: interval,
    targetRule: target,
    notes: notes,
    accountId: accountId,
    foreignAmount: foreign?.amount,
    currency: foreign?.currency,
    guessed: guessed,
    accountFromHabit: accountFromHabit,
    amountFromHabit: amountFromHabit,
  );
}

/// Ismert kereskedő neve-e (a nagybetűs szó ilyenkor nem személynév).
bool _isMerchantWord(String word) => _merchantWords.any(word.startsWith);

final List<String> _merchantWords = [
  for (final merchant in merchants)
    for (final key in merchant.keys)
      if (!key.contains(' ') && key.length >= 3) key,
];

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
  bool merchant = false,
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
      final word = words[i];
      if (word == joined ||
          (word.startsWith(joined) && fuzzyWordMatch(word, joined)) ||
          (joined.length >= 7 &&
              word.length >= joined.length - 1 &&
              !isCommonWord(word) &&
              editDistance(word, joined, maxDistance: 1) <= 1)) {
        return {i};
      }
    }
    return null;
  }
  for (var i = 0; i < words.length; i++) {
    if (skip.contains(i)) continue;
    final word = words[i];
    if (RegExp(r'^\d').hasMatch(word)) continue;
    // Névelők, kötőszavak nem kulcsszavak („egy” ≠ „jegy”).
    if (stopWords.contains(word) && word != key) continue;
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
    if (word.startsWith(key)) {
      if (fuzzyWordMatch(word, key)) return {i};
      continue;
    }
    // Elírás csak ismeretlen szónál: a „számláról” nem „Szamos”, a „kocsit”
    // nem „kocsma”. Kereskedőnél legfeljebb egy betű eltérés.
    if (isCommonWord(word)) continue;
    if (merchant) {
      // Rövid névnél csak két szomszédos betű felcserélése („lild” → Lidl).
      if (key.length < 5) {
        if (key.length == 4 && _isTransposition(word, key)) return {i};
        continue;
      }
      if (candidateStems(word).any(
        (stem) =>
            stem.length >= 5 && editDistance(stem, key, maxDistance: 1) <= 1,
      )) {
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
      final hit = _matchKey(words, key, skip, merchant: true);
      if (hit == null) continue;
      final exact =
          hit.length > 1 ||
          words[hit.first] == key ||
          words[hit.first].startsWith(key);
      final score = exact ? 12 + key.length ~/ 4 : 9;
      if (best == null || score > best.$1.score) {
        best = (
          _CategoryVote(
            merchant.categoryId,
            score,
            merchant.name,
            hit,
            fuzzy: !exact,
          ),
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
    // Helyhatározó („a kocsmában”, „a pékségnél”): a hely dönt a termék
    // („sör”) helyett.
    final word = words[hit.last];
    final place =
        word.length > keyword.key.length + 1 &&
        word.startsWith(keyword.key) &&
        const [
          'ban',
          'ben',
          'nal',
          'nel',
          'ba',
          'be',
          'bol',
          'bol',
        ].any(word.endsWith);
    votes.add(
      _CategoryVote(
        keyword.categoryId,
        keyword.weight +
            (exact ? 2 : 0) +
            (hit.length > 1 ? 2 : 0) +
            (place ? 3 : 0),
        keyword.title,
        hit,
        fuzzy: hit.length == 1 && !words[hit.first].startsWith(keyword.key),
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

/// A modell által a megnevezéshez sorolt szavak (legfeljebb három).
String? _modelTitle(
  BeleferModel? model,
  List<QuickToken> tokens,
  Set<int> consumed,
) {
  if (model == null || tokens.isEmpty) return null;
  final probabilities = model.titleProbabilities([
    for (final token in tokens) token.folded,
  ]);
  final parts = <String>[];
  for (var i = 0; i < tokens.length && parts.length < 3; i++) {
    if (consumed.contains(i)) continue;
    final word = tokens[i].folded;
    if (word.length < 2 || RegExp(r'^\d').hasMatch(word)) continue;
    if (stopWords.contains(word)) continue;
    if (probabilities[i] >= 0.5) parts.add(tokens[i].original);
  }
  if (parts.isEmpty) return null;
  final phrase = parts.map(trimCaseSuffix).join(' ');
  return phrase[0].toUpperCase() + phrase.substring(1);
}

const List<String> _caseSuffixes = [
  'ban', 'ben', 'ból', 'ből', 'nál', 'nél', 'tól', 'től', 'ról', 'ről', //
  'ért', 'hoz', 'hez', 'höz',
];
const List<String> _shortCaseSuffixes = ['ra', 're', 'ba', 'be', 'nak', 'nek'];
final RegExp _shortVowelEnd = RegExp('[aeiouöü]\$');

/// Hosszú „é”-re végződő szavak (ezeknél a rag előtti „é” nem nyúlás).
const Set<String> _longEndings = {
  'kávé', 'kanapé', 'tévé', 'püré', 'zselé', 'kávézó', 'bébé', 'filé', //
  'kupé', 'karaoké', 'paté', 'szufflé', 'tupé',
};

/// Ragok levágása a megjelenített szóról: „pékségben” → „pékség”,
/// „pizzára” → „pizza”, „Netflixet” → „Netflix”.
String trimCaseSuffix(String word) {
  final lower = word.toLowerCase();
  String restore(String stem) {
    if (stem.endsWith('á')) return '${stem.substring(0, stem.length - 1)}a';
    if (stem.endsWith('é') && !_longEndings.contains(stem.toLowerCase())) {
      return '${stem.substring(0, stem.length - 1)}e';
    }
    return stem;
  }

  for (final suffix in _caseSuffixes) {
    if (lower.length - suffix.length >= 3 && lower.endsWith(suffix)) {
      return restore(word.substring(0, word.length - suffix.length));
    }
  }
  for (final suffix in _shortCaseSuffixes) {
    if (lower.length - suffix.length >= 4 && lower.endsWith(suffix)) {
      final stem = word.substring(0, word.length - suffix.length);
      // „kamera” marad: rövid magánhangzó után ez nem rag.
      if (_shortVowelEnd.hasMatch(stem.toLowerCase())) continue;
      return restore(stem);
    }
  }
  // „kanapét” → „kanapé”, „pizzát” → „pizza” (a „kabát” marad).
  if (lower.length >= 6 && (lower.endsWith('át') || lower.endsWith('ét'))) {
    return restore(word.substring(0, word.length - 1));
  }
  return _trimAccusative(word);
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

const Map<String, int> _countWords = {
  'ket': 2,
  'ketto': 2,
  'harom': 3,
  'negy': 4,
  'ot': 5,
  'hat': 6,
  'het': 7,
  'nyolc': 8,
  'kilenc': 9,
  'tiz': 10,
};

/// Darabszám és egységár szorzata: „2 x 1500”, „2x1500”, „3 * 990”,
/// „két mozijegy 2900-ával”, „4 darab, darabja 750”. Visszaad: (összeg,
/// a darabszám tokenjei).
(int, Set<int>)? _multiply(
  String text,
  List<String> words,
  AmountCandidate? pick,
) {
  if (pick == null) return null;
  final first = pick.tokenIndexes.reduce((a, b) => a < b ? a : b);
  final last = pick.tokenIndexes.reduce((a, b) => a > b ? a : b);
  int? small(String word) {
    final match = RegExp(r'^(\d{1,2})(x?)$').firstMatch(word);
    if (match != null) return int.parse(match.group(1)!);
    return _countWords[word];
  }

  // „2 x 1500”, „2x 1500”, „2 * 1500”, „2×1500”.
  if (first >= 1) {
    final before = words[first - 1];
    final glued = RegExp(r'^(\d{1,2})x$').firstMatch(before);
    if (glued != null) {
      final count = int.parse(glued.group(1)!);
      if (count >= 2) return (count * pick.value, {first - 1});
    }
    if (first >= 2 && before == 'x') {
      final count = small(words[first - 2]);
      if (count != null && count >= 2) {
        return (count * pick.value, {first - 2, first - 1});
      }
    }
    final count = small(before);
    if (count != null &&
        count >= 2 &&
        RegExp(r'\d\s*[*×]\s*\d').hasMatch(text)) {
      return (count * pick.value, {first - 1});
    }
  }
  // Egységár: „2900-ával”, „darabja 750”, „darabonként”, „egyenként”.
  final perPiece =
      (last + 1 < words.length &&
          const {
            'aval',
            'evel',
            'javal',
            'jevel',
            'val',
            'vel',
          }.contains(words[last + 1])) ||
      words.any(
        (w) =>
            w == 'darabja' ||
            w.startsWith('darabonkent') ||
            w == 'egyenkent' ||
            w == 'per',
      );
  if (!perPiece) return null;
  for (var i = 0; i < words.length; i++) {
    if (pick.tokenIndexes.contains(i)) continue;
    final count = small(words[i]);
    if (count == null || count < 2) continue;
    // A darabszám mögött darab vagy egy főnév áll, nem pénznem.
    return (count * pick.value, {i});
  }
  return null;
}

/// Két szomszédos betű felcserélése-e (és semmi más).
bool _isTransposition(String word, String key) {
  if (word.length != key.length) return false;
  final diffs = [
    for (var i = 0; i < word.length; i++)
      if (word[i] != key[i]) i,
  ];
  return diffs.length == 2 &&
      diffs[1] == diffs[0] + 1 &&
      word[diffs[0]] == key[diffs[1]] &&
      word[diffs[1]] == key[diffs[0]];
}
