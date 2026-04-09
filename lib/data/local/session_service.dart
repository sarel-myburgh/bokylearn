// ─────────────────────────────────────────────────────────────────────────────
// session_service.dart — Persists and restores the navigation stack
//
// When the user dives into a rabbit hole (fact → follow-up → follow-up → …),
// each ExpansionScreen pushes a SessionEntry onto the stack in its initState
// and pops it in its dispose. The stack is persisted to SharedPreferences on
// every change so the app can restore it after being killed.
//
// On next launch, the feed screen reads the saved stack and offers a
// "Pick up where you left off" banner. Tapping it re-pushes all the screens
// in order — each initState then rebuilds the in-memory stack naturally.
//
// All methods are static — SessionService is a namespace, not an instance.
//
// Stack discipline:
//   push()          — called by ExpansionScreen.initState()
//   pop()           — called by ExpansionScreen.dispose()
//   clear()         — called when navigating home (popUntil isFirst)
//   clearInMemory() — called just before session restore so each initState
//                     can rebuild the stack from scratch without fighting the
//                     stale in-memory copy
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SessionEntry — One level of the rabbit-hole navigation stack.
//
// factId is always the *root* fact (the one tapped in the feed) — it is
// passed down unchanged through all follow-up screens. questionAsked and
// priorQuestions are null/empty on the root screen and populated on follow-ups.
// ─────────────────────────────────────────────────────────────────────────────
class SessionEntry {
  final String factId;
  final String? questionAsked;
  final List<String> priorQuestions;

  const SessionEntry({
    required this.factId,
    this.questionAsked,
    this.priorQuestions = const [],
  });

  Map<String, dynamic> toJson() => {
    'factId': factId,
    if (questionAsked != null) 'questionAsked': questionAsked,
    'priorQuestions': priorQuestions,
  };

  factory SessionEntry.fromJson(Map<String, dynamic> json) => SessionEntry(
    factId: json['factId'] as String,
    questionAsked: json['questionAsked'] as String?,
    priorQuestions: (json['priorQuestions'] as List).cast<String>(),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SessionService
// ─────────────────────────────────────────────────────────────────────────────
class SessionService {
  static const String _key = 'session_stack';

  // In-memory mirror of the persisted stack.
  // Updated synchronously on push/pop; persisted asynchronously.
  static List<SessionEntry> _stack = [];

  // Returns an unmodifiable view of the current stack.
  static List<SessionEntry> get current => List.unmodifiable(_stack);

  static bool get hasSession => _stack.isNotEmpty;

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  // Reads the persisted session from SharedPreferences into _stack.
  // Call once at startup (or lazily in the feed screen's initState).
  // Safe to call multiple times — overwrites the in-memory copy each time.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_key);
    if (json == null) {
      _stack = [];
      return;
    }
    try {
      final list = jsonDecode(json) as List;
      _stack = list
          .map((e) => SessionEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // Corrupted data — start fresh.
      _stack = [];
    }
  }

  // ── Stack operations ────────────────────────────────────────────────────────

  // Adds an entry to the top of the stack and persists.
  // The in-memory update is synchronous (before the first await), so callers
  // that don't await still see the updated stack immediately.
  static Future<void> push(SessionEntry entry) async {
    _stack = [..._stack, entry];
    await _persist();
  }

  // Removes the top entry from the stack and persists.
  static Future<void> pop() async {
    if (_stack.isEmpty) return;
    _stack = _stack.sublist(0, _stack.length - 1);
    await _persist();
  }

  // Clears the stack in memory and in SharedPreferences.
  // Called when the user navigates back to the feed root.
  static Future<void> clear() async {
    _stack = [];
    await _persist();
  }

  // Clears only the in-memory stack without touching SharedPreferences.
  // Used just before session restore: the old prefs value is left in place
  // until each ExpansionScreen's initState rebuilds the stack correctly via push().
  static void clearInMemory() => _stack = [];

  // ── Persistence ─────────────────────────────────────────────────────────────

  static Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(_stack.map((e) => e.toJson()).toList()),
    );
  }
}
