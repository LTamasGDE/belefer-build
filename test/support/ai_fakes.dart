import 'package:belefer/services/ai_client.dart';

/// Előre megadott választ adó AI.
class FakeAiClient implements AiClient {
  FakeAiClient(this.reply);

  final String Function(String user) reply;
  final List<String> systems = [];

  @override
  Future<String> completeJson({
    required String system,
    required String user,
  }) async {
    systems.add(system);
    return reply(user);
  }
}

class FailingAiClient implements AiClient {
  const FailingAiClient(this.error);

  final AiException error;

  @override
  Future<String> completeJson({
    required String system,
    required String user,
  }) => Future.error(error);
}
