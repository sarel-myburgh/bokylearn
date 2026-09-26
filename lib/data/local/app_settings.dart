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
enum AiProvider {
  openAi,
  openRouter,
  anthropic,
  gemini,
  ollamaCloud,
  ollama,
  opencodeGo,
}

// ─────────────────────────────────────────────────────────────────────────────
// AppSettingsState — immutable snapshot of all user preferences
// ─────────────────────────────────────────────────────────────────────────────
class AppSettingsState {
  // OpenAI Platform API key. Null if not yet configured.
  final String? openAiApiKey;

  final String? openRouterApiKey;

  // Anthropic direct API key (sk-ant-...). Optional — only needed if the
  // user wants to use Anthropic directly.
  final String? anthropicApiKey;

  // Which AI backend is currently active.
  final AiProvider provider;

  // Selected OpenRouter model ID (e.g. "meta-llama/llama-3.1-8b-instruct:free").
  // Only relevant when provider == openAi.
  final String selectedOpenAiModel;

  final String selectedOpenRouterModel;

  // Selected Anthropic model ID. Only relevant when provider == anthropic.
  final String selectedAnthropicModel;

  // Google AI Studio (Gemini) API key. Only needed when provider == gemini.
  final String? googleApiKey;

  // Selected Gemini model ID. Only relevant when provider == gemini.
  final String selectedGeminiModel;

  final String? opencodeGoApiKey;

  // Selected OpenCode Go model ID.
  final String selectedOpencodeGoModel;

  // Ollama Cloud API key. Only needed when provider == ollamaCloud.
  final String? ollamaCloudApiKey;

  // Selected Ollama Cloud model name. Only relevant when provider == ollamaCloud.
  final String selectedOllamaCloudModel;

  final String ollamaBaseUrl;

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
    this.openAiApiKey,
    this.openRouterApiKey,
    this.anthropicApiKey,
    this.provider = AiProvider.openAi,
    this.selectedOpenAiModel = AppConstants.defaultOpenAiModel,
    this.selectedOpenRouterModel = AppConstants.defaultOpenRouterModel,
    this.selectedAnthropicModel = AppConstants.defaultAnthropicModel,
    this.googleApiKey,
    this.selectedGeminiModel = AppConstants.defaultGeminiModel,
    this.opencodeGoApiKey,
    this.selectedOpencodeGoModel = AppConstants.defaultOpencodeGoModel,
    this.ollamaCloudApiKey,
    this.selectedOllamaCloudModel = AppConstants.defaultOllamaCloudModel,
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
      case AiProvider.opencodeGo:
        return opencodeGoApiKey != null && opencodeGoApiKey!.isNotEmpty;
      case AiProvider.ollamaCloud:
        return ollamaCloudApiKey != null && ollamaCloudApiKey!.isNotEmpty;
      case AiProvider.openAi:
        return openAiApiKey != null && openAiApiKey!.isNotEmpty;
      case AiProvider.openRouter:
        return openRouterApiKey != null && openRouterApiKey!.isNotEmpty;
      case AiProvider.ollama:
        return ollamaBaseUrl.trim().isNotEmpty;
    }
  }

  // The API key (or empty string) for the currently active provider.
  String get activeApiKey {
    switch (provider) {
      case AiProvider.anthropic:
        return anthropicApiKey ?? '';
      case AiProvider.gemini:
        return googleApiKey ?? '';
      case AiProvider.opencodeGo:
        return opencodeGoApiKey ?? '';
      case AiProvider.ollamaCloud:
        return ollamaCloudApiKey ?? '';
      case AiProvider.openAi:
        return openAiApiKey ?? '';
      case AiProvider.openRouter:
        return openRouterApiKey ?? '';
      case AiProvider.ollama:
        return '';
    }
  }

  // The model ID for the currently active provider.
  String get activeModel {
    switch (provider) {
      case AiProvider.anthropic:
        return selectedAnthropicModel;
      case AiProvider.gemini:
        return selectedGeminiModel;
      case AiProvider.opencodeGo:
        return selectedOpencodeGoModel;
      case AiProvider.ollamaCloud:
        return selectedOllamaCloudModel;
      case AiProvider.openAi:
        return selectedOpenAiModel;
      case AiProvider.openRouter:
        return selectedOpenRouterModel;
      case AiProvider.ollama:
        return selectedOllamaModel;
    }
  }

  // Returns a new instance with only the specified fields changed.
  // All other fields carry over from the current state. This is the standard
  // immutable update pattern — avoids accidentally clearing fields.
  AppSettingsState copyWith({
    String? openAiApiKey,
    String? openRouterApiKey,
    String? anthropicApiKey,
    AiProvider? provider,
    String? selectedOpenAiModel,
    String? selectedOpenRouterModel,
    String? selectedAnthropicModel,
    String? googleApiKey,
    String? selectedGeminiModel,
    String? opencodeGoApiKey,
    String? selectedOpencodeGoModel,
    String? ollamaCloudApiKey,
    String? selectedOllamaCloudModel,
    String? ollamaBaseUrl,
    String? selectedOllamaModel,
    bool? matureEnabled,
    bool? onboardingComplete,
    List<String>? interests,
    bool? trackSeen,
    bool? loaded,
  }) {
    return AppSettingsState(
      openAiApiKey: openAiApiKey ?? this.openAiApiKey,
      openRouterApiKey: openRouterApiKey ?? this.openRouterApiKey,
      anthropicApiKey: anthropicApiKey ?? this.anthropicApiKey,
      provider: provider ?? this.provider,
      selectedOpenAiModel: selectedOpenAiModel ?? this.selectedOpenAiModel,
      selectedOpenRouterModel:
          selectedOpenRouterModel ?? this.selectedOpenRouterModel,
      selectedAnthropicModel:
          selectedAnthropicModel ?? this.selectedAnthropicModel,
      googleApiKey: googleApiKey ?? this.googleApiKey,
      selectedGeminiModel: selectedGeminiModel ?? this.selectedGeminiModel,
      opencodeGoApiKey: opencodeGoApiKey ?? this.opencodeGoApiKey,
      selectedOpencodeGoModel:
          selectedOpencodeGoModel ?? this.selectedOpencodeGoModel,
      ollamaCloudApiKey: ollamaCloudApiKey ?? this.ollamaCloudApiKey,
      selectedOllamaCloudModel:
          selectedOllamaCloudModel ?? this.selectedOllamaCloudModel,
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
    try {
      final prefs = await SharedPreferences.getInstance();

      // API keys come from secure storage (encrypted).
      final openAiKey = await _secure.read(key: AppConstants.keyOpenAiApiKey);
      final openRouterKey = await _secure.read(
        key: AppConstants.keyOpenRouterApiKey,
      );
      final anthropicKey = await _secure.read(
        key: AppConstants.keyAnthropicApiKey,
      );
      final googleKey = await _secure.read(key: AppConstants.keyGoogleApiKey);
      final opencodeGoKey = await _secure.read(
        key: AppConstants.keyOpencodeGoApiKey,
      );
      final ollamaCloudKey = await _secure.read(
        key: AppConstants.keyOllamaCloudApiKey,
      );

      // Everything else from SharedPreferences.
      final providerStr = prefs.getString(AppConstants.keyProvider);
      final provider = switch (providerStr) {
        'anthropic' => AiProvider.anthropic,
        'gemini' => AiProvider.gemini,
        'openRouter' => AiProvider.openRouter,
        'ollama' => AiProvider.ollama,
        'opencode' || 'opencodeGo' => AiProvider.opencodeGo,
        'ollamaCloud' => AiProvider.ollamaCloud,
        _ => AiProvider.openAi,
      };
      final openAiModel =
          prefs.getString(AppConstants.keySelectedOpenAiModel) ??
          AppConstants.defaultOpenAiModel;
      final openRouterModel =
          prefs.getString(AppConstants.keySelectedOpenRouterModel) ??
          AppConstants.defaultOpenRouterModel;
      final anthropicModel =
          prefs.getString(AppConstants.keySelectedAnthropicModel) ??
          AppConstants.defaultAnthropicModel;
      final geminiModel =
          prefs.getString(AppConstants.keySelectedGeminiModel) ??
          AppConstants.defaultGeminiModel;
      final opencodeGoModel =
          prefs.getString(AppConstants.keySelectedOpencodeGoModel) ??
          AppConstants.defaultOpencodeGoModel;
      final ollamaCloudModel =
          prefs.getString(AppConstants.keySelectedOllamaCloudModel) ??
          AppConstants.defaultOllamaCloudModel;
      final ollamaBaseUrl =
          prefs.getString(AppConstants.keyOllamaBaseUrl) ??
          AppConstants.defaultOllamaBaseUrl;
      final ollamaModel =
          prefs.getString(AppConstants.keySelectedOllamaModel) ??
          AppConstants.defaultOllamaModel;
      final mature = prefs.getBool(AppConstants.keyMatureEnabled) ?? false;
      final onboarding =
          prefs.getBool(AppConstants.keyOnboardingComplete) ?? false;
      final trackSeen = prefs.getBool(AppConstants.keyTrackSeen) ?? true;

      // Interests are stored as a JSON array of strings.
      final interestsJson = prefs.getString('interests');
      final interests = interestsJson != null
          ? List<String>.from(jsonDecode(interestsJson) as List)
          : <String>[];

      state = AppSettingsState(
        openAiApiKey: openAiKey,
        openRouterApiKey: openRouterKey,
        anthropicApiKey: anthropicKey,
        provider: provider,
        selectedOpenAiModel: openAiModel,
        selectedOpenRouterModel: openRouterModel,
        selectedAnthropicModel: anthropicModel,
        googleApiKey: googleKey,
        selectedGeminiModel: geminiModel,
        opencodeGoApiKey: opencodeGoKey,
        selectedOpencodeGoModel: opencodeGoModel,
        ollamaCloudApiKey: ollamaCloudKey,
        selectedOllamaCloudModel: ollamaCloudModel,
        ollamaBaseUrl: ollamaBaseUrl,
        selectedOllamaModel: ollamaModel,
        matureEnabled: mature,
        onboardingComplete: onboarding,
        interests: interests,
        trackSeen: trackSeen,
        loaded: true,
      );
    } catch (_) {
      // Never leave the app stuck on its loading spinner if device storage is
      // corrupt or temporarily unavailable. The user can re-enter settings.
      state = const AppSettingsState(loaded: true);
    }
  }

  // Each setter writes to storage and updates state immediately so the UI
  // reflects the change without waiting for a round-trip read.

  Future<void> setOpenAiApiKey(String key) async {
    await _secure.write(key: AppConstants.keyOpenAiApiKey, value: key);
    state = state.copyWith(openAiApiKey: key);
  }

  Future<void> setOpenRouterApiKey(String key) async {
    await _secure.write(key: AppConstants.keyOpenRouterApiKey, value: key);
    state = state.copyWith(openRouterApiKey: key);
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

  Future<void> setOpenAiModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keySelectedOpenAiModel, model);
    state = state.copyWith(selectedOpenAiModel: model);
  }

  Future<void> setOpenRouterModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keySelectedOpenRouterModel, model);
    state = state.copyWith(selectedOpenRouterModel: model);
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

  Future<void> setOpencodeGoApiKey(String key) async {
    await _secure.write(key: AppConstants.keyOpencodeGoApiKey, value: key);
    state = state.copyWith(opencodeGoApiKey: key);
  }

  Future<void> setOpencodeGoModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keySelectedOpencodeGoModel, model);
    state = state.copyWith(selectedOpencodeGoModel: model);
  }

  Future<void> setOllamaCloudApiKey(String key) async {
    await _secure.write(key: AppConstants.keyOllamaCloudApiKey, value: key);
    state = state.copyWith(ollamaCloudApiKey: key);
  }

  Future<void> setOllamaCloudModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keySelectedOllamaCloudModel, model);
    state = state.copyWith(selectedOllamaCloudModel: model);
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
