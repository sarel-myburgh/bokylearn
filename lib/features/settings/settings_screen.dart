import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/constants.dart';
import '../../data/local/app_settings.dart';
import '../../data/remote/model_client.dart';

class TagCategory {
  final String group;
  final List<String> tags;

  const TagCategory({required this.group, required this.tags});
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _openAiController = TextEditingController();
  final _openRouterController = TextEditingController();
  final _anthropicController = TextEditingController();
  final _geminiController = TextEditingController();
  final _ollamaCloudController = TextEditingController();
  final _opencodeGoController = TextEditingController();
  final _ollamaController = TextEditingController();

  final Map<AiProvider, List<ModelInfo>> _models = {};
  final Map<AiProvider, bool> _loadingModels = {};
  final Map<AiProvider, String?> _modelErrors = {};
  final Map<AiProvider, bool> _keyObscured = {
    for (final provider in AiProvider.values) provider: true,
  };

  late List<String> _interests;
  List<TagCategory> _categories = [];
  bool _loadingTags = true;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(appSettingsProvider);
    _openAiController.text = settings.openAiApiKey ?? '';
    _openRouterController.text = settings.openRouterApiKey ?? '';
    _anthropicController.text = settings.anthropicApiKey ?? '';
    _geminiController.text = settings.googleApiKey ?? '';
    _ollamaCloudController.text = settings.ollamaCloudApiKey ?? '';
    _opencodeGoController.text = settings.opencodeGoApiKey ?? '';
    _ollamaController.text = settings.ollamaBaseUrl;
    _interests = List.of(settings.interests);
    _fetchTags();
  }

  @override
  void dispose() {
    _openAiController.dispose();
    _openRouterController.dispose();
    _anthropicController.dispose();
    _geminiController.dispose();
    _ollamaCloudController.dispose();
    _opencodeGoController.dispose();
    _ollamaController.dispose();
    super.dispose();
  }

  Future<void> _fetchTags() async {
    try {
      final response = await http
          .get(Uri.parse(AppConstants.tagsJsonUrl))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Tag request failed (${response.statusCode})');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final raw = data['categories'] as List<dynamic>? ?? const [];
      final categories = raw.map((item) {
        final category = item as Map<String, dynamic>;
        return TagCategory(
          group: category['group'] as String,
          tags: (category['tags'] as List<dynamic>).cast<String>(),
        );
      }).toList();
      if (mounted) {
        setState(() {
          _categories = categories;
          _loadingTags = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingTags = false);
    }
  }

  TextEditingController _controllerFor(AiProvider provider) =>
      switch (provider) {
        AiProvider.openAi => _openAiController,
        AiProvider.openRouter => _openRouterController,
        AiProvider.anthropic => _anthropicController,
        AiProvider.gemini => _geminiController,
        AiProvider.ollamaCloud => _ollamaCloudController,
        AiProvider.opencodeGo => _opencodeGoController,
        AiProvider.ollama => _ollamaController,
      };

  String _providerName(AiProvider provider) => switch (provider) {
    AiProvider.openAi => 'OpenAI',
    AiProvider.openRouter => 'OpenRouter',
    AiProvider.anthropic => 'Anthropic',
    AiProvider.gemini => 'Google Gemini',
    AiProvider.ollamaCloud => 'Ollama Cloud',
    AiProvider.opencodeGo => 'OpenCode Go',
    AiProvider.ollama => 'Ollama Local',
  };

  String _providerDescription(AiProvider provider) => switch (provider) {
    AiProvider.openAi => 'Uses your OpenAI Platform API account and billing.',
    AiProvider.openRouter => 'Uses your OpenRouter API key and model catalog.',
    AiProvider.anthropic => 'Uses your Anthropic Console API account.',
    AiProvider.gemini => 'Uses a Google AI Studio Gemini API key.',
    AiProvider.ollamaCloud => 'Uses an Ollama Cloud API key from ollama.com.',
    AiProvider.opencodeGo => 'Uses an active OpenCode Go subscription key.',
    AiProvider.ollama => 'Connects directly to an Ollama server you control.',
  };

  String _keyHint(AiProvider provider) => switch (provider) {
    AiProvider.openAi => 'sk-...',
    AiProvider.openRouter => 'sk-or-...',
    AiProvider.anthropic => 'sk-ant-...',
    AiProvider.gemini => 'AIza...',
    AiProvider.ollamaCloud => 'Ollama API key',
    AiProvider.opencodeGo => 'OpenCode Go API key',
    AiProvider.ollama => 'http://192.168.1.10:11434',
  };

  String _defaultModel(AiProvider provider) => switch (provider) {
    AiProvider.openAi => AppConstants.defaultOpenAiModel,
    AiProvider.openRouter => AppConstants.defaultOpenRouterModel,
    AiProvider.anthropic => AppConstants.defaultAnthropicModel,
    AiProvider.gemini => AppConstants.defaultGeminiModel,
    AiProvider.ollamaCloud => AppConstants.defaultOllamaCloudModel,
    AiProvider.opencodeGo => AppConstants.defaultOpencodeGoModel,
    AiProvider.ollama => AppConstants.defaultOllamaModel,
  };

  String _selectedModel(AppSettingsState settings, AiProvider provider) =>
      switch (provider) {
        AiProvider.openAi => settings.selectedOpenAiModel,
        AiProvider.openRouter => settings.selectedOpenRouterModel,
        AiProvider.anthropic => settings.selectedAnthropicModel,
        AiProvider.gemini => settings.selectedGeminiModel,
        AiProvider.ollamaCloud => settings.selectedOllamaCloudModel,
        AiProvider.opencodeGo => settings.selectedOpencodeGoModel,
        AiProvider.ollama => settings.selectedOllamaModel,
      };

  String? _savedKey(AppSettingsState settings, AiProvider provider) =>
      switch (provider) {
        AiProvider.openAi => settings.openAiApiKey,
        AiProvider.openRouter => settings.openRouterApiKey,
        AiProvider.anthropic => settings.anthropicApiKey,
        AiProvider.gemini => settings.googleApiKey,
        AiProvider.ollamaCloud => settings.ollamaCloudApiKey,
        AiProvider.opencodeGo => settings.opencodeGoApiKey,
        AiProvider.ollama => settings.ollamaBaseUrl,
      };

  Future<void> _saveKey(AiProvider provider) async {
    final key = _controllerFor(provider).text.trim();
    if (key.isEmpty) return;
    if (provider == AiProvider.ollama) {
      final uri = Uri.tryParse(key);
      if (uri == null ||
          (uri.scheme != 'http' && uri.scheme != 'https') ||
          uri.host.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enter a complete http:// or https:// server URL.'),
          ),
        );
        return;
      }
    }
    final notifier = ref.read(appSettingsProvider.notifier);
    switch (provider) {
      case AiProvider.openAi:
        await notifier.setOpenAiApiKey(key);
      case AiProvider.openRouter:
        await notifier.setOpenRouterApiKey(key);
      case AiProvider.anthropic:
        await notifier.setAnthropicApiKey(key);
      case AiProvider.gemini:
        await notifier.setGoogleApiKey(key);
      case AiProvider.ollamaCloud:
        await notifier.setOllamaCloudApiKey(key);
      case AiProvider.opencodeGo:
        await notifier.setOpencodeGoApiKey(key);
      case AiProvider.ollama:
        await notifier.setOllamaBaseUrl(key.replaceFirst(RegExp(r'/+$'), ''));
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          provider == AiProvider.ollama
              ? 'Ollama server saved'
              : '${_providerName(provider)} key saved',
        ),
      ),
    );
    await _fetchModels(provider, key);
  }

  Future<void> _fetchModels(AiProvider provider, String key) async {
    setState(() {
      _loadingModels[provider] = true;
      _modelErrors[provider] = null;
    });
    try {
      final models = switch (provider) {
        AiProvider.openAi => await ModelClient.fetchOpenAiModels(key),
        AiProvider.openRouter => await ModelClient.fetchOpenRouterModels(key),
        AiProvider.anthropic => await ModelClient.fetchAnthropicModels(key),
        AiProvider.gemini => await ModelClient.fetchGeminiModels(key),
        AiProvider.ollamaCloud => await ModelClient.fetchOllamaCloudModels(key),
        AiProvider.opencodeGo => await ModelClient.fetchOpencodeGoModels(key),
        AiProvider.ollama => await ModelClient.fetchOllamaModels(key),
      };
      if (models.isEmpty) throw Exception('No compatible models returned');
      if (!mounted) return;
      setState(() {
        _models[provider] = models;
        _loadingModels[provider] = false;
      });
      final settings = ref.read(appSettingsProvider);
      final selected = _selectedModel(settings, provider);
      if (!models.any((model) => model.id == selected)) {
        final preferred =
            models.any((model) => model.id == _defaultModel(provider))
            ? _defaultModel(provider)
            : models.first.id;
        await _selectModel(provider, preferred);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingModels[provider] = false;
        _modelErrors[provider] =
            'Could not load models. Check the key and subscription.';
      });
    }
  }

  Future<void> _selectModel(AiProvider provider, String model) async {
    final notifier = ref.read(appSettingsProvider.notifier);
    switch (provider) {
      case AiProvider.openAi:
        await notifier.setOpenAiModel(model);
      case AiProvider.openRouter:
        await notifier.setOpenRouterModel(model);
      case AiProvider.anthropic:
        await notifier.setAnthropicModel(model);
      case AiProvider.gemini:
        await notifier.setGeminiModel(model);
      case AiProvider.ollamaCloud:
        await notifier.setOllamaCloudModel(model);
      case AiProvider.opencodeGo:
        await notifier.setOpencodeGoModel(model);
      case AiProvider.ollama:
        await notifier.setOllamaModel(model);
    }
  }

  void _addInterest(String value) {
    final interest = value.trim();
    if (interest.isEmpty || _interests.contains(interest)) return;
    setState(() => _interests.add(interest));
    ref.read(appSettingsProvider.notifier).updateInterests(_interests);
  }

  void _removeInterest(String interest) {
    setState(() => _interests.remove(interest));
    ref.read(appSettingsProvider.notifier).updateInterests(_interests);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final provider = settings.provider;
    final savedKey = _savedKey(settings, provider);
    final models = _models[provider] ?? const <ModelInfo>[];
    final selected = _selectedModel(settings, provider);
    final dropdownValue = models.any((model) => model.id == selected)
        ? selected
        : null;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('AI provider', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          DropdownButtonFormField<AiProvider>(
            initialValue: provider,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: AiProvider.values
                .map(
                  (item) => DropdownMenuItem(
                    value: item,
                    child: Text(_providerName(item)),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                ref.read(appSettingsProvider.notifier).setProvider(value);
              }
            },
          ),
          const SizedBox(height: 8),
          Text(
            _providerDescription(provider),
            style: theme.textTheme.bodySmall,
          ),
          if (provider == AiProvider.ollama) ...[
            const SizedBox(height: 4),
            Text(
              'Use HTTPS on mobile. Plain HTTP may be blocked by Android or iOS.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            provider == AiProvider.ollama
                ? 'Ollama server URL'
                : '${_providerName(provider)} API key',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controllerFor(provider),
                  obscureText:
                      provider != AiProvider.ollama &&
                      (_keyObscured[provider] ?? true),
                  keyboardType: provider == AiProvider.ollama
                      ? TextInputType.url
                      : TextInputType.text,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    hintText: _keyHint(provider),
                    border: const OutlineInputBorder(),
                    suffixIcon: provider == AiProvider.ollama
                        ? null
                        : IconButton(
                            onPressed: () => setState(() {
                              _keyObscured[provider] =
                                  !(_keyObscured[provider] ?? true);
                            }),
                            icon: Icon(
                              (_keyObscured[provider] ?? true)
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => _saveKey(provider),
                child: const Text('Save'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Available models',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (_loadingModels[provider] == true)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  tooltip: 'Refresh models',
                  onPressed: savedKey?.isNotEmpty == true
                      ? () => _fetchModels(provider, savedKey!)
                      : null,
                  icon: const Icon(Icons.refresh),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Default: ${_defaultModel(provider)}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (savedKey?.isNotEmpty != true)
            Text(
              provider == AiProvider.ollama
                  ? 'Save a server URL to load its installed models.'
                  : 'Save an API key to load the models available to it.',
            )
          else if (models.isEmpty && _loadingModels[provider] != true)
            OutlinedButton.icon(
              onPressed: () => _fetchModels(provider, savedKey!),
              icon: const Icon(Icons.cloud_download),
              label: const Text('Load available models'),
            )
          else if (models.isNotEmpty)
            DropdownButtonFormField<String>(
              key: ValueKey(provider),
              initialValue: dropdownValue,
              isExpanded: true,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              hint: const Text('Choose a model'),
              items: models
                  .map(
                    (model) => DropdownMenuItem(
                      value: model.id,
                      child: Text(model.name, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) _selectModel(provider, value);
              },
            ),
          if (_modelErrors[provider] case final error?) ...[
            const SizedBox(height: 6),
            Text(
              error,
              style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
            ),
          ],
          const SizedBox(height: 24),
          const Divider(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show mature content'),
            subtitle: const Text('Includes sexual and adult facts'),
            value: settings.matureEnabled,
            onChanged: ref.read(appSettingsProvider.notifier).setMatureEnabled,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Track seen facts'),
            subtitle: const Text('Hide viewed facts for 14 days'),
            value: settings.trackSeen,
            onChanged: ref.read(appSettingsProvider.notifier).setTrackSeen,
          ),
          const Divider(),
          const SizedBox(height: 12),
          Text('Interests', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_loadingTags)
            const Center(child: CircularProgressIndicator())
          else ...[
            for (final category in _categories) ...[
              Text(
                category.group,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: category.tags.map((tag) {
                  final selected = _interests.contains(tag);
                  return FilterChip(
                    label: Text(tag),
                    selected: selected,
                    onSelected: (_) =>
                        selected ? _removeInterest(tag) : _addInterest(tag),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
            ],
          ],
          if (_interests.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _interests
                  .map(
                    (interest) => InputChip(
                      label: Text(interest),
                      onDeleted: () => _removeInterest(interest),
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
