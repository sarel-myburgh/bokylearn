// ─────────────────────────────────────────────────────────────────────────────
// openrouter_client.dart — Fetches the list of available OpenRouter models
//
// Used exclusively by the Settings screen to populate the model search
// dropdown. This is separate from AiClient (which handles actual AI calls)
// because model listing is a one-time settings action, not a streaming call.
//
// The fetched list is sorted alphabetically by display name and limited to
// 8 visible entries in the dropdown at a time (the user can type to filter).
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/constants.dart';

// Lightweight model descriptor — only id and display name are needed.
class OpenRouterModel {
  final String id;   // e.g. "meta-llama/llama-3.1-8b-instruct:free"
  final String name; // e.g. "Meta: Llama 3.1 8B Instruct (free)"

  const OpenRouterModel({required this.id, required this.name});
}

class OpenRouterClient {
  // Fetches all models available to the given API key from OpenRouter's
  // /api/v1/models endpoint. Returns them sorted alphabetically by name.
  // Throws an Exception on network or auth failure.
  static Future<List<OpenRouterModel>> fetchModels(String apiKey) async {
    final response = await http.get(
      Uri.parse(AppConstants.openRouterModelsUrl),
      headers: {'Authorization': 'Bearer $apiKey'},
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch models: ${response.statusCode}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    // OpenRouter wraps the model array in a "data" key.
    final data = body['data'] as List<dynamic>;

    return data.map((m) {
      final map = m as Map<String, dynamic>;
      return OpenRouterModel(
        id: map['id'] as String,
        // Some models have no name in the API response — fall back to the ID.
        name: (map['name'] as String?) ?? (map['id'] as String),
      );
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }
}
