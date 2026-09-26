// ─────────────────────────────────────────────────────────────────────────────
// facts_fetcher.dart — Downloads monthly JSON fact files from GitHub
//
// The facts repo (sarel-myburgh/facts) publishes:
//
//   data/<month_key>.json       — one JSON file per scraped month
//   data/manifest.json          — list of all scraped month keys (optional)
//   data/tags.json              — interest taxonomy
//
// Month key examples:
//   dyk_2026_Mar    Wikipedia "Did You Know" archive for March 2026
//   tih_Jan         Wikipedia "Today In History" for all January days (static)
//
// Sync algorithm (called on every launch and on pull-to-refresh):
//   1. Try GET manifest.json → list of all available month keys.
//      If that 404s, fall back to the GitHub API to enumerate data/*.json files.
//   2. Ask FactsDb which months are already in the local SQLite DB.
//   3. Download each missing month JSON in parallel (max 8 concurrent).
//   4. Write each month's facts to the local DB via FactsDb.storeMonthFacts().
//
// Returns the number of new facts written.  The caller (FeedNotifier) uses
// this only to decide whether to reload the feed buffer.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../local/facts_db.dart';
import '../../core/constants.dart';

class FactsFetcher {
  static const int _concurrency = 8;

  // ── Public entry points ──────────────────────────────────────────────────

  static Future<int> quickSync() async {
    final available = await _fetchAvailableMonths();
    final localVersions = FactsDb.loadedMonthVersions;

    const tihNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final tihKey = 'tih_${tihNames[DateTime.now().month - 1]}';

    final dykKeys = available.keys.where((k) => k.startsWith('dyk_')).toList()
      ..sort();
    final priorityKeys = [...dykKeys.reversed.take(5), tihKey]
        .where((k) => available.containsKey(k) && !localVersions.containsKey(k))
        .toList();

    if (priorityKeys.isEmpty) return 0;

    int added = 0;
    for (int i = 0; i < priorityKeys.length; i += _concurrency) {
      final batch = priorityKeys.skip(i).take(_concurrency).toList();
      final results = await _downloadBatch(batch);
      for (final r in results) {
        if (r != null) added += r;
      }
    }
    return added;
  }

  static Future<int> sync() async {
    final available = await _fetchAvailableMonths();
    final localVersions = FactsDb.loadedMonthVersions;

    final toFetch = <String>[];
    final toReplace = <String>[];

    for (final entry in available.entries) {
      final local = localVersions[entry.key];
      if (local == null) {
        toFetch.add(entry.key);
      } else if (entry.value > local) {
        toReplace.add(entry.key);
      }
    }

    if (toFetch.isEmpty && toReplace.isEmpty) return 0;

    int added = 0;
    final allKeys = [...toFetch, ...toReplace];
    for (int i = 0; i < allKeys.length; i += _concurrency) {
      final batch = allKeys.skip(i).take(_concurrency).toList();
      final results = await _downloadBatch(
        batch,
        replaceKeys: Set.from(toReplace),
      );
      for (final result in results) {
        if (result != null) added += result;
      }
    }
    return added;
  }

  // ── Month discovery ──────────────────────────────────────────────────────

  // Returns {monthKey: version}.
  // Tries manifest.json first; falls back to GitHub API if that 404s.
  static Future<Map<String, int>> _fetchAvailableMonths() async {
    try {
      return await _fetchManifest();
    } catch (_) {
      return await _fetchFromGitHubApi();
    }
  }

  static Future<Map<String, int>> _fetchManifest() async {
    final response = await http.get(Uri.parse(AppConstants.manifestUrl));
    if (response.statusCode != 200) {
      throw Exception('Manifest not available: ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final months = data['months'];
    if (months is Map) {
      return {
        for (final e in (months as Map<String, dynamic>).entries)
          e.key: (e.value is Map
              ? (e.value as Map)['version'] as int? ?? 1
              : 1),
      };
    }
    return {for (final k in (months as List? ?? [])) k as String: 1};
  }

  // Enumerates data/*.json files via the GitHub content API.
  // Extracts month keys from filenames like "dyk_2004_Dec.json".
  static Future<Map<String, int>> _fetchFromGitHubApi() async {
    final response = await http.get(
      Uri.parse(AppConstants.factsRepoApiUrl),
      headers: {'Accept': 'application/vnd.github.v3+json'},
    );
    if (response.statusCode != 200) {
      throw Exception('GitHub API failed: ${response.statusCode}');
    }
    final files = (jsonDecode(response.body) as List<dynamic>)
        .cast<Map<String, dynamic>>();

    final months = <String, int>{};
    for (final f in files) {
      final name = f['name'] as String;
      if (!name.endsWith('.json') ||
          name == 'tags.json' ||
          name == 'manifest.json') {
        continue;
      }
      final key = name.replaceFirst('.json', '');
      months[key] = 1;
    }
    return months;
  }

  // ── Download helpers ──────────────────────────────────────────────────────

  static Future<List<int?>> _downloadBatch(
    List<String> keys, {
    Set<String> replaceKeys = const {},
  }) async {
    final results = await Future.wait(
      keys.map((k) => _fetchMonth(k, replace: replaceKeys.contains(k))),
      eagerError: false,
    );
    return results;
  }

  static Future<int?> _fetchMonth(
    String monthKey, {
    bool replace = false,
  }) async {
    final url = '${AppConstants.factsRepoRawBase}/data/$monthKey.json';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        debugPrint('[FactsFetcher] $monthKey: HTTP ${response.statusCode}');
        return null;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final facts = (data['facts'] as List? ?? []).cast<Map<String, dynamic>>();
      await FactsDb.storeMonthFacts(
        monthKey,
        facts,
        version: 1,
        replace: replace,
      );
      return facts.length;
    } catch (e) {
      debugPrint('[FactsFetcher] $monthKey: $e');
      return null;
    }
  }
}
