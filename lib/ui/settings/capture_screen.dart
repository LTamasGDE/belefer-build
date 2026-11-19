import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/capture/captured_event.dart';
import '../../domain/formatting.dart';
import '../../domain/calendar.dart';
import '../../state/app_scope.dart';
import '../accounts/accounts_screen.dart';
import '../theme/app_theme.dart';
import '../theme/belefer_colors.dart';
import '../widgets/common.dart';
import '../widgets/rows.dart';

/// Automatikus rögzítés: Androidon a Revolut-értesítések, iPhone-on az
/// Apple Pay-fizetések; számlák és napló.
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with WidgetsBindingObserver {
  bool? _accessGranted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAccess();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    // Visszatérés a rendszerbeállításokból.
    if (lifecycle == AppLifecycleState.resumed) _checkAccess();
  }

  Future<void> _checkAccess() async {
    final bridge = AppScope.read(context).captureBridge;
    if (!bridge.supportsNotifications) return;
    final granted = await bridge.isNotificationAccessGranted();
    if (mounted) setState(() => _accessGranted = granted);
  }

  Future<void> _toggleRevolut(bool value) async {
    final state = AppScope.read(context);
    await state.setRevolutCaptureEnabled(value);
    if (value && !(_accessGranted ?? false)) {
      await state.captureBridge.openNotificationAccessSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final bridge = state.captureBridge;
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final infoStyle = textTheme.bodySmall?.copyWith(color: colors.textMuted);

    final children = <Widget>[
      Text(
        'A fizetéseid maguktól kerülnek a tételek közé: az AI (vagy a '
        'beépített értelmező) kiszűri a sikertelen fizetéseket és a saját '
        'számláid közötti mozgást, és a felismerő szavak alapján a jó számlára '
        'teszi őket. Minden automatikus tétel szerkeszthető és törölhető.',
        style: textTheme.bodyMedium?.copyWith(color: colors.textMuted),
      ),
    ];

    if (bridge.supportsNotifications) {
      final granted = _accessGranted ?? false;
      children.addAll([
        const SectionTitle('Revolut-értesítések (Android)'),
        Panel(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ToggleRow(
                icon: Icons.notifications_active_outlined,
                title: 'Revolut-fizetések rögzítése',
                subtitle: !state.revolutCaptureEnabled
                    ? 'Kikapcsolva.'
                    : granted
                    ? 'Bekapcsolva: a Revolut értesítéseiből rögzít.'
                    : 'Még meg kell adni az értesítés-hozzáférést.',
                value: state.revolutCaptureEnabled,
                switchKey: const ValueKey('revolut-switch'),
                onChanged: _toggleRevolut,
              ),
              if (state.revolutCaptureEnabled && !granted) ...[
                const RowDivider(),
                LinkRow(
                  key: const ValueKey('grant-access'),
                  icon: Icons.lock_open_rounded,
                  title: 'Értesítés-hozzáférés megadása',
                  subtitle:
                      'Ha szürke a kapcsoló: Beállítások → Alkalmazások → '
                      'Belefér → ⋮ → Korlátozott beállítások engedélyezése, '
                      'majd újra itt.',
                  onTap: bridge.openNotificationAccessSettings,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Space.sm),
        Text(
          'Az Android ezt az engedélyt rendszerszinten adja meg, de a Belefér '
          'kódja minden más alkalmazás értesítését azonnal eldobja: csak a '
          'Revolut (com.revolut.revolut) értesítéseit olvassa, más bankét, '
          'üzenetekét semmiképp. A tételek a Belefér következő megnyitásakor '
          'kerülnek be.',
          style: infoStyle,
        ),
      ]);
    }

    if (bridge.supportsApplePay) {
      children.addAll([
        const SectionTitle('Apple Pay (iPhone)'),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Beállítás kártyánként (egyszer kell):',
                style: textTheme.titleMedium,
              ),
              const SizedBox(height: Space.sm),
              for (final (index, step) in const [
                'Nyisd meg a Parancsok appot → Automatizálás → + (Új '
                    'automatizálás).',
                'Válaszd a „Wallet” (régebben „Tranzakció”) eseményt, és '
                    'jelöld be az egyik kártyát (pl. a saját Revolut-kártyát). '
                    'Állítsd „Azonnali futtatás”-ra.',
                'Új parancs → keresd a Belefér „Fizetés rögzítése a '
                    'Belefér-ben” műveletét.',
                'Összeg = Parancs bemenete → Összeg; Kereskedő = Parancs '
                    'bemenete → Kereskedő. A Kártya mezőbe egyszerűen írd be, '
                    'melyik kártya ez (pl. „Saját Revolut”), hiszen az '
                    'automatizmus csak ennél a kártyánál indul el.',
                'Ismételd meg a többi kártyával (pl. a közös számla '
                    'kártyájával, Kártya: „Közös”). Ugyanezt a szót írd a '
                    'számla felismerő szavai közé a Belefér-ben.',
              ].indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text(
                          '${index + 1}.',
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(step, style: textTheme.bodyMedium),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.sm),
        Text(
          'Az iPhone más alkalmazások értesítéseit nem engedi olvasni; az '
          'Apple Pay-automatizmus az iOS saját, ingyenes módja. Elutasított '
          'fizetésnél is elindulhat: a pár percen belül megismételt, azonos '
          'fizetésből csak egy marad, a többit egy koppintással törölheted. '
          'A tételek a Belefér következő megnyitásakor kerülnek be.',
          style: infoStyle,
        ),
      ]);
    }

    if (!bridge.supportsNotifications && !bridge.supportsApplePay) {
      children.add(
        const Padding(
          padding: EdgeInsets.only(top: Space.lg),
          child: Text('Ezen az eszközön nem érhető el.'),
        ),
      );
    }

    children.addAll([
      const SectionTitle('Számlák'),
      Panel(
        padding: EdgeInsets.zero,
        child: LinkRow(
          icon: Icons.account_balance_wallet_rounded,
          title: 'Számlák és felismerő szavak',
          subtitle: state.accounts.isEmpty
              ? 'Még nincs számla: minden egy listába kerül.'
              : state.accounts.map((account) => account.name).join(', '),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const AccountsScreen()),
          ),
        ),
      ),
      SectionTitle(
        'Napló',
        trailing: TextButton.icon(
          key: const ValueKey('process-now'),
          onPressed: () => unawaited(state.processCaptures()),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Feldolgozás most'),
        ),
      ),
      if (state.captureLog.isEmpty)
        Text(
          'Még nem érkezett semmi. Itt látod majd, mit küldött a Revolut vagy '
          'az Apple Pay, és mi lett vele.',
          style: infoStyle,
        )
      else
        Panel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final (index, entry) in state.captureLog.take(30).indexed) ...[
                if (index > 0) const RowDivider(),
                _LogTile(entry: entry),
              ],
            ],
          ),
        ),
    ]);

    return Scaffold(
      appBar: AppBar(title: const Text('Automatikus rögzítés')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.page,
          Space.sm,
          Space.page,
          Space.xxl,
        ),
        children: [
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _LogTile extends StatefulWidget {
  const _LogTile({required this.entry});

  final CaptureLogEntry entry;

  @override
  State<_LogTile> createState() => _LogTileState();
}

class _LogTileState extends State<_LogTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final entry = widget.entry;
    final today = AppScope.of(context).today();
    final time =
        '${formatShortDate(CalendarDay.fromDateTime(entry.time), today)} '
        '${entry.time.hour.toString().padLeft(2, '0')}:'
        '${entry.time.minute.toString().padLeft(2, '0')}';
    final booked = entry.outcome == CaptureOutcome.booked;
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              booked
                  ? Icons.check_circle_rounded
                  : entry.outcome == CaptureOutcome.failed
                  ? Icons.block_rounded
                  : Icons.remove_circle_outline_rounded,
              size: 20,
              color: booked ? colors.income : colors.textMuted,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${entry.source.label} · $time',
                    style: textTheme.labelMedium?.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                  Text(entry.outcome.label, style: textTheme.bodyMedium),
                  if (entry.detail.isNotEmpty)
                    Text(
                      entry.detail,
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  if (_expanded) ...[
                    const SizedBox(height: Space.xs),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(Space.sm),
                      decoration: BoxDecoration(
                        color: colors.sunken,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: SelectableText(
                        entry.raw,
                        style: textTheme.bodySmall,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              color: colors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
