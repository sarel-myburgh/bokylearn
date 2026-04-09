// ─────────────────────────────────────────────────────────────────────────────
// feed_provider.dart — Feed state management (Riverpod StateNotifier)
//
// Manages the list of facts shown in the feed.  Key responsibilities:
//   1. First launch (local DB empty): download all available months from the
//      facts repo manifest before showing anything (blocking spinner).
//   2. Subsequent launches: show feed immediately from the local DB, then sync
//      any new months in the background.
//   3. Query the local DB for a batch of unseen, interest-matching facts.
//   4. Append more facts as the user scrolls toward the end.
//   5. Handle pull-to-refresh (sync new months + reload buffer).
//
// State type: AsyncValue<List<Fact>>
//   loading  — first-launch sync in progress
//   error    — first-launch sync failed (no network, etc.)
//   data     — list of facts to display (grows as user scrolls)
//
// The list is append-only during a session — facts are added to the end,
// never removed.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/local/app_settings.dart';
import '../../data/local/facts_db.dart';
import '../../data/models/fact.dart';
import '../../data/remote/facts_fetcher.dart';

// Bump this constant whenever the Fact model gains or removes fields.
// On startup, if the stored version is lower, the facts DB is wiped and all
// months are re-downloaded so every stored fact has current fields populated.
const int _factsSchemaVersion = 11;

class FeedNotifier extends StateNotifier<AsyncValue<List<Fact>>> {
  FeedNotifier(this._ref) : super(const AsyncValue.loading()) {
    _init();
  }

  final Ref _ref;
  final List<Fact> _buffer = [];

  bool _exhausted = false;
  bool get isExhausted => _exhausted;

  // ── Initialisation ──────────────────────────────────────────────────────────

  Future<void> _init() async {
    try {
      // Schema version check — wipe local DB if the model has changed.
      final prefs = await SharedPreferences.getInstance();
      final storedVersion = prefs.getInt('facts_schema_version') ?? 0;
      if (storedVersion < _factsSchemaVersion) {
        await FactsDb.clearFacts();
        await prefs.setInt('facts_schema_version', _factsSchemaVersion);
      }

      if (FactsDb.totalFacts == 0) {
        // First launch (or post-schema-wipe) — must sync before showing anything.
        await FactsFetcher.sync();
        _loadMore();
      } else {
        // Returning user — show feed immediately, sync new months in background.
        _loadMore();
        _syncInBackground();
      }
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  // Silently syncs any new months from the manifest.
  // Errors are swallowed — best-effort; the user can pull-to-refresh manually.
  Future<void> _syncInBackground() async {
    try {
      await FactsFetcher.sync();
    } catch (_) {
      // Network unavailable or server error — ignore.
    }
  }

  // ── Interest → tag matching ─────────────────────────────────────────────────

  List<String> _tagsFromInterests(List<String> interests) {
    if (interests.isEmpty) return [];
    final allTags = FactsDb.allTags;
    final result = <String>{};
    for (final interest in interests) {
      final words = interest.toLowerCase()
          .split(RegExp(r'\W+'))
          .where((w) => w.length > 2)
          .toSet();
      for (final tag in allTags) {
        final parts = tag.toLowerCase().split('_');
        final matched = words.any((word) => parts.any((part) =>
          part == word || (word.length >= 4 && part.startsWith(word)),
        ));
        if (matched) result.add(tag);
      }
    }
    return result.toList();
  }

  // ── Loading facts ───────────────────────────────────────────────────────────

  void _loadMore() {
    final settings = _ref.read(appSettingsProvider);
    final tags = _tagsFromInterests(settings.interests);

    final batch = FactsDb.queryFeed(
      tags: tags,
      excludeMature: !settings.matureEnabled,
      limit: 20,
    );

    if (batch.isEmpty && _buffer.isNotEmpty) _exhausted = true;
    _buffer.addAll(batch);
    state = AsyncValue.data(List.unmodifiable(_buffer));
  }

  void requestMore() {
    if (_buffer.length < FactsDb.totalFacts) {
      _loadMore();
    }
  }

  // ── Refresh ─────────────────────────────────────────────────────────────────

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    _buffer.clear();
    _exhausted = false;
    try {
      await FactsFetcher.sync();
      _loadMore();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final feedProvider =
    StateNotifierProvider<FeedNotifier, AsyncValue<List<Fact>>>(
  (ref) => FeedNotifier(ref),
);
