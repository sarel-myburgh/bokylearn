// ─────────────────────────────────────────────────────────────────────────────
// model_client.dart — Fetches model lists from various providers
//
// Used by the Settings screen to populate model selection dropdowns.
// Each provider has its own fetch method because they use different APIs:
//   OpenAI      — GET /v1/models
//   OpenCode Go — GET /zen/go/v1/models
//   Anthropic   — GET /v1/models
//   Ollama Cloud— GET /api/tags (native Ollama, with auth)
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/constants.dart';

class ModelInfo {
  final String id;
  final String name;

  const ModelInfo({required this.id, required this.name});
}

class ModelClient {
  static const _timeout = Duration(seconds: 15);

  static Future<List<ModelInfo>> fetchOpenAiModels(String apiKey) async {
    final response = await http
        .get(
          Uri.parse(AppConstants.openAiModelsUrl),
          headers: {'Authorization': 'Bearer $apiKey'},
        )
        .timeout(_timeout);
    _requireSuccess('OpenAI', response);
    return parseOpenAiModels(response.body);
  }

  static Future<List<ModelInfo>> fetchOpenRouterModels(String apiKey) async {
    final response = await http
        .get(
          Uri.parse(AppConstants.openRouterModelsUrl),
          headers: {'Authorization': 'Bearer $apiKey'},
        )
        .timeout(_timeout);
    _requireSuccess('OpenRouter', response);
    return parseOpenAiCompatibleModels(response.body);
  }

  static Future<List<ModelInfo>> fetchAnthropicModels(String apiKey) async {
    final response = await http
        .get(
          Uri.parse('${AppConstants.anthropicBaseUrl}/models?limit=1000'),
          headers: {
            'x-api-key': apiKey,
            'anthropic-version': AppConstants.anthropicVersion,
          },
        )
        .timeout(_timeout);
    _requireSuccess('Anthropic', response);
    return parseAnthropicModels(response.body);
  }

  static List<ModelInfo> parseAnthropicModels(String responseBody) {
    final body = jsonDecode(responseBody) as Map<String, dynamic>;
    final data = body['data'] as List<dynamic>? ?? const [];
    return _sort(
      data.map((item) {
        final model = item as Map<String, dynamic>;
        final id = model['id'] as String;
        return ModelInfo(id: id, name: model['display_name'] as String? ?? id);
      }),
    );
  }

  static Future<List<ModelInfo>> fetchGeminiModels(String apiKey) async {
    final response = await http
        .get(
          Uri.parse('${AppConstants.geminiBaseUrl}/models'),
          headers: {'Authorization': 'Bearer $apiKey'},
        )
        .timeout(_timeout);
    _requireSuccess('Gemini', response);
    return parseGeminiModels(response.body);
  }

  static Future<List<ModelInfo>> fetchOllamaCloudModels(String apiKey) async {
    final response = await http
        .get(
          Uri.parse('${AppConstants.ollamaCloudBaseUrl}/api/tags'),
          headers: {'Authorization': 'Bearer $apiKey'},
        )
        .timeout(_timeout);
    _requireSuccess('Ollama Cloud', response);
    return parseOllamaModels(response.body);
  }

  static Future<List<ModelInfo>> fetchOllamaModels(String baseUrl) async {
    final normalized = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final response = await http
        .get(Uri.parse('$normalized/api/tags'))
        .timeout(_timeout);
    _requireSuccess('Ollama', response);
    return parseOllamaModels(response.body);
  }

  static List<ModelInfo> parseOllamaModels(String responseBody) {
    final body = jsonDecode(responseBody) as Map<String, dynamic>;
    final models = body['models'] as List<dynamic>? ?? const [];
    return _sort(
      models.map((item) {
        final model = item as Map<String, dynamic>;
        final id = (model['model'] ?? model['name']) as String;
        return ModelInfo(id: id, name: id);
      }),
    );
  }

  static Future<List<ModelInfo>> fetchOpencodeGoModels(String apiKey) async {
    final response = await http
        .get(
          Uri.parse(AppConstants.opencodeGoModelsUrl),
          headers: {'Authorization': 'Bearer $apiKey'},
        )
        .timeout(_timeout);
    _requireSuccess('OpenCode Go', response);
    return parseOpenAiCompatibleModels(response.body);
  }

  static List<ModelInfo> parseOpenAiModels(String responseBody) =>
      parseOpenAiCompatibleModels(
        responseBody,
      ).where((model) => _isOpenAiTextModel(model.id)).toList();

  static List<ModelInfo> parseGeminiModels(String responseBody) =>
      parseOpenAiCompatibleModels(
        responseBody,
      ).where((model) => _isGeminiChatModel(model.id)).toList();

  static List<ModelInfo> parseOpenAiCompatibleModels(String responseBody) {
    final body = jsonDecode(responseBody) as Map<String, dynamic>;
    final data = body['data'] as List<dynamic>? ?? const [];
    return _sort(
      data.map((item) {
        final model = item as Map<String, dynamic>;
        final id = model['id'] as String;
        return ModelInfo(id: id, name: model['name'] as String? ?? id);
      }),
    );
  }

  static List<ModelInfo> _sort(Iterable<ModelInfo> models) {
    final result = models.toList();
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  static bool _isOpenAiTextModel(String id) {
    final value = id.toLowerCase();
    const unsupported = [
      'audio',
      'dall-e',
      'davinci',
      'embedding',
      'image',
      'moderation',
      'realtime',
      'sora',
      'transcribe',
      'tts',
      'whisper',
    ];
    return !unsupported.any(value.contains);
  }

  static bool _isGeminiChatModel(String id) {
    final value = id.toLowerCase();
    return value.startsWith('gemini-') &&
        !value.contains('embedding') &&
        !value.contains('image') &&
        !value.contains('live') &&
        !value.contains('tts');
  }

  static void _requireSuccess(String provider, http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        '$provider model request failed (${response.statusCode})',
      );
    }
  }
}
