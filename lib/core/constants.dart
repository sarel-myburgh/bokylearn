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

  static const blue   = Color(0xFF1565C0); // Cobalt — primary brand colour
  static const red    = Color(0xFFE53935); // Mario-red — warm energy
  static const green  = Color(0xFF2E7D32); // Zelda/Yoshi — life and growth
  static const amber  = Color(0xFFFFB300); // Pikachu gold — curiosity
  static const orange = Color(0xFFE65100); // Splatoon heat — discovery

  // Cycling palette for feed/bookmark cards.
  // Ordered so adjacent cards always contrast noticeably.
  static const cardAccents = <Color>[blue, red, green, amber, orange];

  // Fact card surface and text — warm cream background with deep ink text.
  static const cardBackground = Color(0xFFFFFBDB);
  static const cardText       = Color(0xFF30362F);

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
  // Monthly fact files: '$factsRepoRawBase/data/<month_key>.json'
  // e.g. 'dyk_2026_Mar.json' or 'tih_Jan.json'

  // ── OpenRouter ─────────────────────────────────────────────────────────────
  // OpenRouter is a unified API gateway that routes to many model providers.
  // Users supply their own key (BYOK — Bring Your Own Key).
  static const String openRouterBaseUrl = 'https://openrouter.ai/api/v1';
  static const String openRouterModelsUrl = '$openRouterBaseUrl/models';

  // Default model — Gemma 4 27B is fast and capable for educational content.
  // This is a real model ID (not a meta-router like 'openrouter/free') so
  // OpenRouter can route directly without an extra lookup step.
  static const String defaultModel = 'google/gemma-4-26b-a4b-it';

  // ── Google AI Studio (Gemini) ──────────────────────────────────────────────
  // Uses the OpenAI-compatible endpoint so we can reuse the same SSE parser.
  static const String geminiBaseUrl = 'https://generativelanguage.googleapis.com/v1beta/openai';
  static const String defaultGeminiModel = 'gemini-2.0-flash';
  static const List<String> geminiModels = [
    'gemini-2.0-flash',
    'gemini-2.0-flash-lite',
    'gemini-1.5-flash',
    'gemini-1.5-pro',
  ];

  // ── Ollama (locally hosted) ────────────────────────────────────────────────
  // OpenAI-compatible endpoint at /v1/chat/completions. No auth required.
  static const String defaultOllamaBaseUrl = 'http://localhost:11434';
  static const String defaultOllamaModel   = 'llama3.2';

  // ── Anthropic (direct) ─────────────────────────────────────────────────────
  // Anthropic direct integration bypasses OpenRouter entirely and tends to be
  // significantly faster because there is no intermediate routing layer.
  static const String anthropicBaseUrl = 'https://api.anthropic.com/v1';
  static const String anthropicVersion = '2023-06-01'; // Required header value
  static const String defaultAnthropicModel = 'claude-haiku-4-5-20251001';

  // All selectable Anthropic models, listed fastest → most capable.
  static const List<String> anthropicModels = [
    'claude-haiku-4-5-20251001', // Fastest, cheapest — good for most content
    'claude-sonnet-4-6',         // Balanced speed and quality
    'claude-opus-4-6',           // Highest quality, slowest
  ];

  // ── SharedPreferences / SecureStorage keys ─────────────────────────────────
  // These are the string keys used to read/write each setting.
  // Changing a key here will make existing saved values unreadable (migration
  // would be needed), so treat these as stable identifiers.
  static const String keyApiKey = 'openrouter_api_key';
  static const String keyAnthropicApiKey = 'anthropic_api_key';
  static const String keySelectedModel = 'selected_model';
  static const String keySelectedAnthropicModel = 'selected_anthropic_model';
  static const String keyGoogleApiKey     = 'google_api_key';
  static const String keySelectedGeminiModel = 'selected_gemini_model';
  static const String keyOllamaBaseUrl    = 'ollama_base_url';
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
