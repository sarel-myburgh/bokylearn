// ─────────────────────────────────────────────────────────────────────────────
// settings_screen.dart — User preferences and API key configuration
//
// Sections (top to bottom):
//   1. AI Provider dropdown (OpenRouter / Anthropic / Google AI Studio / Ollama)
//   2. API key / URL field — only the field for the selected provider is shown.
//   3. Model selector — OpenRouter: searchable list; others: fixed dropdown.
//   4. Mature content toggle.
//   5. Track seen facts toggle.
//   6. Interests — autocomplete from DB tags; deletable chips.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/local/app_settings.dart';
import '../../data/local/facts_db.dart';
import '../../data/remote/openrouter_client.dart';
import '../../core/constants.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // ── Key / URL controllers (one per provider) ────────────────────────────────
  final _orKeyController       = TextEditingController(); // OpenRouter
  final _anthropicKeyController = TextEditingController(); // Anthropic
  final _googleKeyController   = TextEditingController(); // Gemini
  final _ollamaUrlController   = TextEditingController(); // Ollama base URL
  final _ollamaModelController = TextEditingController(); // Ollama model name

  // ── OpenRouter model search ──────────────────────────────────────────────────
  final _modelController = TextEditingController();
  List<OpenRouterModel> _models = [];
  List<OpenRouterModel> _filteredModels = [];
  bool _loadingModels = false;
  String? _modelError;

  // ── Key visibility toggles ──────────────────────────────────────────────────
  bool _orKeyObscured       = true;
  bool _anthropicKeyObscured = true;
  bool _googleKeyObscured   = true;

  // ── Interests ───────────────────────────────────────────────────────────────
  late List<String> _interests;
  late List<String> _allTags; // autocomplete source from DB

  @override
  void initState() {
    super.initState();
    final settings = ref.read(appSettingsProvider);
    _orKeyController.text        = settings.apiKey ?? '';
    _anthropicKeyController.text = settings.anthropicApiKey ?? '';
    _googleKeyController.text    = settings.googleApiKey ?? '';
    _ollamaUrlController.text    = settings.ollamaBaseUrl;
    _ollamaModelController.text  = settings.selectedOllamaModel;
    _modelController.text        = settings.selectedModel;
    _interests = List.from(settings.interests);
    _allTags   = FactsDb.allTags..sort();
    _modelController.addListener(_filterModels);
  }

  @override
  void dispose() {
    _orKeyController.dispose();
    _anthropicKeyController.dispose();
    _googleKeyController.dispose();
    _ollamaUrlController.dispose();
    _ollamaModelController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  // ── Interests ────────────────────────────────────────────────────────────────

  void _addInterest(String text) {
    final t = text.trim();
    if (t.isEmpty || _interests.contains(t)) return;
    setState(() => _interests.add(t));
    ref.read(appSettingsProvider.notifier).updateInterests(_interests);
  }

  void _removeInterest(String interest) {
    setState(() => _interests.remove(interest));
    ref.read(appSettingsProvider.notifier).updateInterests(_interests);
  }

  // ── OpenRouter model search ──────────────────────────────────────────────────

  void _filterModels() {
    final query = _modelController.text.toLowerCase();
    setState(() {
      _filteredModels = _models
          .where((m) => m.id.toLowerCase().contains(query) || m.name.toLowerCase().contains(query))
          .take(8)
          .toList();
    });
  }

  Future<void> _fetchModels(String key) async {
    setState(() { _loadingModels = true; _modelError = null; });
    try {
      final models = await OpenRouterClient.fetchModels(key);
      setState(() {
        _models = models;
        _filteredModels = models.take(8).toList();
        _loadingModels = false;
      });
    } catch (_) {
      setState(() {
        _modelError = 'Could not load models. Check your API key.';
        _loadingModels = false;
      });
    }
  }

  Future<void> _selectModel(OpenRouterModel model) async {
    _modelController.text = model.id;
    final focusScope = FocusScope.of(context);
    await ref.read(appSettingsProvider.notifier).setModel(model.id);
    if (!mounted) return;
    setState(() => _filteredModels = []);
    focusScope.unfocus();
  }

  // ── Key save helpers ─────────────────────────────────────────────────────────

  Future<void> _saveOrKey() async {
    final key = _orKeyController.text.trim();
    if (key.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(appSettingsProvider.notifier).setApiKey(key);
    if (!mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('OpenRouter key saved')));
    _fetchModels(key);
  }

  Future<void> _saveAnthropicKey() async {
    final key = _anthropicKeyController.text.trim();
    if (key.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(appSettingsProvider.notifier).setAnthropicApiKey(key);
    if (!mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('Anthropic key saved')));
  }

  Future<void> _saveGoogleKey() async {
    final key = _googleKeyController.text.trim();
    if (key.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(appSettingsProvider.notifier).setGoogleApiKey(key);
    if (!mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('Google AI Studio key saved')));
  }

  Future<void> _saveOllamaSettings() async {
    final url   = _ollamaUrlController.text.trim();
    final model = _ollamaModelController.text.trim();
    final notifier = ref.read(appSettingsProvider.notifier);
    if (url.isNotEmpty)   await notifier.setOllamaBaseUrl(url);
    if (model.isNotEmpty) await notifier.setOllamaModel(model);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ollama settings saved')),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final theme    = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // ── AI Provider ────────────────────────────────────────────────────
          Text('AI Provider', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          DropdownButtonFormField<AiProvider>(
            initialValue: settings.provider,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: AiProvider.openRouter, child: Text('OpenRouter')),
              DropdownMenuItem(value: AiProvider.anthropic,  child: Text('Anthropic')),
              DropdownMenuItem(value: AiProvider.gemini,     child: Text('Google AI Studio (Gemini)')),
              DropdownMenuItem(value: AiProvider.ollama,     child: Text('Ollama (local)')),
            ],
            onChanged: (p) {
              if (p != null) ref.read(appSettingsProvider.notifier).setProvider(p);
            },
          ),

          const SizedBox(height: 24),

          // ── Provider-specific key / URL field ──────────────────────────────
          if (settings.provider == AiProvider.openRouter) ...[
            _buildSectionLabel('OpenRouter API Key', 'Get a free key at openrouter.ai'),
            const SizedBox(height: 8),
            _buildKeyRow(_orKeyController, 'sk-or-...', _orKeyObscured,
              () => setState(() => _orKeyObscured = !_orKeyObscured),
              _saveOrKey,
            ),
          ],

          if (settings.provider == AiProvider.anthropic) ...[
            _buildSectionLabel('Anthropic API Key', 'Direct API — faster than OpenRouter for Claude models.'),
            const SizedBox(height: 8),
            _buildKeyRow(_anthropicKeyController, 'sk-ant-...', _anthropicKeyObscured,
              () => setState(() => _anthropicKeyObscured = !_anthropicKeyObscured),
              _saveAnthropicKey,
            ),
          ],

          if (settings.provider == AiProvider.gemini) ...[
            _buildSectionLabel('Google AI Studio API Key', 'Get a free key at aistudio.google.com'),
            const SizedBox(height: 8),
            _buildKeyRow(_googleKeyController, 'AIza...', _googleKeyObscured,
              () => setState(() => _googleKeyObscured = !_googleKeyObscured),
              _saveGoogleKey,
            ),
          ],

          if (settings.provider == AiProvider.ollama) ...[
            _buildSectionLabel('Ollama (local)', 'Make sure Ollama is running on your device.'),
            const SizedBox(height: 8),
            TextField(
              controller: _ollamaUrlController,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                hintText: 'http://localhost:11434',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _ollamaModelController,
              decoration: const InputDecoration(
                labelText: 'Model name',
                hintText: 'llama3.2',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(onPressed: _saveOllamaSettings, child: const Text('Save')),
            ),
          ],

          const SizedBox(height: 24),

          // ── Model selector ─────────────────────────────────────────────────
          // OpenRouter: searchable live list.
          // Anthropic: fixed dropdown (haiku / sonnet / opus).
          // Gemini: fixed dropdown.
          // Ollama: handled in the URL/model block above.
          if (settings.provider == AiProvider.openRouter) ...[
            Text('Model', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Default: ${AppConstants.defaultModel}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 8),
            if (settings.apiKey == null || settings.apiKey!.isEmpty)
              Text(
                'Save an OpenRouter key first to load available models.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              )
            else ...[
              TextField(
                controller: _modelController,
                decoration: InputDecoration(
                  hintText: 'Search models...',
                  border: const OutlineInputBorder(),
                  suffixIcon: _loadingModels
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : _models.isEmpty
                          ? IconButton(
                              icon: const Icon(Icons.refresh),
                              onPressed: () => _fetchModels(settings.apiKey!),
                            )
                          : null,
                ),
                onTap: () {
                  if (_models.isEmpty && !_loadingModels) {
                    _fetchModels(settings.apiKey!);
                  } else {
                    _filterModels();
                  }
                },
              ),
              if (_modelError != null) ...[
                const SizedBox(height: 4),
                Text(_modelError!, style: TextStyle(color: theme.colorScheme.error, fontSize: 12)),
              ],
              if (_filteredModels.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outline),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: _filteredModels.map((model) => ListTile(
                      dense: true,
                      title: Text(model.name, style: theme.textTheme.bodyMedium),
                      subtitle: Text(model.id, style: theme.textTheme.bodySmall),
                      onTap: () => _selectModel(model),
                    )).toList(),
                  ),
                ),
            ],
            const SizedBox(height: 24),
          ],

          if (settings.provider == AiProvider.anthropic) ...[
            Text('Model', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            InputDecorator(
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
              child: DropdownButton<String>(
                value: settings.selectedAnthropicModel,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                items: AppConstants.anthropicModels
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (m) {
                  if (m != null) ref.read(appSettingsProvider.notifier).setAnthropicModel(m);
                },
              ),
            ),
            const SizedBox(height: 24),
          ],

          if (settings.provider == AiProvider.gemini) ...[
            Text('Model', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            InputDecorator(
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
              child: DropdownButton<String>(
                value: settings.selectedGeminiModel,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                items: AppConstants.geminiModels
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (m) {
                  if (m != null) ref.read(appSettingsProvider.notifier).setGeminiModel(m);
                },
              ),
            ),
            const SizedBox(height: 24),
          ],

          // ── Mature content toggle ──────────────────────────────────────────
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show mature content'),
            subtitle: const Text('Includes sexual and adult facts'),
            value: settings.matureEnabled,
            onChanged: (val) => ref.read(appSettingsProvider.notifier).setMatureEnabled(val),
          ),

          // ── Track seen facts toggle ────────────────────────────────────────
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Track seen facts'),
            subtitle: const Text("Seen facts won't appear again for 2 weeks"),
            value: settings.trackSeen,
            onChanged: (val) => ref.read(appSettingsProvider.notifier).setTrackSeen(val),
          ),

          const SizedBox(height: 24),

          // ── Interests ─────────────────────────────────────────────────────
          Text('Interests', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _InterestAutocomplete(
            allTags: _allTags,
            onAdd: _addInterest,
          ),
          const SizedBox(height: 12),
          if (_interests.isEmpty)
            Text(
              'No interests added — showing all facts.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _interests
                  .map((i) => InputChip(
                        label: Text(i),
                        onDeleted: () => _removeInterest(i),
                      ))
                  .toList(),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  Widget _buildSectionLabel(String title, String subtitle) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  Widget _buildKeyRow(
    TextEditingController controller,
    String hint,
    bool obscured,
    VoidCallback toggleObscure,
    VoidCallback onSave,
  ) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            obscureText: obscured,
            decoration: InputDecoration(
              hintText: hint,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(obscured ? Icons.visibility : Icons.visibility_off),
                onPressed: toggleObscure,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(onPressed: onSave, child: const Text('Save')),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _InterestAutocomplete — text field with tag autocomplete suggestions
// ─────────────────────────────────────────────────────────────────────────────
class _InterestAutocomplete extends StatelessWidget {
  final List<String> allTags;
  final void Function(String) onAdd;

  const _InterestAutocomplete({required this.allTags, required this.onAdd});

  String? _matchTag(String text) {
    final lower = text.trim().toLowerCase();
    if (lower.isEmpty) return null;
    try {
      return allTags.firstWhere((t) => t.toLowerCase() == lower);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      optionsBuilder: (textEditingValue) {
        final query = textEditingValue.text.trim().toLowerCase();
        if (query.isEmpty) return const [];
        return allTags
            .where((tag) => tag.toLowerCase().contains(query))
            .take(8);
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                decoration: const InputDecoration(
                  hintText: 'Add an interest...',
                  helperText: 'Pick a tag from the suggestions',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (value) {
                  final tag = _matchTag(value);
                  if (tag != null) {
                    onAdd(tag);
                    controller.clear();
                  }
                },
                textInputAction: TextInputAction.done,
              ),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final tag = _matchTag(value.text);
                return FilledButton(
                  onPressed: tag != null
                      ? () {
                          onAdd(tag);
                          controller.clear();
                          FocusScope.of(context).unfocus();
                        }
                      : null,
                  child: const Text('Add'),
                );
              },
            ),
          ],
        );
      },
      onSelected: (tag) => onAdd(tag),
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320, maxHeight: 280),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final tag = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    title: Text(tag),
                    onTap: () => onSelected(tag),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
