import 'package:flutter/material.dart';

import '../../domain/ai/ai_settings.dart';
import '../../state/app_scope.dart';
import '../theme/app_theme.dart';
import '../theme/belefer_colors.dart';
import '../widgets/common.dart';
import '../widgets/rows.dart';

/// Az AI beállításai: szolgáltató, saját kulcs, modell, próba.
class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  late AiProvider _provider;
  late final TextEditingController _geminiKey;
  late final TextEditingController _mistralKey;
  late final TextEditingController _model;
  bool _showKey = false;
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    final settings = AppScope.read(context).aiSettings;
    _provider = settings.provider;
    _geminiKey = TextEditingController(text: settings.geminiKey);
    _mistralKey = TextEditingController(text: settings.mistralKey);
    _model = TextEditingController(text: _customModel(settings, _provider));
  }

  @override
  void dispose() {
    _geminiKey.dispose();
    _mistralKey.dispose();
    _model.dispose();
    super.dispose();
  }

  String _customModel(AiSettings settings, AiProvider provider) =>
      switch (provider) {
        AiProvider.gemini => settings.geminiModel,
        AiProvider.mistral => settings.mistralModel,
        AiProvider.off => '',
      };

  AiSettings _current() {
    final settings = AppScope.read(context).aiSettings;
    final model = _model.text.trim();
    return settings.copyWith(
      provider: _provider,
      geminiKey: _geminiKey.text.trim(),
      mistralKey: _mistralKey.text.trim(),
      geminiModel: _provider == AiProvider.gemini ? model : null,
      mistralModel: _provider == AiProvider.mistral ? model : null,
    );
  }

  Future<void> _save() async {
    await AppScope.read(context).setAiSettings(_current());
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    await _save();
    if (!mounted) return;
    final error = await AppScope.read(context).testAi();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testOk = error == null;
      _testResult = error ?? 'Működik: a próbamondatot jól értelmezte.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final keyController = _provider == AiProvider.mistral
        ? _mistralKey
        : _geminiKey;
    final infoStyle = textTheme.bodySmall?.copyWith(color: colors.textMuted);

    return PopScope(
      onPopInvokedWithResult: (_, _) => _save(),
      child: Scaffold(
        appBar: AppBar(title: const Text('AI')),
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
                    'Az AI értelmezi a gyorsrögzítés mondatait, a blokkokat és '
                    'az automatikusan érkező tételeket. Ha nincs internet vagy '
                    'elfogy a keret, a beépített értelmező dolgozik tovább.',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                  const SizedBox(height: Space.lg),
                  ChoiceWrap<AiProvider>(
                    semanticLabel: 'AI-szolgáltató',
                    options: [
                      for (final provider in AiProvider.values)
                        (provider, provider.label),
                    ],
                    selected: _provider,
                    onSelected: (value) {
                      setState(() {
                        _provider = value;
                        _model.text = _customModel(
                          AppScope.read(context).aiSettings,
                          value,
                        );
                        _testResult = null;
                      });
                      _save();
                    },
                  ),
                  if (_provider != AiProvider.off) ...[
                    const SizedBox(height: Space.lg),
                    TextField(
                      key: const ValueKey('ai-key'),
                      controller: keyController,
                      obscureText: !_showKey,
                      autocorrect: false,
                      enableSuggestions: false,
                      onChanged: (_) => setState(() => _testResult = null),
                      onEditingComplete: _save,
                      decoration: InputDecoration(
                        labelText: '${_provider.label} API-kulcs',
                        suffixIcon: IconButton(
                          tooltip: _showKey ? 'Elrejtés' : 'Megjelenítés',
                          icon: Icon(
                            _showKey
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                          ),
                          onPressed: () => setState(() => _showKey = !_showKey),
                        ),
                      ),
                    ),
                    const SizedBox(height: Space.sm),
                    Text(switch (_provider) {
                      AiProvider.gemini =>
                        'Ingyenes kulcs: aistudio.google.com → Get API key. '
                            'Fontos: a Gemini ingyenes keretét a Google '
                            'feltételei EGT-beli (így magyarországi) '
                            'felhasználóknak szánt appban csak fizetős módban '
                            'engedik; saját, egyéni használatra ez szürke zóna. '
                            'Az EGT-ben az ingyenes kérésekből sem tanítanak.',
                      AiProvider.mistral =>
                        'Ingyenes kulcs: console.mistral.ai → Experiment '
                            '(ingyenes) csomag, telefonszámos azonosítással. '
                            'Az ingyenes csomag adatait alapból tanításra '
                            'használhatják: az Admin → Privacy alatt '
                            'kikapcsolható.',
                      AiProvider.off => '',
                    }, style: infoStyle),
                    const SizedBox(height: Space.lg),
                    TextField(
                      key: const ValueKey('ai-model'),
                      controller: _model,
                      autocorrect: false,
                      onEditingComplete: _save,
                      decoration: InputDecoration(
                        labelText: 'Modell (nem kötelező)',
                        hintText: _provider.defaultModel,
                      ),
                    ),
                    const SizedBox(height: Space.lg),
                    FilledButton.icon(
                      key: const ValueKey('ai-test'),
                      onPressed: _testing || keyController.text.trim().isEmpty
                          ? null
                          : _test,
                      icon: _testing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_tethering_rounded),
                      label: const Text('Mentés és kapcsolat tesztelése'),
                    ),
                    if (_testResult != null) ...[
                      const SizedBox(height: Space.md),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            _testOk
                                ? Icons.check_circle_rounded
                                : Icons.error_outline_rounded,
                            color: _testOk ? colors.income : colors.danger,
                          ),
                          const SizedBox(width: Space.sm),
                          Expanded(
                            child: Text(
                              _testResult!,
                              key: const ValueKey('ai-test-result'),
                              style: textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: Space.xl),
                    Text(
                      'Mit küld el? Az értelmezendő szöveget (a beírt '
                      'mondatot, a blokk felismert szövegét vagy az értesítést, '
                      'benne az összeggel), a kategóriáid és számláid nevét, '
                      'az ismétlődő tételeid nevét és összegét, valamint '
                      'legfeljebb 40 korábbi tételed nevét és kategóriáját (a '
                      'besorolási szokásaidhoz). Egyenleget, számlaszámot vagy '
                      'a teljes tétellistát nem. A kulcs csak ezen a telefonon '
                      'tárolódik.',
                      style: infoStyle,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
