import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants.dart';

class NoApiKeyScreen extends StatelessWidget {
  const NoApiKeyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const cream = BokyPalette.cardBackground;
    const dark = Color(0xFF30362F);
    const orange = Color(0xFFDA7422);

    return Scaffold(
      backgroundColor: dark,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            children: [
              const Spacer(),

              // Logo + branding
              Image.asset('assets/images/bokylearnlogo.png', height: 88),
              const SizedBox(height: 20),
              Text(
                'BokyLearn',
                style: theme.textTheme.headlineLarge?.copyWith(
                  color: cream,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Down the rabbit hole 🐇',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: cream.withValues(alpha: 0.5),
                ),
              ),

              const SizedBox(height: 32),

              Text(
                'Replace doomscrolling with curiosity-driven learning.',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: cream.withValues(alpha: 0.85),
                  height: 1.4,
                ),
              ),

              const Spacer(),

              // Setup instructions
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cream.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cream.withValues(alpha: 0.12)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'To get started',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: cream,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Configure OpenAI, OpenRouter, Anthropic, Gemini, Ollama Cloud, Ollama Local, or OpenCode Go in Settings.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cream.withValues(alpha: 0.6),
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: orange,
                    foregroundColor: cream,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: () => context.push('/settings'),
                  icon: const Icon(Icons.settings),
                  label: const Text('Open Settings'),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
