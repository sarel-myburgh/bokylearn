// ─────────────────────────────────────────────────────────────────────────────
// facts_fetcher.dart — Downloads monthly JSON fact files from GitHub
//
// The facts repo (sarel-myburgh/facts) no longer ships a monolithic SQLite
// binary.  Instead it publishes:
//
//   data/manifest.json          — list of all scraped month keys
//   data/<month_key>.json       — one JSON file per scraped month
//
// Month key examples:
//   dyk_2026_Mar    Wikipedia "Did You Know" archive for March 2026
//   tih_Jan         Wikipedia "Today In History" for all January days (static)
//
// Sync algorithm (called on every launch and on pull-to-refresh):
//   1. GET manifest.json → list of all available month keys.
//   2. Ask FactsDb which months are already in the local SQLite DB.
//   3. Download each missing month JSON in parallel (max 8 concurrent).
//   4. Write each month's facts to the local DB via FactsDb.storeMonthFacts().
//
// Returns the number of new facts written.  The caller (FeedNotifier) uses
// this only to decide whether to reload the feed buffer.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../local/facts_db.dart';
import '../../core/constants.dart';

class FactsFetcher {
  // Maximum number of month files downloaded simultaneously.
  static const int _concurrency = 8;

  // ── Public entry points ──────────────────────────────────────────────────────

  // Downloads just enough months to populate an initial feed on first launch:
  // the 5 most recent DYK months + today's TIH month.
  // Call this on first launch, then call sync() in the background for the rest.
  static Future<int> quickSync() async {
    final available = await _fetchManifest();
    final localVersions = FactsDb.loadedMonthVersions;

    const tihNames = ['Jan','Feb','Mar','Apr','May','Jun',
                      'Jul','Aug','Sep','Oct','Nov','Dec'];
    final tihKey = 'tih_${tihNames[DateTime.now().month - 1]}';

    final dykKeys = available.keys
        .where((k) => k.startsWith('dyk_'))
        .toList()
      ..sort();
    final priorityKeys = [
      ...dykKeys.reversed.take(5),
      tihKey,
    ].where((k) => available.containsKey(k) && !localVersions.containsKey(k))
     .toList();

    if (priorityKeys.isEmpty) return 0;

    int added = 0;
    for (int i = 0; i < priorityKeys.length; i += _concurrency) {
      final batch = priorityKeys.skip(i).take(_concurrency).toList();
      final results = await Future.wait(
        batch.map((k) => _fetchMonth(k, version: available[k]!)),
        eagerError: false,
      );
      for (final r in results) { if (r != null) added += r; }
    }
    return added;
  }

  // Syncs the local DB with the remote facts repo.
  //
  // Downloads the manifest, then fetches:
  //   - months missing from the local DB entirely, and
  //   - months whose remote version exceeds the locally stored version
  //     (meaning the enricher has updated them since the last download).
  //
  // Returns the total number of new facts added.
  // Throws on manifest fetch failure; individual month failures are skipped.
  static Future<int> sync() async {
    // 1. Fetch manifest (month key → remote version).
    final available = await _fetchManifest();

    // 2. Compare against local versions.
    final localVersions = FactsDb.loadedMonthVersions;

    final toFetch  = <String>[];  // new months
    final toReplace = <String>[]; // stale months with higher remote version

    for (final entry in available.entries) {
      final local = localVersions[entry.key];
      if (local == null) {
        toFetch.add(entry.key);
      } else if (entry.value > local) {
        toReplace.add(entry.key);
      }
    }

    if (toFetch.isEmpty && toReplace.isEmpty) return 0;

    // 3. Download in parallel batches.
    int added = 0;
    final allKeys = [...toFetch, ...toReplace];
    for (int i = 0; i < allKeys.length; i += _concurrency) {
      final batch = allKeys.skip(i).take(_concurrency).toList();
      final results = await Future.wait(
        batch.map((key) => _fetchMonth(
          key,
          version: available[key]!,
          replace: toReplace.contains(key),
        )),
        eagerError: false,
      );
      for (final result in results) {
        if (result != null) added += result;
      }
    }
    return added;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  // Fetches manifest.json and returns a map of month key → remote version.
  static Future<Map<String, int>> _fetchManifest() async {
    final response = await http.get(Uri.parse(AppConstants.manifestUrl));
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch manifest: ${response.statusCode}');
    }
    final data   = jsonDecode(response.body) as Map<String, dynamic>;
    final months = data['months'];
    if (months is Map) {
      return {
        for (final e in (months as Map<String, dynamic>).entries)
          e.key: (e.value is Map ? (e.value as Map)['version'] as int? ?? 1 : 1),
      };
    }
    // Fallback: old list format — treat everything as version 1.
    return { for (final k in (months as List? ?? [])) k as String: 1 };
  }

  // Downloads one month JSON and writes its facts to the local DB.
  // [replace] = true means the month already exists and should be overwritten.
  // Returns the number of facts written, or null on failure (logged).
  static Future<int?> _fetchMonth(
    String monthKey, {
    int version = 1,
    bool replace = false,
  }) async {
    final url = '${AppConstants.factsRepoRawBase}/data/$monthKey.json';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        print('[FactsFetcher] $monthKey: HTTP ${response.statusCode}');
        return null;
      }
      final data  = jsonDecode(response.body) as Map<String, dynamic>;
      final facts = (data['facts'] as List? ?? []).cast<Map<String, dynamic>>();
      await FactsDb.storeMonthFacts(monthKey, facts, version: version, replace: replace);
      return facts.length;
    } catch (e) {
      print('[FactsFetcher] $monthKey: $e');
      return null;
    }
  }
}
