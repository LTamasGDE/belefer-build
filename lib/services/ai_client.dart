import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/ai/ai_settings.dart';

/// Hiba az AI hívásakor, a felhasználónak szóló üzenettel.
class AiException implements Exception {
  const AiException(this.message, {this.retryable = false});

  final String message;

  /// Átmeneti hiba (hálózat, keret): később újra lehet próbálni.
  final bool retryable;

  @override
  String toString() => message;
}

/// Egy nyelvi modell, amely JSON-választ ad.
abstract class AiClient {
  Future<String> completeJson({required String system, required String user});
}

/// Az AI-kliens létrehozása a beállításokból (`null`, ha ki van kapcsolva).
AiClient? createAiClient(AiSettings settings, {http.Client? httpClient}) {
  if (!settings.isActive) return null;
  final client = httpClient ?? http.Client();
  return switch (settings.provider) {
    AiProvider.off => null,
    AiProvider.gemini => GeminiClient(
      apiKey: settings.apiKey,
      model: settings.model,
      httpClient: client,
    ),
    AiProvider.mistral => MistralClient(
      apiKey: settings.apiKey,
      model: settings.model,
      httpClient: client,
    ),
  };
}

const Duration _timeout = Duration(seconds: 20);

/// Google Gemini (Gemini API, saját kulccsal).
class GeminiClient implements AiClient {
  GeminiClient({
    required this.apiKey,
    required this.model,
    required http.Client httpClient,
  }) : _http = httpClient;

  final String apiKey;
  final String model;
  final http.Client _http;

  /// Ha a választott modell nem érhető el, ezekkel próbálkozik.
  static const List<String> fallbackModels = [
    'gemini-flash-lite-latest',
    'gemini-3.1-flash-lite',
    'gemini-2.5-flash-lite',
    'gemini-flash-latest',
  ];

  String? _workingModel;

  @override
  Future<String> completeJson({
    required String system,
    required String user,
  }) async {
    final models = [?_workingModel, model, ...fallbackModels].toSet().toList();
    AiException? last;
    for (final candidate in models) {
      try {
        final text = await _call(candidate, system, user);
        _workingModel = candidate;
        return text;
      } on _ModelUnavailable {
        last = AiException('A(z) $candidate modell nem érhető el.');
        continue;
      }
    }
    throw last ?? const AiException('Nincs elérhető Gemini-modell.');
  }

  Future<String> _call(String model, String system, String user) async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '$model:generateContent',
    );
    final body = jsonEncode({
      'systemInstruction': {
        'parts': [
          {'text': system},
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': user},
          ],
        },
      ],
      'generationConfig': {
        'responseMimeType': 'application/json',
        'temperature': 0,
      },
    });
    final response = await _send(
      () => _http.post(
        uri,
        headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey},
        body: body,
      ),
    );
    if (response.statusCode == 404) throw _ModelUnavailable();
    _checkStatus(response, 'Gemini');
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final candidates = (decoded as Map)['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      throw const AiException('A Gemini nem adott választ.');
    }
    final parts = ((candidates.first as Map)['content'] as Map?)?['parts'];
    if (parts is! List || parts.isEmpty) {
      throw const AiException('A Gemini üres választ adott.');
    }
    return [
      for (final part in parts)
        if (part is Map && part['text'] is String) part['text'] as String,
    ].join();
  }
}

/// Mistral (La Plateforme, saját kulccsal).
class MistralClient implements AiClient {
  MistralClient({
    required this.apiKey,
    required this.model,
    required http.Client httpClient,
  }) : _http = httpClient;

  final String apiKey;
  final String model;
  final http.Client _http;

  @override
  Future<String> completeJson({
    required String system,
    required String user,
  }) async {
    final response = await _send(
      () => _http.post(
        Uri.parse('https://api.mistral.ai/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': model,
          'temperature': 0,
          'response_format': {'type': 'json_object'},
          'messages': [
            {'role': 'system', 'content': system},
            {'role': 'user', 'content': user},
          ],
        }),
      ),
    );
    _checkStatus(response, 'Mistral');
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final choices = (decoded as Map)['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const AiException('A Mistral nem adott választ.');
    }
    final content = ((choices.first as Map)['message'] as Map?)?['content'];
    if (content is! String) {
      throw const AiException('A Mistral üres választ adott.');
    }
    return content;
  }
}

class _ModelUnavailable implements Exception {}

Future<http.Response> _send(Future<http.Response> Function() request) async {
  try {
    return await request().timeout(_timeout);
  } on TimeoutException {
    throw const AiException('Az AI nem válaszolt időben.', retryable: true);
  } on http.ClientException {
    throw const AiException('Nincs internetkapcsolat.', retryable: true);
  } on Exception {
    throw const AiException('Nincs internetkapcsolat.', retryable: true);
  }
}

void _checkStatus(http.Response response, String provider) {
  final code = response.statusCode;
  if (code >= 200 && code < 300) return;
  if (code == 400 && response.body.contains('API_KEY_INVALID')) {
    throw AiException('A $provider-kulcs érvénytelen.');
  }
  if (code == 401 || code == 403) {
    throw AiException(
      'A $provider elutasította a kérést (hibás kulcs vagy nem elérhető '
      'ebben a régióban).',
    );
  }
  if (code == 429) {
    throw AiException(
      'Elfogyott a $provider ingyenes kerete, később újra próbálom.',
      retryable: true,
    );
  }
  if (code >= 500) {
    throw AiException(
      'A $provider szolgáltatás átmenetileg nem elérhető.',
      retryable: true,
    );
  }
  throw AiException('A $provider hibát adott ($code).');
}
