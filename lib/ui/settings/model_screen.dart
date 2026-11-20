import 'package:flutter/material.dart';

import '../../domain/formatting.dart';
import '../../domain/model/belefer_model.dart';
import '../../domain/quick_entry/interpreter.dart';
import '../../state/app_scope.dart';
import '../quick_entry/quick_entry_preview.dart';
import '../theme/app_theme.dart';
import '../theme/belefer_colors.dart';
import '../widgets/common.dart';

/// A saját nyelvi modell bemutatása és kipróbálása.
class ModelScreen extends StatefulWidget {
  const ModelScreen({super.key});

  @override
  State<ModelScreen> createState() => _ModelScreenState();
}

class _ModelScreenState extends State<ModelScreen> {
  final _text = TextEditingController();
  QuickEntryResult? _result;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _interpret(String text) {
    setState(() {
      _result = text.trim().isEmpty
          ? null
          : AppScope.read(context).tryInterpret(text);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final model = currentModel;
    final infoStyle = textTheme.bodySmall?.copyWith(color: colors.textMuted);
    final result = _result;

    return Scaffold(
      appBar: AppBar(title: const Text('Saját modell')),
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
              children: [
                Text(
                  'A Belefér saját nyelvi modellje értelmezi a gyorsrögzítés '
                  'mondatait, a blokkokat és a banki értesítéseket. A '
                  'telefonon fut: nem kell hozzá internet, kulcs vagy '
                  'előfizetés, és semmit nem küld el sehova.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colors.textMuted,
                  ),
                ),
                const SizedBox(height: Space.lg),
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Fact(
                        icon: Icons.memory_rounded,
                        text: model == null
                            ? 'A modell nem töltődött be: a beépített '
                                  'szabályok dolgoznak.'
                            : 'Betanítva magyar pénzügyi mondatokra, '
                                  'blokkokra és értesítésekre '
                                  '(${_thousands(model.weightCount)} súly).',
                      ),
                      const SizedBox(height: Space.md),
                      _Fact(
                        icon: Icons.school_rounded,
                        text: state.learnedTitleCount == 0
                            ? 'A tételeidből is tanul: amit rögzítesz vagy '
                                  'javítasz, azt legközelebb így sorolja be.'
                            : 'A tételeidből is tanul: '
                                  '${state.learnedTitleCount} saját '
                                  'megnevezésedet ismeri.',
                      ),
                      const SizedBox(height: Space.md),
                      const _Fact(
                        icon: Icons.spellcheck_rounded,
                        text:
                            'Érti az elírásokat, a toldalékokat, a szórendet '
                            'és a szlenget („meki 2890”, „a pékségben '
                            'hagytam 2500-at”).',
                      ),
                    ],
                  ),
                ),
                const SectionTitle('Amit megtanultam rólad'),
                const _LearnedPanel(),
                const SectionTitle('Próbáld ki'),
                TextField(
                  key: const ValueKey('model-try'),
                  controller: _text,
                  onChanged: _interpret,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Pl. tegnap a kínaiban ebédeltem 2600',
                  ),
                ),
                const SizedBox(height: Space.md),
                if (result != null)
                  QuickResultCard(result: result, today: state.today())
                else
                  Text(
                    'Írj be egy mondatot: megmutatom, hogyan érteném. '
                    'Itt semmi nem kerül rögzítésre.',
                    style: infoStyle,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _thousands(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: colors.accentText),
        const SizedBox(width: Space.md),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }
}

/// A tételekből és a javításaidból tanult tudás, kérdezés nélkül.
class _LearnedPanel extends StatelessWidget {
  const _LearnedPanel();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final today = state.today();
    final knowledge = state.knowledge;
    final habits =
        knowledge.habits.values
            .where((habit) => habit.count >= 2 && habit.usualAmount != null)
            .toList()
          ..sort((a, b) => b.count.compareTo(a.count));
    final accounts = {
      for (final account in state.accounts)
        if (account.id != null) account.id!: account.name,
    };
    final accountHabits =
        knowledge.habits.values
            .where(
              (habit) =>
                  habit.usualAccountId != null &&
                  accounts.containsKey(habit.usualAccountId),
            )
            .toList()
          ..sort((a, b) => b.count.compareTo(a.count));
    final muted = textTheme.bodySmall?.copyWith(color: colors.textMuted);
    final empty =
        knowledge.patterns.isEmpty &&
        habits.isEmpty &&
        accountHabits.isEmpty &&
        state.lessons.isEmpty;
    return Panel(
      key: const ValueKey('learned-panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (empty)
            Text(
              'Még nem ismerlek eléggé. Ahogy rögzítesz, megtanulom a szokásos '
              'összegeidet, számláidat, a rendszeres tételeidet (pl. mikor jön '
              'a fizetés), és a javításaidból a saját szavaidat is – kérdezés '
              'nélkül.',
              style: textTheme.bodyMedium,
            ),
          if (knowledge.patterns.isNotEmpty) ...[
            Text('Rendszeres tételek', style: textTheme.labelLarge),
            const SizedBox(height: Space.xs),
            for (final pattern in knowledge.patterns.take(8))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${pattern.title}: ${pattern.rhythm}, '
                  '${formatForint(pattern.amount)} – következő: '
                  '${formatShortDate(pattern.next, today)}',
                  style: textTheme.bodyMedium,
                ),
              ),
            const SizedBox(height: Space.md),
          ],
          if (habits.isNotEmpty) ...[
            Text('Szokásos összegek', style: textTheme.labelLarge),
            const SizedBox(height: Space.xs),
            for (final habit in habits.take(8))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${habit.title}: ${formatForint(habit.usualAmount!)} '
                  '(${habit.count}×)',
                  style: textTheme.bodyMedium,
                ),
              ),
            const SizedBox(height: Space.md),
          ],
          if (accountHabits.isNotEmpty) ...[
            Text('Szokásos számlák', style: textTheme.labelLarge),
            const SizedBox(height: Space.xs),
            for (final habit in accountHabits.take(6))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${habit.title} → ${accounts[habit.usualAccountId]}',
                  style: textTheme.bodyMedium,
                ),
              ),
            const SizedBox(height: Space.md),
          ],
          if (state.lessons.isNotEmpty) ...[
            Text(
              '${state.lessons.length} kifejezésedet tanultam meg a '
              'gyorsrögzítésből (amit beírtál, és ahogy elmentetted).',
              style: muted,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const ValueKey('forget-lessons'),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Elfelejtsem a tanult kifejezéseket?'),
                      content: const Text(
                        'A tételeid megmaradnak, és a szokásaidat továbbra is '
                        'látom belőlük; csak a gyorsrögzítésből tanult '
                        'kifejezések törlődnek.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(false),
                          child: const Text('Mégse'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(true),
                          child: const Text('Elfelejtés'),
                        ),
                      ],
                    ),
                  );
                  if (ok ?? false) await state.forgetLessons();
                },
                child: const Text('Tanult kifejezések elfelejtése'),
              ),
            ),
          ],
          if (!empty)
            Text(
              'Mindez csak a telefonodon van, a tételeidből számolom.',
              style: muted,
            ),
        ],
      ),
    );
  }
}
