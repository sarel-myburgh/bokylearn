// ─────────────────────────────────────────────────────────────────────────────
// app_shell.dart — Root widget that gates access based on app state
//
// This widget is the first thing rendered after the splash. It reads the
// persisted settings and routes the user to the correct screen:
//
//   1. Settings not loaded yet      → loading spinner (avoids flash of wrong screen)
//   2. No API key configured        → NoApiKeyScreen (prompt to add a key)
//   3. Onboarding not complete      → OnboardingScreen (interest selection)
//   4. Everything ready             → FeedScreen (main experience)
//
// Because it watches appSettingsProvider, it automatically re-renders when
// any setting changes — e.g. after the user saves an API key in Settings, the
// shell transitions to onboarding without any manual navigation call.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/local/app_settings.dart';
import '../features/feed/feed_screen.dart';
import '../features/no_api_key/no_api_key_screen.dart';
import '../features/onboarding/onboarding_screen.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the full settings state. Any change (API key, onboarding flag,
    // provider switch) causes this widget to rebuild and re-evaluate the gate.
    final settings = ref.watch(appSettingsProvider);

    // Settings are loaded asynchronously from SharedPreferences/SecureStorage
    // on startup. Show a spinner until the load completes to avoid briefly
    // rendering the wrong screen (e.g. NoApiKeyScreen when a key exists).
    if (!settings.loaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // No API key means the user can't make AI calls — block access to the feed.
    // hasApiKey checks whichever provider is currently selected.
    if (!settings.hasApiKey) {
      return const NoApiKeyScreen();
    }

    // First launch after adding a key: show interest selection so the feed can
    // be personalised. The user can also skip this.
    if (!settings.onboardingComplete) {
      return const OnboardingScreen();
    }

    // All gates passed — show the main feed.
    return const FeedScreen();
  }
}
