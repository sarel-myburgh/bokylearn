import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants.dart';
import '../../data/local/app_settings.dart';

const _suggestedTopics = [
  'Animals', 'Space', 'History', 'Science', 'Technology',
  'Food', 'Movies & TV', 'Music', 'Psychology', 'Health',
  'Art', 'Economics',
];

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = TextEditingController();
  final List<String> _interests = [];

  void _addInterest([String? text]) {
    final value = (text ?? _controller.text).trim();
    if (value.isEmpty || _interests.contains(value)) return;
    setState(() => _interests.add(value));
    if (text == null) _controller.clear();
  }

  void _removeInterest(String interest) {
    setState(() => _interests.remove(interest));
  }

  Future<void> _finish() async {
    await ref.read(appSettingsProvider.notifier).completeOnboarding(_interests);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
              // Logo + title
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
                'Tell us your interests and we\'ll tailor your feed. Be as specific as you like.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cream.withValues(alpha: 0.6),
                ),
              ),

              const SizedBox(height: 20),

              // Quick-tap topic suggestions
              Text(
                'Quick picks',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cream.withValues(alpha: 0.5),
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _suggestedTopics.map((topic) {
                  final selected = _interests.contains(topic);
                  return FilterChip(
                    label: Text(topic),
                    selected: selected,
                    onSelected: (_) => selected
                        ? _removeInterest(topic)
                        : _addInterest(topic),
                    selectedColor: orange,
                    checkmarkColor: cream,
                    labelStyle: TextStyle(
                      color: selected ? cream : cream.withValues(alpha: 0.8),
                    ),
                    backgroundColor: dark.withValues(alpha: 0.0),
                    side: BorderSide(
                      color: selected ? orange : cream.withValues(alpha: 0.3),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 24),

              // Custom interest input
              Text(
                'Or type your own',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cream.withValues(alpha: 0.5),
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      style: const TextStyle(color: cream),
                      cursorColor: orange,
                      decoration: InputDecoration(
                        hintText: 'e.g. Roman history, Pokemon TV show',
                        hintStyle: TextStyle(color: cream.withValues(alpha: 0.35)),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: cream.withValues(alpha: 0.3)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: orange),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onSubmitted: (_) => _addInterest(),
                      textInputAction: TextInputAction.done,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: orange,
                      foregroundColor: cream,
                    ),
                    onPressed: _addInterest,
                    child: const Text('Add'),
                  ),
                ],
              ),

              if (_interests.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _interests
                      .where((i) => !_suggestedTopics.contains(i))
                      .map((interest) => InputChip(
                            label: Text(interest,
                                style: const TextStyle(color: cream)),
                            backgroundColor: orange.withValues(alpha: 0.2),
                            side: const BorderSide(color: orange),
                            deleteIconColor: cream.withValues(alpha: 0.7),
                            onDeleted: () => _removeInterest(interest),
                          ))
                      .toList(),
                ),
              ],

              const SizedBox(height: 36),

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
                  child: const Text('Start learning'),
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
