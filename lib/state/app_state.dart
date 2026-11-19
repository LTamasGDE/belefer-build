import 'dart:async';

import 'package:flutter/foundation.dart' hide Category;
import 'package:http/http.dart' as http;

import '../data/local_store.dart';
import '../domain/accounts.dart';
import '../domain/ai/ai_prompt.dart';
import '../domain/ai/ai_settings.dart';
import '../domain/capture/captured_event.dart';
import '../domain/calendar.dart';
import '../domain/categories.dart';
import '../domain/demo_data.dart';
import '../domain/forecast.dart';
import '../domain/formatting.dart';
import '../domain/models.dart';
import '../domain/monthly_summary.dart';
import '../domain/quick_entry/interpreter.dart';
import '../domain/recurring.dart';
import '../domain/search.dart';
import '../services/ai_client.dart';
import '../services/ai_interpreter.dart';
import '../services/capture_processor.dart';
import '../services/exchange_rates.dart';
import '../services/platform_services.dart';

/// Az alkalmazás egyetlen állapotforrása.
///
/// Minden képernyő ugyanebből olvas, ezért mentés, szerkesztés és törlés
/// után a lista és az áttekintés ugyanazt a friss adatot mutatja.
class AppState extends ChangeNotifier {
  AppState({
    required LocalStore store,
    required this.versionLabel,
    CalendarDay Function()? today,
    DateTime Function()? now,
    ReminderScheduler reminders = const NoopReminderScheduler(),
    WidgetPublisher widget = const NoopWidgetPublisher(),
    CaptureBridge capture = const NoCaptureBridge(),
    ExchangeRates rates = const NoExchangeRates(),
    http.Client? httpClient,
  }) : _store = store,
       _now = now ?? DateTime.now,
       _reminders = reminders,
       _widget = widget,
       _capture = capture,
       _rates = rates,
       _httpClient = httpClient {
    _today = today ?? () => CalendarDay.fromDateTime(_now());
    _selectedMonth = YearMonth.of(_today());
  }

  final LocalStore _store;
  late final CalendarDay Function() _today;
  final DateTime Function() _now;
  final ReminderScheduler _reminders;
  final WidgetPublisher _widget;
  final CaptureBridge _capture;
  final ExchangeRates _rates;
  final http.Client? _httpClient;

  static const String _aiKey = 'ai';
  static const String _captureKey = 'capture';
  static const String _captureLogKey = 'captureLog';

  AiSettings _aiSettings = const AiSettings();
  AiClient? _aiClient;
  bool _revolutCapture = false;
  List<CaptureLogEntry> _captureLog = const [];
  Future<CaptureReport?>? _processing;

  /// Az automatikus rögzítés visszajelzései (a felület mutatja meg).
  final ValueNotifier<CaptureReport?> captureReports = ValueNotifier(null);

  /// Az alkalmazás verziója a build metaadataiból, pl. `0.3.0 (3)`.
  final String versionLabel;

  List<Transaction> _transactions = const [];
  List<EntryTemplate> _templates = const [];
  List<RecurringRule> _rules = const [];
  List<Category> _customCategories = const [];
  List<Account> _accounts = const [];
  int? _selectedAccountId;
  ReminderDefaults _reminderDefaults = const ReminderDefaults();
  bool _darkMode = false;
  bool _tourSeen = false;
  late YearMonth _selectedMonth;

  /// Bemutató mód: a körbevezetés alatt a felhasználó adatai helyett
  /// (ha még nincs adata) a bemutató adatok látszanak. Semmi sem mentődik.
  bool _demo = false;
  _Snapshot? _beforeDemo;
  bool _tourActive = false;

  CalendarDay today() => _today();

  List<Transaction> get transactions => _transactions;
  List<EntryTemplate> get templates => _templates;
  List<RecurringRule> get rules => _rules;
  List<Category> get customCategories => _customCategories;
  List<Account> get accounts => _accounts;

  /// A kiválasztott számla az Áttekintésen és a Tételeknél (`null` = mind).
  int? get selectedAccountId => _selectedAccountId;

  Account? get defaultAccount {
    for (final account in _accounts) {
      if (account.isDefault) return account;
    }
    return null;
  }

  Account? accountById(int? id) {
    if (id == null) return null;
    for (final account in _accounts) {
      if (account.id == id) return account;
    }
    return null;
  }

  /// A tétel számlája; számla nélkül az alapértelmezett számla.
  int? effectiveAccountId(int? accountId) =>
      accountById(accountId)?.id ?? defaultAccount?.id;

  bool _inSelectedAccount(int? accountId) =>
      _selectedAccountId == null ||
      effectiveAccountId(accountId) == _selectedAccountId;

  /// A kiválasztott számla tételei (vagy mind).
  List<Transaction> get _visibleTransactions => _selectedAccountId == null
      ? _transactions
      : [
          for (final transaction in _transactions)
            if (_inSelectedAccount(transaction.accountId)) transaction,
        ];

  void selectAccount(int? id) {
    final next = accountById(id)?.id;
    if (next == _selectedAccountId) return;
    _selectedAccountId = next;
    notifyListeners();
  }

  ReminderDefaults get reminderDefaults => _reminderDefaults;
  bool get darkMode => _darkMode;
  bool get tourSeen => _tourSeen;
  bool get isDemo => _demo;

  /// Fut-e éppen a körbevezetés.
  bool get tourActive => _tourActive;

  /// Van-e a felhasználónak saját adata.
  bool get hasUserData =>
      (_demo ? _beforeDemo!.transactions : _transactions).isNotEmpty ||
      (_demo ? _beforeDemo!.templates : _templates).isNotEmpty ||
      (_demo ? _beforeDemo!.rules : _rules).isNotEmpty;

  /// Az Áttekintés és a Tételek képernyő közös hónapja.
  YearMonth get selectedMonth => _selectedMonth;

  bool get isCurrentMonth => _selectedMonth == YearMonth.of(_today());

  MonthlySummary get summary =>
      summarizeMonth(_visibleTransactions, _selectedMonth);

  /// Előrejelzés a kiválasztott hónapra (múltbeli hónapra `null`).
  Forecast? get forecast => forecastMonth(
    transactions: _visibleTransactions,
    rules: [
      for (final rule in activeRules)
        if (_inSelectedAccount(rule.accountId)) rule,
    ],
    month: _selectedMonth,
    today: _today(),
  );

  List<Transaction> transactionsOfSelectedMonth({EntryType? type}) =>
      transactionsInMonth(_visibleTransactions, _selectedMonth, type: type);

  /// Keresés az összes tétel között.
  List<Transaction> search(String query) =>
      searchTransactions(_transactions, query);

  /// Sablonok név szerint, opcionálisan típus szerint szűrve.
  List<EntryTemplate> templatesOf(EntryType? type) {
    final result = [
      for (final template in _templates)
        if (type == null || template.type == type) template,
    ];
    result.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    return result;
  }

  /// A még nem lezárt ismétlődő tételek.
  List<RecurringRule> get activeRules {
    final today = _today();
    return [
      for (final rule in _rules)
        if (!rule.isEndedOn(today)) rule,
    ];
  }

  /// A lezárt (lemondott) ismétlődő tételek.
  List<RecurringRule> get endedRules {
    final today = _today();
    return [
      for (final rule in _rules)
        if (rule.isEndedOn(today)) rule,
    ];
  }

  /// Jóváhagyásra váró esedékességek: szabályonként a legkorábbi.
  List<PendingOccurrence> get pending {
    final today = _today();
    final result = <PendingOccurrence>[];
    for (final rule in _rules) {
      if (rule.autoBook) continue;
      final due = rule.dueOccurrences(today);
      if (due.isNotEmpty) {
        result.add(PendingOccurrence(rule: rule, date: due.first));
      }
    }
    result.sort((a, b) => a.date.compareTo(b.date));
    return result;
  }

  /// A gyorsrögzítés értelmezőjének adatai (a tanuláshoz).
  QuickEntryContext get quickEntryContext => QuickEntryContext(
    today: _today(),
    history: _transactions,
    rules: activeRules,
  );

  Future<void> load() async {
    _transactions = await _store.loadTransactions();
    _templates = await _store.loadTemplates();
    _rules = await _store.loadRecurring();
    _customCategories = await _store.loadCategories();
    _accounts = await _store.loadAccounts();
    _aiSettings = AiSettings.fromMap(await _store.readSettingMap(_aiKey));
    _aiClient = null;
    _revolutCapture =
        (await _store.readSettingMap(_captureKey))?['revolut'] == true;
    _captureLog = [
      for (final entry in await _store.readSettingList(_captureLogKey))
        if (entry is Map) CaptureLogEntry.fromMap(entry),
    ];
    _reminderDefaults = await _store.readReminderDefaults();
    _darkMode = await _store.readDarkMode();
    _tourSeen = await _store.readTourSeen();
    _applyCatalog();
    await _bookDueRecurring();
    notifyListeners();
    _afterDataChange();
    unawaited(processCaptures());
  }

  /// Az alkalmazás előtérbe kerülésekor: ha közben új nap kezdődött, az
  /// esedékes ismétlődő tételek elkönyvelése.
  Future<void> refreshForToday() async {
    if (_demo) return;
    final booked = await _bookDueRecurring();
    if (booked) notifyListeners();
    _afterDataChange();
    await processCaptures();
  }

  void showMonth(YearMonth month) {
    if (month == _selectedMonth) return;
    _selectedMonth = month;
    notifyListeners();
  }

  void showPreviousMonth() => showMonth(_selectedMonth.previous);

  void showNextMonth() => showMonth(_selectedMonth.next);

  void showCurrentMonth() => showMonth(YearMonth.of(_today()));

  // --- Tételek ---

  /// Új tétel felvétele vagy meglévő módosítása.
  Future<Transaction> saveTransaction(Transaction transaction) async {
    if (_demo) return transaction;
    final saved = await _store.saveTransaction(transaction);
    _transactions = _replace(_transactions, saved, (t) => t.id);
    _changed();
    return saved;
  }

  Future<void> deleteTransaction(int id) async {
    if (_demo) return;
    await _store.deleteTransaction(id);
    _transactions = [
      for (final existing in _transactions)
        if (existing.id != id) existing,
    ];
    _changed();
  }

  // --- Sablonok ---

  Future<EntryTemplate> saveTemplate(EntryTemplate template) async {
    if (_demo) return template;
    final saved = await _store.saveTemplate(template);
    _templates = _replace(_templates, saved, (t) => t.id);
    _changed();
    return saved;
  }

  Future<void> deleteTemplate(int id) async {
    if (_demo) return;
    await _store.deleteTemplate(id);
    _templates = [
      for (final existing in _templates)
        if (existing.id != id) existing,
    ];
    _changed();
  }

  // --- Ismétlődő tételek ---

  /// Ismétlődő tétel mentése.
  ///
  /// Új tételnél a múltbeli esedékességek csak [bookPast] esetén kerülnek
  /// rögzítésre; a mai esedékesség automatikus könyvelésnél azonnal.
  Future<RecurringRule> saveRule(
    RecurringRule rule, {
    bool bookPast = false,
  }) async {
    if (_demo) return rule;
    var toSave = rule;
    final today = _today();
    if ((rule.id == null || rule.handledThrough == null) &&
        !bookPast &&
        rule.startDate.compareTo(today) < 0) {
      toSave = rule.copyWith(
        handledThrough: CalendarDay(today.year, today.month, today.day - 1),
      );
    }
    final saved = await _store.saveRecurring(toSave);
    _rules = _replace(_rules, saved, (r) => r.id);
    await _bookDueRecurring();
    if (saved.reminder.enabled && _reminderDefaults.enabled) {
      await _reminders.ensurePermission();
    }
    _changed();
    return _rules.firstWhere((r) => r.id == saved.id);
  }

  /// Az ismétlődő tétel lezárása (lemondás): mától (vagy a [day] utántól)
  /// nincs több esedékesség. A korábban rögzített tételek megmaradnak.
  Future<void> endRule(RecurringRule rule, {CalendarDay? day}) async {
    if (_demo) return;
    final today = _today();
    final saved = await _store.saveRecurring(
      rule.copyWith(
        endDate: day ?? CalendarDay(today.year, today.month, today.day - 1),
      ),
    );
    _rules = _replace(_rules, saved, (r) => r.id);
    _changed();
  }

  /// Lezárt ismétlődő tétel újraindítása.
  Future<void> resumeRule(RecurringRule rule) async {
    if (_demo) return;
    final today = _today();
    final saved = await _store.saveRecurring(
      rule.copyWith(
        clearEndDate: true,
        handledThrough: CalendarDay(today.year, today.month, today.day - 1),
      ),
    );
    _rules = _replace(_rules, saved, (r) => r.id);
    await _bookDueRecurring();
    _changed();
  }

  /// Az összeg módosítása a [from] naptól (a korábbi tételek változatlanok).
  Future<void> changeRuleAmount(
    RecurringRule rule, {
    required int amount,
    required CalendarDay from,
  }) async {
    if (_demo) return;
    final changes = [
      for (final change in rule.amountChanges)
        if (change.from != from) change,
      AmountChange(from: from, amount: amount),
    ]..sort((a, b) => a.from.compareTo(b.from));
    final saved = await _store.saveRecurring(
      rule.copyWith(amountChanges: changes),
    );
    _rules = _replace(_rules, saved, (r) => r.id);
    _changed();
  }

  /// Egy korábbi állapot visszaállítása (visszavonáshoz), könyvelés nélkül.
  Future<void> restoreRule(RecurringRule rule) async {
    if (_demo) return;
    final saved = await _store.saveRecurring(rule);
    _rules = _replace(_rules, saved, (r) => r.id);
    _changed();
  }

  Future<void> deleteRule(int id) async {
    if (_demo) return;
    await _store.deleteRecurring(id);
    _rules = [
      for (final rule in _rules)
        if (rule.id != id) rule,
    ];
    _changed();
  }

  /// Jóváhagyásra váró esedékesség rögzítése (az összeg módosítható).
  Future<Transaction?> bookPending(
    PendingOccurrence occurrence, {
    int? amount,
  }) async {
    if (_demo) return null;
    var transaction = occurrence.rule.transactionFor(occurrence.date);
    if (amount != null && amount > 0) {
      transaction = Transaction(
        type: transaction.type,
        title: transaction.title,
        amount: amount,
        categoryId: transaction.categoryId,
        date: transaction.date,
        note: transaction.note,
        recurringId: transaction.recurringId,
        accountId: transaction.accountId,
      );
    }
    final saved = await _store.saveTransaction(transaction);
    _transactions = [..._transactions, saved];
    await _markHandled(occurrence.rule, occurrence.date);
    _changed();
    return saved;
  }

  /// Esedékesség kihagyása (nem rögzül tétel).
  Future<void> skipPending(PendingOccurrence occurrence) async {
    if (_demo) return;
    await _markHandled(occurrence.rule, occurrence.date);
    _changed();
  }

  Future<void> _markHandled(RecurringRule rule, CalendarDay day) async {
    final current = _rules.firstWhere((r) => r.id == rule.id);
    final saved = await _store.saveRecurring(
      current.copyWith(handledThrough: day),
    );
    _rules = _replace(_rules, saved, (r) => r.id);
  }

  /// Az automatikusan könyvelendő, esedékes ismétlődő tételek rögzítése.
  /// Igaz, ha történt könyvelés.
  Future<bool> _bookDueRecurring() async {
    if (_demo) return false;
    final today = _today();
    var booked = false;
    for (final rule in [..._rules]) {
      if (!rule.autoBook) continue;
      final due = rule.dueOccurrences(today);
      if (due.isEmpty) continue;
      for (final day in due) {
        final saved = await _store.saveTransaction(rule.transactionFor(day));
        _transactions = [..._transactions, saved];
      }
      final saved = await _store.saveRecurring(
        rule.copyWith(handledThrough: due.last),
      );
      _rules = _replace(_rules, saved, (r) => r.id);
      booked = true;
    }
    return booked;
  }

  // --- Kategóriák ---

  Future<Category> saveCategory(Category category) async {
    if (_demo) return category;
    final saved = await _store.saveCategory(category);
    _customCategories = _replace(_customCategories, saved, (c) => c.id);
    _applyCatalog();
    _changed();
    return saved;
  }

  /// Saját kategória törlése; a tételei az „Egyéb” kategóriába kerülnek.
  Future<void> deleteCategory(Category category) async {
    if (_demo) return;
    await _store.deleteCategory(category);
    _transactions = await _store.loadTransactions();
    _templates = await _store.loadTemplates();
    _rules = await _store.loadRecurring();
    _customCategories = [
      for (final existing in _customCategories)
        if (existing.id != category.id) existing,
    ];
    _applyCatalog();
    _changed();
  }

  /// Hány tétel, sablon és ismétlődő tétel használja a kategóriát.
  int usageOfCategory(String id) =>
      _transactions.where((t) => t.categoryId == id).length +
      _templates.where((t) => t.categoryId == id).length +
      _rules.where((r) => r.categoryId == id).length;

  void _applyCatalog() {
    currentCatalog = CategoryCatalog(_customCategories);
  }

  // --- Számlák ---

  Future<Account> saveAccount(Account account) async {
    if (_demo) return account;
    final saved = await _store.saveAccount(account);
    _accounts = await _store.loadAccounts();
    _changed();
    return saved;
  }

  /// Számla törlése; a tételei számla nélküliek lesznek (az alapértelmezett
  /// számlánál látszanak, ha van ilyen).
  Future<void> deleteAccount(int id) async {
    if (_demo) return;
    await _store.deleteAccount(id);
    _accounts = await _store.loadAccounts();
    _transactions = await _store.loadTransactions();
    _rules = await _store.loadRecurring();
    if (_selectedAccountId == id) _selectedAccountId = null;
    _changed();
  }

  /// Hány tétel tartozik a számlához (a számla nélküliek az
  /// alapértelmezetthez számítanak).
  int usageOfAccount(int id) => _transactions
      .where((transaction) => effectiveAccountId(transaction.accountId) == id)
      .length;

  // --- AI ---

  AiSettings get aiSettings => _aiSettings;

  Future<void> setAiSettings(AiSettings value) async {
    _aiSettings = value;
    _aiClient = null;
    notifyListeners();
    await _store.writeSettingMap(_aiKey, value.toMap());
  }

  AiClient? get _client =>
      _aiClient ??= createAiClient(_aiSettings, httpClient: _httpClient);

  /// Az AI-értelmező a jelenlegi beállításokkal (kikapcsolva a beépített
  /// értelmező dolgozik).
  AiInterpreter get aiInterpreter =>
      AiInterpreter(client: _client, rates: _rates, accounts: _accounts);

  /// Próbahívás: `null`, ha működik, különben a hiba szövege.
  Future<String?> testAi() async {
    if (!_aiSettings.isActive) return 'Előbb add meg a kulcsot.';
    final context = quickEntryContext;
    final outcome = await aiInterpreter.interpret(
      'tegnap Lidl 4500',
      AiInputKind.sentence,
      context,
      fallback: interpretQuickEntry('tegnap Lidl 4500', context),
    );
    if (!outcome.usedAi) return outcome.error ?? 'Az AI nem válaszolt.';
    if (outcome.result.amount != 4500) {
      return 'Az AI válaszolt, de furcsán értelmezte a próbamondatot.';
    }
    return null;
  }

  // --- Automatikus rögzítés ---

  CaptureBridge get captureBridge => _capture;
  bool get revolutCaptureEnabled => _revolutCapture;
  List<CaptureLogEntry> get captureLog => _captureLog;

  Future<void> setRevolutCaptureEnabled(bool value) async {
    _revolutCapture = value;
    notifyListeners();
    await _store.writeSettingMap(_captureKey, {'revolut': value});
    await _capture.setRevolutCaptureEnabled(value);
  }

  /// A beérkezett Revolut-értesítések és Apple Pay-fizetések feldolgozása.
  Future<CaptureReport?> processCaptures() {
    if (_demo) return Future.value();
    return _processing ??= _processCaptures().whenComplete(() {
      _processing = null;
    });
  }

  Future<CaptureReport?> _processCaptures() async {
    final List<Map<Object?, Object?>> raw;
    try {
      raw = await _capture.drain();
    } on Object catch (error) {
      debugPrint('Az automatikus rögzítés sora nem olvasható: $error');
      return null;
    }
    if (raw.isEmpty) return null;
    final events = [for (final map in raw) CapturedEvent.fromMap(map)]
      ..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
    final processor = CaptureProcessor(
      interpreter: aiInterpreter,
      accounts: _accounts,
    );
    final booked = <Transaction>[];
    var skipped = 0;
    final log = [..._captureLog];
    for (final event in events) {
      final decision = await processor.decide(
        event,
        quickEntryContext,
        recent: log,
      );
      var entry = decision.log;
      final transaction = decision.transaction;
      if (transaction != null) {
        final saved = await _store.saveTransaction(transaction);
        _transactions = [..._transactions, saved];
        booked.add(saved);
        entry = CaptureLogEntry(
          time: entry.time,
          source: entry.source,
          raw: entry.raw,
          outcome: entry.outcome,
          detail: entry.detail,
          amount: entry.amount,
          merchantKey: entry.merchantKey,
          transactionId: saved.id,
        );
      } else {
        skipped++;
      }
      log.insert(0, entry);
    }
    _captureLog = log.take(60).toList();
    await _store.writeSettingList(_captureLogKey, [
      for (final entry in _captureLog) entry.toMap(),
    ]);
    final report = CaptureReport(booked: booked, skipped: skipped);
    _changed();
    captureReports.value = report;
    return report;
  }

  // --- Beállítások ---

  Future<void> setDarkMode(bool value) async {
    if (value == _darkMode) return;
    _darkMode = value;
    notifyListeners();
    await _store.writeDarkMode(value);
  }

  Future<void> setReminderDefaults(ReminderDefaults value) async {
    final enabling = value.enabled && !_reminderDefaults.enabled;
    _reminderDefaults = value;
    notifyListeners();
    await _store.writeReminderDefaults(value);
    if (enabling) await _reminders.ensurePermission();
    unawaited(_syncReminders());
  }

  /// Próba-értesítés a beállításokból.
  Future<bool> sendTestReminder() async {
    final allowed = await _reminders.ensurePermission();
    if (!allowed) return false;
    await _reminders.showNow(
      title: 'Belefér',
      body: 'Így fog kinézni az emlékeztető egy esedékes tételről.',
    );
    return true;
  }

  Future<void> markTourSeen() async {
    if (_tourSeen) return;
    _tourSeen = true;
    notifyListeners();
    await _store.writeTourSeen(true);
  }

  // --- Bemutató ---

  /// A körbevezetés kezdete. Ha a felhasználónak nincs adata, bemutató
  /// adatok jelennek meg; a saját adatai sosem törlődnek.
  void startTour() {
    if (_tourActive) return;
    _tourActive = true;
    _selectedMonth = YearMonth.of(_today());
    if (!hasUserData) {
      _beforeDemo = _Snapshot(_transactions, _templates, _rules);
      final demo = DemoData.build(_today());
      _transactions = demo.transactions;
      _templates = demo.templates;
      _rules = demo.rules;
      _demo = true;
    }
    notifyListeners();
  }

  /// A körbevezetés vége: a bemutató adatok eltűnnek.
  Future<void> endTour() async {
    _tourActive = false;
    if (_demo) {
      final before = _beforeDemo!;
      _transactions = before.transactions;
      _templates = before.templates;
      _rules = before.rules;
      _beforeDemo = null;
      _demo = false;
    }
    notifyListeners();
    await markTourSeen();
  }

  // --- Törlés ---

  /// Minden helyi adat törlése, a beállítások visszaállítása.
  Future<void> clearAllData() async {
    if (_demo) await endTour();
    await _store.clearAll();
    _transactions = const [];
    _templates = const [];
    _rules = const [];
    _customCategories = const [];
    _accounts = const [];
    _selectedAccountId = null;
    _aiSettings = const AiSettings();
    _aiClient = null;
    _captureLog = const [];
    if (_revolutCapture) {
      _revolutCapture = false;
      await _capture.setRevolutCaptureEnabled(false);
    }
    _reminderDefaults = const ReminderDefaults();
    _darkMode = false;
    _selectedMonth = YearMonth.of(_today());
    _applyCatalog();
    _changed();
  }

  /// Az adatbázis lezárása (tesztekhez és újranyitás szimulálásához).
  Future<void> close() => _store.close();

  // --- Belső ---

  void _changed() {
    notifyListeners();
    _afterDataChange();
  }

  void _afterDataChange() {
    if (_demo) return;
    unawaited(_syncReminders());
    unawaited(_publishWidget());
  }

  Future<void> _syncReminders() async {
    try {
      await _reminders.schedule(
        planReminders(
          activeRules,
          now: _now(),
          enabled: _reminderDefaults.enabled,
        ),
      );
    } on Object catch (error) {
      debugPrint('Emlékeztetők ütemezése sikertelen: $error');
    }
  }

  Future<void> _publishWidget() async {
    try {
      await _widget.publish(widgetData());
    } on Object catch (error) {
      debugPrint('Widget frissítése sikertelen: $error');
    }
  }

  /// A kezdőképernyő-widget adatai (az aktuális hónap).
  HomeWidgetData widgetData() {
    final today = _today();
    final month = YearMonth.of(today);
    final summary = summarizeMonth(_transactions, month);
    UpcomingItem? next;
    for (final rule in activeRules) {
      if (rule.type != EntryType.expense) continue;
      final from =
          rule.handledThrough != null &&
              rule.handledThrough!.compareTo(today) >= 0
          ? CalendarDay(
              rule.handledThrough!.year,
              rule.handledThrough!.month,
              rule.handledThrough!.day + 1,
            )
          : today;
      final date = rule.nextOccurrence(from);
      if (date == null) continue;
      if (next == null || date.compareTo(next.date) < 0) {
        next = UpcomingItem(
          rule: rule,
          date: date,
          amount: rule.amountOn(date),
        );
      }
    }
    final nextText = next == null
        ? ''
        : '${next.rule.title}: ${formatForint(next.amount)}, '
              '${formatShortDate(next.date, today)}';
    return HomeWidgetData(
      monthLabel: formatYearMonth(month),
      income: formatForint(summary.income),
      expense: formatForint(summary.expense),
      balance: formatForint(summary.balance),
      balanceNegative: summary.balance < 0,
      nextDue: nextText,
    );
  }

  static List<T> _replace<T, K>(List<T> list, T item, K Function(T) key) => [
    for (final existing in list)
      if (key(existing) != key(item)) existing,
    item,
  ];
}

/// Az automatikus rögzítés egy körének eredménye.
class CaptureReport {
  const CaptureReport({required this.booked, required this.skipped});

  final List<Transaction> booked;

  /// Sikertelen fizetés, saját számlák közötti mozgás, ismétlődés stb.
  final int skipped;

  String get message {
    if (booked.isEmpty) {
      return '$skipped értesítést átnéztem, nem volt rögzítendő tétel.';
    }
    if (booked.length == 1) {
      final transaction = booked.single;
      return 'Automatikusan rögzítve: ${transaction.title}, '
          '${formatForint(transaction.amount)}';
    }
    return '${booked.length} tétel automatikusan rögzítve.';
  }
}

class _Snapshot {
  const _Snapshot(this.transactions, this.templates, this.rules);

  final List<Transaction> transactions;
  final List<EntryTemplate> templates;
  final List<RecurringRule> rules;
}
