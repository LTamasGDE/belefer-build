/// Melyik mesterséges intelligencia értelmezze a szöveget.
enum AiProvider {
  /// Csak a beépített, internet nélküli értelmező.
  off('off', 'Ki'),

  /// Google Gemini (saját, ingyenes API-kulccsal).
  gemini('gemini', 'Gemini'),

  /// Mistral (saját, ingyenes API-kulccsal).
  mistral('mistral', 'Mistral');

  const AiProvider(this.storageKey, this.label);

  final String storageKey;
  final String label;

  static AiProvider fromStorage(Object? value) {
    for (final provider in AiProvider.values) {
      if (provider.storageKey == value) return provider;
    }
    return AiProvider.off;
  }

  String get defaultModel => switch (this) {
    AiProvider.off => '',
    AiProvider.gemini => 'gemini-flash-lite-latest',
    AiProvider.mistral => 'mistral-small-latest',
  };
}

/// Az AI beállításai. A kulcsok szolgáltatónként külön tárolódnak, így a
/// váltás nem törli őket.
class AiSettings {
  const AiSettings({
    this.provider = AiProvider.off,
    this.geminiKey = '',
    this.mistralKey = '',
    this.geminiModel = '',
    this.mistralModel = '',
  });

  factory AiSettings.fromMap(Map<String, Object?>? map) {
    if (map == null) return const AiSettings();
    String text(String key) => (map[key] as String?)?.trim() ?? '';
    return AiSettings(
      provider: AiProvider.fromStorage(map['provider']),
      geminiKey: text('geminiKey'),
      mistralKey: text('mistralKey'),
      geminiModel: text('geminiModel'),
      mistralModel: text('mistralModel'),
    );
  }

  final AiProvider provider;
  final String geminiKey;
  final String mistralKey;
  final String geminiModel;
  final String mistralModel;

  /// A választott szolgáltató kulcsa.
  String get apiKey => switch (provider) {
    AiProvider.off => '',
    AiProvider.gemini => geminiKey,
    AiProvider.mistral => mistralKey,
  };

  /// A választott szolgáltató modellje (üresen az alapértelmezett).
  String get model {
    final custom = switch (provider) {
      AiProvider.off => '',
      AiProvider.gemini => geminiModel,
      AiProvider.mistral => mistralModel,
    };
    return custom.isEmpty ? provider.defaultModel : custom;
  }

  /// Be van-e kapcsolva és van-e kulcs.
  bool get isActive => provider != AiProvider.off && apiKey.isNotEmpty;

  AiSettings copyWith({
    AiProvider? provider,
    String? geminiKey,
    String? mistralKey,
    String? geminiModel,
    String? mistralModel,
  }) => AiSettings(
    provider: provider ?? this.provider,
    geminiKey: geminiKey ?? this.geminiKey,
    mistralKey: mistralKey ?? this.mistralKey,
    geminiModel: geminiModel ?? this.geminiModel,
    mistralModel: mistralModel ?? this.mistralModel,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    'provider': provider.storageKey,
    'geminiKey': geminiKey,
    'mistralKey': mistralKey,
    'geminiModel': geminiModel,
    'mistralModel': mistralModel,
  };
}
