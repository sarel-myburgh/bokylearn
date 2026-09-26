import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../core/constants.dart';
import '../../data/local/app_settings.dart';

class TagCategory {
  final String group;
  final List<String> tags;

  const TagCategory({required this.group, required this.tags});
}

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  List<TagCategory> _categories = [];
  bool _loading = true;
  final Set<String> _selectedTags = {};

  @override
  void initState() {
    super.initState();
    _fetchTags();
  }

  Future<void> _fetchTags() async {
    try {
      final response = await http.get(Uri.parse(AppConstants.tagsJsonUrl));
      if (response.statusCode != 200) {
        setState(() => _loading = false);
        return;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final raw = (data['categories'] as List<dynamic>).cast<Map<String, dynamic>>();
      final cats = raw.map((c) => TagCategory(
        group: c['group'] as String,
        tags: (c['tags'] as List<dynamic>).cast<String>(),
      )).toList();
      setState(() { _categories = cats; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  void _toggleTag(String tag) {
    setState(() {
      if (_selectedTags.contains(tag)) {
        _selectedTags.remove(tag);
      } else {
        _selectedTags.add(tag);
      }
    });
  }

  Future<void> _finish() async {
    await ref.read(appSettingsProvider.notifier).completeOnboarding(_selectedTags.toList());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const cream = BokyPalette.cardBackground;
    const dark = Color(0xFF30362F);
    const orange = Color(0xFFDA7422);

    return Scaffold(
      backgroundColor: dark,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Column(
                  children: [
                    Image.asset('assets/images/bokylearnlogo.png', height: 72),
                    const SizedBox(height: 12),
                    Text(
                      'BokyLearn',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: cream,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Down the rabbit hole 🐇',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cream.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 36),

              Text(
                'What are you curious about?',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: cream,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Pick topics you like. We\'ll tailor your feed.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cream.withValues(alpha: 0.6),
                ),
              ),

              const SizedBox(height: 24),

              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(48),
                    child: CircularProgressIndicator(color: orange),
                  ),
                )
              else ...[
                for (final cat in _categories) ...[
                  Text(
                    cat.group,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: orange,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: cat.tags.map((tag) {
                      final selected = _selectedTags.contains(tag);
                      return FilterChip(
                        label: Text(tag),
                        selected: selected,
                        onSelected: (_) => _toggleTag(tag),
                        selectedColor: orange,
                        checkmarkColor: cream,
                        labelStyle: TextStyle(
                          color: selected ? cream : cream.withValues(alpha: 0.8),
                          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                        ),
                        backgroundColor: dark.withValues(alpha: 0.0),
                        side: const BorderSide(color: orange),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                ],
              ],

              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: orange,
                    foregroundColor: cream,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: _finish,
                  child: Text(
                    _selectedTags.isEmpty ? 'Start learning' : 'Start learning (${_selectedTags.length} selected)',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _finish,
                  child: Text(
                    'Skip for now',
                    style: TextStyle(color: cream.withValues(alpha: 0.4)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
