import 'package:flutter_test/flutter_test.dart';
import 'package:bokylearn/data/local/app_settings.dart';

void main() {
  test('provider routing uses the active key and model', () {
    AppSettingsState settings(AiProvider provider) => AppSettingsState(
      provider: provider,
      openAiApiKey: 'openai-key',
      selectedOpenAiModel: 'openai-model',
      openRouterApiKey: 'openrouter-key',
      selectedOpenRouterModel: 'openrouter-model',
      anthropicApiKey: 'anthropic-key',
      selectedAnthropicModel: 'anthropic-model',
      googleApiKey: 'gemini-key',
      selectedGeminiModel: 'gemini-model',
      ollamaCloudApiKey: 'ollama-key',
      selectedOllamaCloudModel: 'ollama-model',
      ollamaBaseUrl: 'https://ollama.test',
      selectedOllamaModel: 'local-model',
      opencodeGoApiKey: 'opencode-key',
      selectedOpencodeGoModel: 'opencode-model',
    );

    for (final provider in AiProvider.values) {
      final state = settings(provider);
      expect(state.hasApiKey, isTrue);
      if (provider == AiProvider.ollama) {
        expect(state.activeApiKey, isEmpty);
      } else {
        expect(state.activeApiKey, contains('-key'));
      }
      expect(state.activeModel, contains('-model'));
    }
  });
}
