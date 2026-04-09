// ─────────────────────────────────────────────────────────────────────────────
// router.dart — Declarative navigation configuration (go_router)
//
// Defines every named route in the app. AppShell (at '/') acts as the root
// and decides which screen to show based on app state (no API key, onboarding,
// or the feed). Settings is a separate push route so the back button works.
//
// The ExpansionScreen is NOT declared here — it uses imperative
// Navigator.push() so it can be stacked arbitrarily deep (rabbit hole
// navigation). go_router handles named routes; Navigator handles the stack.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:go_router/go_router.dart';
import 'app_shell.dart';
import '../features/settings/settings_screen.dart';

class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: [
      // Root route — AppShell reads settings and renders the correct screen.
      GoRoute(
        path: '/',
        builder: (context, state) => const AppShell(),
      ),

      // Settings is a separate named route so it can be pushed from anywhere
      // with context.push('/settings') and popped with the back button.
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
}
