import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:bokylearn/data/remote/model_client.dart';

void main() {
  test('OpenAI model filtering removes incompatible modalities', () {
    final body = jsonEncode({
      'data': [
        {'id': 'text-embedding-3-small'},
        {'id': 'gpt-5.6-sol'},
        {'id': 'gpt-realtime-2.1'},
      ],
    });
    final models = ModelClient.parseOpenAiModels(body);
    expect(models.map((model) => model.id), ['gpt-5.6-sol']);
  });

  test('Gemini filtering keeps chat models', () {
    final body = jsonEncode({
      'data': [
        {'id': 'gemini-embedding-001'},
        {'id': 'gemini-3.6-flash'},
        {'id': 'imagen-4'},
      ],
    });
    final models = ModelClient.parseGeminiModels(body);
    expect(models.single.id, 'gemini-3.6-flash');
  });
}
