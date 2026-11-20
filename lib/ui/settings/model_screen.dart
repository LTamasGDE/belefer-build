import 'package:flutter/material.dart';

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
                      const _Fact(
                        icon: Icons.school_rounded,
                        text:
                            'A tételeidből is tanul: amit rögzítesz vagy '
                            'javítasz, azt legközelebb így érti.',
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
