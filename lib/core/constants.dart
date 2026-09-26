// ─────────────────────────────────────────────────────────────────────────────
// constants.dart — Central place for all hard-coded values and the app palette
//
// Keeps magic strings and numbers out of business logic. Every URL, storage
// key, and default value lives here so changes only need to happen in one
// place.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BokyPalette — vivid, Nintendo-inspired brand colours
//
// These are fully-saturated, no-pastel colours used across the app:
//   • Theme primary / secondary / tertiary roles
//   • The five-colour cycle applied to feed and bookmark cards
//
// Inspired by the bold, playful colour language of Nintendo games —
// pure primaries, strong contrast, never washed-out.
// ─────────────────────────────────────────────────────────────────────────────
class BokyPalette {
  BokyPalette._();

  static const blue = Color(0xFF1565C0); // Cobalt — primary brand colour
  static const red = Color(0xFFE53935); // Mario-red — warm energy
  static const green = Color(0xFF2E7D32); // Zelda/Yoshi — life and growth
  static const amber = Color(0xFFFFB300); // Pikachu gold — curiosity
  static const orange = Color(0xFFE65100); // Splatoon heat — discovery

  // Cycling palette for feed/bookmark cards.
  // Ordered so adjacent cards always contrast noticeably.
  static const cardAccents = <Color>[blue, red, green, amber, orange];

  // Fact card surface and text — warm cream background with deep ink text.
  static const cardBackground = Color(0xFFFFFBDB);
  static const cardText = Color(0xFF30362F);

  // Feed screen background — deep forest green.
  static const feedBackground = Color(0xFF30362F);
}

class AppConstants {
  // ── Facts repo ─────────────────────────────────────────────────────────────
  // The facts repo publishes per-month JSON files to data/ and an index at
  // data/manifest.json.  The app fetches the manifest to find which months are
  // available, then downloads any months that are not yet in the local DB.
  static const String factsRepoRawBase =
      'https://raw.githubusercontent.com/sarel-myburgh/facts/main';
  static const String manifestUrl = '$factsRepoRawBase/data/manifest.json';
  static const String factsRepoApiUrl =
      'https://api.github.com/repos/sarel-myburgh/facts/contents/data';
  // Monthly fact files: '$factsRepoRawBase/data/<month_key>.json'
  // e.g. 'dyk_2026_Mar.json' or 'tih_Jan.json'

  // ── Tags ────────────────────────────────────────────────────────────────────
  // tags.json defines the interest taxonomy: categories → tags.
  // Fetched on first launch and cached; used by onboarding and settings.
  static const String tagsJsonUrl = '$factsRepoRawBase/data/tags.json';

  // ── OpenAI ─────────────────────────────────────────────────────────────────
  // Uses an OpenAI Platform API key. ChatGPT subscription credentials are not
  // interchangeable with Platform API billing.
  static const String openAiBaseUrl = 'https://api.openai.com/v1';
  static const String openAiModelsUrl = '$openAiBaseUrl/models';

  // The model list is fetched for the supplied key; this value is only the
  // initial preference before discovery completes.
  static const String defaultOpenAiModel = 'gpt-5.6-sol';

  // ── OpenRouter ─────────────────────────────────────────────────────────────
  static const String openRouterBaseUrl = 'https://openrouter.ai/api/v1';
  static const String openRouterModelsUrl = '$openRouterBaseUrl/models';
  static const String defaultOpenRouterModel = 'google/gemma-4-26b-a4b-it';

  // ── Google AI Studio (Gemini) ──────────────────────────────────────────────
  // Uses the OpenAI-compatible endpoint so we can reuse the same SSE parser.
  static const String geminiBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta/openai';
  static const String defaultGeminiModel = 'gemini-3.6-flash';

  // ── Anthropic (direct) ─────────────────────────────────────────────────────
  // Uses Anthropic's native Messages and Models APIs.
  static const String anthropicBaseUrl = 'https://api.anthropic.com/v1';
  static const String anthropicVersion = '2023-06-01'; // Required header value
  static const String defaultAnthropicModel = 'claude-haiku-4-5-20251001';

  // All selectable Anthropic models, listed fastest → most capable.
  static const List<String> anthropicModels = [
    'claude-haiku-4-5-20251001', // Fastest, cheapest — good for most content
    'claude-sonnet-4-6', // Balanced speed and quality
    'claude-opus-4-6', // Highest quality, slowest
  ];

  // ── OpenCode Go ────────────────────────────────────────────────────────────
  // Uses the Go plan's OpenAI-compatible endpoint. Available models depend on
  // the supplied OpenCode Go key.
  // Models are fetched dynamically from GET /v1/models.
  static const String opencodeGoBaseUrl = 'https://opencode.ai/zen/go/v1';
  static const String opencodeGoModelsUrl = '$opencodeGoBaseUrl/models';
  static const String defaultOpencodeGoModel = 'kimi-k3';

  // ── Ollama Cloud ────────────────────────────────────────────────────────────
  // Ollama Cloud uses the native Ollama /api/chat endpoint (NOT OpenAI-compatible).
  // Requires an API key and a user account at ollama.com.
  static const String ollamaCloudBaseUrl = 'https://ollama.com';
  static const String defaultOllamaCloudModel = 'gpt-oss:120b';

  // ── Ollama Local ────────────────────────────────────────────────────────────
  static const String defaultOllamaBaseUrl = 'http://localhost:11434';
  static const String defaultOllamaModel = 'llama3.2';

  // ── SharedPreferences / SecureStorage keys ─────────────────────────────────
  // These are the string keys used to read/write each setting.
  // Changing a key here will make existing saved values unreadable (migration
  // would be needed), so treat these as stable identifiers.
  static const String keyOpenAiApiKey = 'openai_api_key';
  static const String keyOpenRouterApiKey = 'openrouter_api_key';
  static const String keyAnthropicApiKey = 'anthropic_api_key';
  static const String keySelectedOpenAiModel = 'selected_openai_model';
  static const String keySelectedOpenRouterModel = 'selected_model';
  static const String keySelectedAnthropicModel = 'selected_anthropic_model';
  static const String keyGoogleApiKey = 'google_api_key';
  static const String keySelectedGeminiModel = 'selected_gemini_model';
  static const String keyOpencodeGoApiKey = 'opencode_go_api_key';
  static const String keySelectedOpencodeGoModel = 'selected_opencode_go_model';
  static const String keyOllamaCloudApiKey = 'ollama_cloud_api_key';
  static const String keySelectedOllamaCloudModel =
      'selected_ollama_cloud_model';
  static const String keyOllamaBaseUrl = 'ollama_base_url';
  static const String keySelectedOllamaModel = 'selected_ollama_model';
  static const String keyProvider = 'ai_provider';
  static const String keyMatureEnabled = 'mature_content_enabled';
  static const String keyOnboardingComplete = 'onboarding_complete';
  static const String keyTrackSeen = 'track_seen';

  // ── Feed ───────────────────────────────────────────────────────────────────
  // Number of facts to pre-buffer in memory. The feed loads this many at a
  // time and requests more when the user approaches the end of the list.
  static const int feedBufferSize = 10;
}
