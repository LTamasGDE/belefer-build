import 'package:flutter/material.dart';

import '../../state/app_scope.dart';
import '../theme/app_theme.dart';
import '../theme/belefer_colors.dart';
import '../widgets/common.dart';
import '../widgets/confirm_dialog.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _clearAll(BuildContext context) async {
    final state = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final transactionCount = state.transactions.length;
    final templateCount = state.templates.length;
    final confirmed = await confirmAction(
      context,
      title: 'Minden adat törlése?',
      message:
          'Erről a készülékről végleg törlődik $transactionCount tétel és '
          '$templateCount sablon, a beállítások pedig visszaállnak. '
          'A művelet nem vonható vissza.',
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
                const SectionTitle('Adatok'),
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'A tételek és a sablonok csak ezen a készüléken '
                        'tárolódnak.',
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
                              child: Text('Belefér', style: textTheme.titleLarge),
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
