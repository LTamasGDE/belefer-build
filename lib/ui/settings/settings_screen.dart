import 'package:flutter/material.dart';

import '../../domain/recurring.dart';
import '../../state/app_scope.dart';
import '../categories/categories_screen.dart';
import '../theme/app_theme.dart';
import '../theme/belefer_colors.dart';
import '../widgets/common.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/rows.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _clearAll(BuildContext context) async {
    final state = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final transactionCount = state.transactions.length;
    final templateCount = state.templates.length;
    final ruleCount = state.rules.length;
    final categoryCount = state.customCategories.length;
    final confirmed = await confirmAction(
      context,
      title: 'Minden adat törlése?',
      message:
          'Erről a készülékről végleg törlődik $transactionCount tétel, '
          '$templateCount sablon, $ruleCount ismétlődő tétel és '
          '$categoryCount saját kategória, a beállítások pedig '
          'visszaállnak. A művelet nem vonható vissza.',
      confirmLabel: 'Végleges törlés',
      destructive: true,
    );
    if (!confirmed) return;
    await state.clearAllData();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Minden adat törölve')));
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Beállítások')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.xxl),
        children: [
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionTitle('Megjelenés'),
                Panel(
                  padding: EdgeInsets.zero,
                  child: MergeSemantics(
                    child: InkWell(
                      onTap: () => state.setDarkMode(!state.darkMode),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.lg,
                          vertical: Space.md,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              state.darkMode
                                  ? Icons.dark_mode_rounded
                                  : Icons.light_mode_rounded,
                              color: colors.textMuted,
                            ),
                            const SizedBox(width: Space.md),
                            Expanded(
                              child: Text(
                                'Sötét mód',
                                style: textTheme.titleMedium,
                              ),
                            ),
                            Switch(
                              key: const ValueKey('dark-mode-switch'),
                              value: state.darkMode,
                              onChanged: state.setDarkMode,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SectionTitle('Testreszabás'),
                Panel(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      LinkRow(
                        key: const ValueKey('open-categories'),
                        icon: Icons.category_rounded,
                        title: 'Kategóriák',
                        subtitle: state.customCategories.isEmpty
                            ? 'Saját kategóriák felvétele'
                            : '${state.customCategories.length} saját kategória',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const CategoriesScreen(),
                          ),
                        ),
                      ),
                      const RowDivider(),
                      LinkRow(
                        key: const ValueKey('replay-tour'),
                        icon: Icons.school_rounded,
                        title: 'Bemutató újraindítása',
                        subtitle:
                            'Körbevezetés az alkalmazásban; az adataid '
                            'nem változnak.',
                        onTap: state.startTour,
                      ),
                    ],
                  ),
                ),
                const SectionTitle('Emlékeztetők'),
                const _ReminderSettings(),
                const SectionTitle('Adatok'),
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Minden adatod csak ezen a készüléken tárolódik.',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                      const SizedBox(height: Space.lg),
                      OutlinedButton.icon(
                        key: const ValueKey('clear-all-data'),
                        onPressed: () => _clearAll(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colors.danger,
                          side: BorderSide(color: colors.danger, width: 1.2),
                        ),
                        icon: const Icon(Icons.delete_forever_rounded),
                        label: const Text('Összes adat törlése'),
                      ),
                    ],
                  ),
                ),
                const SectionTitle('Névjegy'),
                Panel(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Space.lg,
                          Space.lg,
                          Space.lg,
                          Space.sm,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Belefér',
                                style: textTheme.titleLarge,
                              ),
                            ),
                            Text(
                              'Verzió ${state.versionLabel}',
                              key: const ValueKey('app-version'),
                              style: textTheme.bodyMedium?.copyWith(
                                color: colors.textMuted,
                                fontFeatures: tabularFigures,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            Space.sm,
                            0,
                            Space.sm,
                            Space.sm,
                          ),
                          child: TextButton(
                            onPressed: () => showLicensePage(
                              context: context,
                              applicationName: 'Belefér',
                              applicationVersion: state.versionLabel,
                            ),
                            child: const Text('Licencek'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReminderSettings extends StatelessWidget {
  const _ReminderSettings();

  Future<void> _pickTime(BuildContext context, ReminderDefaults current) async {
    final state = AppScope.read(context);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
      helpText: 'Emlékeztetők időpontja',
    );
    if (picked == null) return;
    await state.setReminderDefaults(
      current.copyWith(hour: picked.hour, minute: picked.minute),
    );
  }

  Future<void> _test(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final sent = await AppScope.read(context).sendTestReminder();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            sent
                ? 'Próbaértesítés elküldve.'
                : 'Az értesítések nincsenek engedélyezve a telefon '
                      'beállításaiban.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final defaults = state.reminderDefaults;
    final time =
        '${defaults.hour.toString().padLeft(2, '0')}:'
        '${defaults.minute.toString().padLeft(2, '0')}';
    final withReminder = state.activeRules
        .where((rule) => rule.reminder.enabled)
        .length;
    return Panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ToggleRow(
            icon: Icons.notifications_active_outlined,
            title: 'Emlékeztetők esedékes tételekről',
            subtitle: defaults.enabled
                ? '$withReminder ismétlődő tételnél bekapcsolva. A szöveg és '
                      'az időpont tételenként is állítható.'
                : 'Kikapcsolva egyetlen emlékeztető sem jelenik meg.',
            value: defaults.enabled,
            switchKey: const ValueKey('reminders-switch'),
            onChanged: (value) =>
                state.setReminderDefaults(defaults.copyWith(enabled: value)),
          ),
          if (defaults.enabled) ...[
            const RowDivider(),
            LinkRow(
              key: const ValueKey('reminder-default-time'),
              icon: Icons.schedule_rounded,
              title: 'Alapértelmezett időpont',
              subtitle:
                  'Új ismétlődő tételeknél: $time, '
                  '${defaults.daysBefore == 0 ? 'aznap' : '${defaults.daysBefore} nappal előtte'}',
              trailing: Text(time),
              onTap: () => _pickTime(context, defaults),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(52, 0, Space.lg, Space.md),
              child: ChoiceWrap<int>(
                semanticLabel: 'Hány nappal előtte',
                options: const [
                  (0, 'Aznap'),
                  (1, '1 nap'),
                  (2, '2 nap'),
                  (3, '3 nap'),
                  (7, '1 hét'),
                ],
                selected: defaults.daysBefore,
                onSelected: (value) => state.setReminderDefaults(
                  defaults.copyWith(daysBefore: value),
                ),
              ),
            ),
            const RowDivider(),
            LinkRow(
              key: const ValueKey('test-reminder'),
              icon: Icons.send_rounded,
              title: 'Próbaértesítés küldése',
              onTap: () => _test(context),
            ),
          ],
        ],
      ),
    );
  }
}
