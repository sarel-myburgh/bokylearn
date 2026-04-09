// ─────────────────────────────────────────────────────────────────────────────
// app_settings.dart — Persistent user settings (Riverpod + SharedPreferences)
//
// Follows the Riverpod StateNotifier pattern:
//   AppSettingsState  — pure immutable data class (the "what")
//   AppSettingsNotifier — loads, mutates, and persists state (the "how")
//   appSettingsProvider — the Riverpod provider widgets watch
//
// Storage split:
//   API keys → FlutterSecureStorage  (encrypted on-device keystore)
//   Everything else → SharedPreferences  (plain key-value file)
//
// The state starts with loaded=false. The notifier's constructor immediately
// kicks off _load(), which reads from disk asynchronously. AppShell shows a
// spinner until loaded becomes true.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants.dart';

// Which AI backend to use.
enum AiProvider { openRouter, anthropic, gemini, ollama }

// ─────────────────────────────────────────────────────────────────────────────
// AppSettingsState — immutable snapshot of all user preferences
// ─────────────────────────────────────────────────────────────────────────────
class AppSettingsState {
  // OpenRouter API key (sk-or-...). Null if not yet configured.
  final String? apiKey;

  // Anthropic direct API key (sk-ant-...). Optional — only needed if the
  // user wants to use Anthropic models directly instead of via OpenRouter.
  final String? anthropicApiKey;

  // Which AI backend is currently active.
  final AiProvider provider;

  // Selected OpenRouter model ID (e.g. "meta-llama/llama-3.1-8b-instruct:free").
  // Only relevant when provider == openRouter.
  final String selectedModel;

  // Selected Anthropic model ID. Only relevant when provider == anthropic.
  final String selectedAnthropicModel;

  // Google AI Studio (Gemini) API key. Only needed when provider == gemini.
  final String? googleApiKey;

  // Selected Gemini model ID. Only relevant when provider == gemini.
  final String selectedGeminiModel;

  // Base URL for a locally-hosted Ollama instance. Defaults to localhost:11434.
  final String ollamaBaseUrl;

  // Selected Ollama model name. Only relevant when provider == ollama.
  final String selectedOllamaModel;

  // Whether to show facts flagged as mature content. Off by default.
  final bool matureEnabled;

  // Set to true after the user completes (or skips) the interest setup screen.
  // Used by AppShell to decide whether to show onboarding.
  final bool onboardingComplete;

  // Natural language interest strings entered by the user.
  // Stored as-is and also substring-matched against fact tags to filter the feed.
  final List<String> interests;

  // When true, tapping a fact marks it seen so it never appears again.
  // When false, facts repeat freely (useful while testing or if the user
  // runs out of unseen facts).
  final bool trackSeen;

  // False until _load() completes. AppShell shows a spinner while false.
  final bool loaded;

  const AppSettingsState({
    this.apiKey,
    this.anthropicApiKey,
    this.provider = AiProvider.openRouter,
    this.selectedModel = AppConstants.defaultModel,
    this.selectedAnthropicModel = AppConstants.defaultAnthropicModel,
    this.googleApiKey,
    this.selectedGeminiModel = AppConstants.defaultGeminiModel,
    this.ollamaBaseUrl = AppConstants.defaultOllamaBaseUrl,
    this.selectedOllamaModel = AppConstants.defaultOllamaModel,
    this.matureEnabled = false,
    this.onboardingComplete = false,
    this.interests = const [],
    this.trackSeen = true,
    this.loaded = false,
  });

  // True if a key (or base URL for Ollama) exists for the active provider.
  // Used by AppShell to gate access to the feed.
  bool get hasApiKey {
    switch (provider) {
      case AiProvider.anthropic:
        return anthropicApiKey != null && anthropicApiKey!.isNotEmpty;
      case AiProvider.gemini:
        return googleApiKey != null && googleApiKey!.isNotEmpty;
      case AiProvider.ollama:
        return true; // Ollama needs no key — base URL is always set
      case AiProvider.openRouter:
        return apiKey != null && apiKey!.isNotEmpty;
    }
  }

  // The API key (or empty string) for the currently active provider.
  String get activeApiKey {
    switch (provider) {
      case AiProvider.anthropic: return anthropicApiKey ?? '';
      case AiProvider.gemini:    return googleApiKey ?? '';
      case AiProvider.ollama:    return '';
      case AiProvider.openRouter: return apiKey ?? '';
    }
  }

  // The model ID for the currently active provider.
  String get activeModel {
    switch (provider) {
      case AiProvider.anthropic:  return selectedAnthropicModel;
      case AiProvider.gemini:     return selectedGeminiModel;
      case AiProvider.ollama:     return selectedOllamaModel;
      case AiProvider.openRouter: return selectedModel;
    }
  }

  // Returns a new instance with only the specified fields changed.
  // All other fields carry over from the current state. This is the standard
  // immutable update pattern — avoids accidentally clearing fields.
  AppSettingsState copyWith({
    String? apiKey,
    String? anthropicApiKey,
    AiProvider? provider,
    String? selectedModel,
    String? selectedAnthropicModel,
    String? googleApiKey,
    String? selectedGeminiModel,
    String? ollamaBaseUrl,
    String? selectedOllamaModel,
    bool? matureEnabled,
    bool? onboardingComplete,
    List<String>? interests,
    bool? trackSeen,
    bool? loaded,
  }) {
    return AppSettingsState(
      apiKey: apiKey ?? this.apiKey,
      anthropicApiKey: anthropicApiKey ?? this.anthropicApiKey,
      provider: provider ?? this.provider,
      selectedModel: selectedModel ?? this.selectedModel,
      selectedAnthropicModel: selectedAnthropicModel ?? this.selectedAnthropicModel,
      googleApiKey: googleApiKey ?? this.googleApiKey,
      selectedGeminiModel: selectedGeminiModel ?? this.selectedGeminiModel,
      ollamaBaseUrl: ollamaBaseUrl ?? this.ollamaBaseUrl,
      selectedOllamaModel: selectedOllamaModel ?? this.selectedOllamaModel,
      matureEnabled: matureEnabled ?? this.matureEnabled,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      interests: interests ?? this.interests,
      trackSeen: trackSeen ?? this.trackSeen,
      loaded: loaded ?? this.loaded,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AppSettingsNotifier — loads and mutates settings, persists every change
// ─────────────────────────────────────────────────────────────────────────────
class AppSettingsNotifier extends StateNotifier<AppSettingsState> {
  AppSettingsNotifier() : super(const AppSettingsState()) {
    // Start loading immediately — state begins as the unloaded default.
    _load();
  }

  final _secure = const FlutterSecureStorage();

  // Reads all settings from storage and updates state to loaded=true.
  // Called once on construction. Every widget watching appSettingsProvider
  // will rebuild when state transitions from loaded=false to loaded=true.
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();

    // API keys come from secure storage (encrypted).
    final apiKey      = await _secure.read(key: AppConstants.keyApiKey);
    final anthropicKey = await _secure.read(key: AppConstants.keyAnthropicApiKey);
    final googleKey   = await _secure.read(key: AppConstants.keyGoogleApiKey);

    // Everything else from SharedPreferences.
    final providerStr = prefs.getString(AppConstants.keyProvider);
    final provider = switch (providerStr) {
      'anthropic' => AiProvider.anthropic,
      'gemini'    => AiProvider.gemini,
      'ollama'    => AiProvider.ollama,
      _           => AiProvider.openRouter,
    };
    final model          = prefs.getString(AppConstants.keySelectedModel) ?? AppConstants.defaultModel;
    final anthropicModel = prefs.getString(AppConstants.keySelectedAnthropicModel) ?? AppConstants.defaultAnthropicModel;
    final geminiModel    = prefs.getString(AppConstants.keySelectedGeminiModel) ?? AppConstants.defaultGeminiModel;
    final ollamaUrl      = prefs.getString(AppConstants.keyOllamaBaseUrl) ?? AppConstants.defaultOllamaBaseUrl;
    final ollamaModel    = prefs.getString(AppConstants.keySelectedOllamaModel) ?? AppConstants.defaultOllamaModel;
    final mature         = prefs.getBool(AppConstants.keyMatureEnabled) ?? false;
    final onboarding     = prefs.getBool(AppConstants.keyOnboardingComplete) ?? false;
    final trackSeen      = prefs.getBool(AppConstants.keyTrackSeen) ?? true;

    // Interests are stored as a JSON array of strings.
    final interestsJson = prefs.getString('interests');
    final interests = interestsJson != null
        ? List<String>.from(jsonDecode(interestsJson) as List)
        : <String>[];

    state = AppSettingsState(
      apiKey: apiKey,
      anthropicApiKey: anthropicKey,
      provider: provider,
      selectedModel: model,
      selectedAnthropicModel: anthropicModel,
      googleApiKey: googleKey,
      selectedGeminiModel: geminiModel,
      ollamaBaseUrl: ollamaUrl,
      selectedOllamaModel: ollamaModel,
      matureEnabled: mature,
      onboardingComplete: onboarding,
      interests: interests,
      trackSeen: trackSeen,
      loaded: true,
    );
  }

  // Each setter writes to storage and updates state immediately so the UI
  // reflects the change without waiting for a round-trip read.

  Future<void> setApiKey(String key) async {
    await _secure.write(key: AppConstants.keyApiKey, value: key);
    state = state.copyWith(apiKey: key);
  }

  Future<void> setAnthropicApiKey(String key) async {
    await _secure.write(key: AppConstants.keyAnthropicApiKey, value: key);
    state = state.copyWith(anthropicApiKey: key);
  }

  Future<void> setProvider(AiProvider provider) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyProvider, provider.name);
    state = state.copyWith(provider: provider);
  }

  Future<void> setModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keySelectedModel, model);
    state = state.copyWith(selectedModel: model);
  }

  Future<void> setAnthropicModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keySelectedAnthropicModel, model);
    state = state.copyWith(selectedAnthropicModel: model);
  }

  Future<void> setGoogleApiKey(String key) async {
    await _secure.write(key: AppConstants.keyGoogleApiKey, value: key);
    state = state.copyWith(googleApiKey: key);
  }

  Future<void> setGeminiModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keySelectedGeminiModel, model);
    state = state.copyWith(selectedGeminiModel: model);
  }

  Future<void> setOllamaBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyOllamaBaseUrl, url);
    state = state.copyWith(ollamaBaseUrl: url);
  }

  Future<void> setOllamaModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keySelectedOllamaModel, model);
    state = state.copyWith(selectedOllamaModel: model);
  }

  Future<void> setMatureEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyMatureEnabled, enabled);
    state = state.copyWith(matureEnabled: enabled);
  }

  // Enables or disables seen-fact tracking.
  // When disabled, facts are never written to the seen_facts box and can
  // appear in the feed repeatedly.
  Future<void> setTrackSeen(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyTrackSeen, enabled);
    state = state.copyWith(trackSeen: enabled);
  }

  // Called when the user finishes (or skips) onboarding. Saves both the
  // completion flag and the interest list in one go.
  Future<void> completeOnboarding(List<String> interests) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyOnboardingComplete, true);
    await prefs.setString('interests', jsonEncode(interests));
    state = state.copyWith(onboardingComplete: true, interests: interests);
  }

  // Updates the interest list without touching the onboarding flag.
  // Called from the Settings screen when the user edits interests post-onboarding.
  Future<void> updateInterests(List<String> interests) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('interests', jsonEncode(interests));
    state = state.copyWith(interests: interests);
  }
}

// The single global provider. Any widget can watch this to react to setting
// changes, or use .notifier to call mutating methods.
final appSettingsProvider =
    StateNotifierProvider<AppSettingsNotifier, AppSettingsState>(
  (ref) => AppSettingsNotifier(),
);
