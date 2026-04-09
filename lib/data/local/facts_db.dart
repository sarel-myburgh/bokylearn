// ─────────────────────────────────────────────────────────────────────────────
// facts_db.dart — Local database layer
//
// Two storage backends, one class:
//
//   SQLite (sqflite)  — The facts catalogue.  Holds facts, fact_tags,
//                       fact_links, and a loaded_months table that tracks
//                       which monthly JSON files have been imported.
//                       An in-memory Map<String, Fact> mirrors every row so
//                       all read paths remain synchronous (same behaviour as
//                       the previous Hive-based approach).
//
//   Hive              — User data only.  Five boxes:
//                         seen_ts        Box<int>    — timestamps of seen facts
//                         reactions      Box<String> — 'like' | 'dislike' per fact
//                         bookmarks      Box<String> — bookmarked fact IDs
//                         tag_weights    Box<double> — feed curation weights
//                         article_cache  Box<String> — cached AI articles
//
// All public methods are static — FactsDb is a namespace, not an instance.
// Call init() once before runApp(); it opens both backends.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/fact.dart';

class FactsDb {
  // ── SQLite ────────────────────────────────────────────────────────────────

  static late Database _db;

  // In-memory mirror of the SQLite facts table.
  // Key = fact.id.  Kept in sync with every write so all reads are O(1) / sync.
  static final Map<String, Fact> _cache = {};

  // Month keys already imported, mapped to their downloaded manifest version.
  // Compared against the remote manifest on sync to detect enriched re-releases.
  static final Map<String, int> _loadedMonths = {};

  // ── Hive box names ────────────────────────────────────────────────────────

  static const String _seenTsBox       = 'seen_ts';
  static const String _reactionsBox    = 'reactions';
  static const String _bookmarksBox    = 'bookmarks';
  static const String _weightsBox      = 'tag_weights';
  static const String _articleCacheBox = 'article_cache';

  // ── Initialisation ────────────────────────────────────────────────────────

  // Opens SQLite + all Hive boxes.  Must be awaited before runApp().
  static Future<void> init() async {
    // SQLite — facts catalogue
    await _initSqlite();

    // Hive — user data
    await Hive.initFlutter();
    Hive.registerAdapter(FactAdapter()); // needed so existing Hive data can be read
    await Hive.openBox<int>(_seenTsBox);
    await Hive.openBox<String>(_reactionsBox);
    await Hive.openBox<String>(_bookmarksBox);
    await Hive.openBox<double>(_weightsBox);
    await Hive.openBox<String>(_articleCacheBox);
  }

  static Future<void> _initSqlite() async {
    final dir  = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/facts_local.db';

    _db = await openDatabase(
      path,
      version: 3,
      onCreate: (db, _) async {
        await db.executeBatch([
          '''CREATE TABLE IF NOT EXISTS facts (
               id            TEXT PRIMARY KEY,
               hash          TEXT UNIQUE NOT NULL,
               text          TEXT NOT NULL,
               image_url     TEXT,
               image_caption TEXT,
               mature        INTEGER DEFAULT 0,
               source        TEXT,
               month         TEXT,
               tih_month     INTEGER,
               tih_day       INTEGER,
               scraped_at    TEXT
             )''',
          '''CREATE TABLE IF NOT EXISTS fact_tags (
               fact_id TEXT NOT NULL REFERENCES facts(id) ON DELETE CASCADE,
               tag     TEXT NOT NULL,
               PRIMARY KEY (fact_id, tag)
             )''',
          '''CREATE TABLE IF NOT EXISTS fact_links (
               fact_id TEXT NOT NULL REFERENCES facts(id) ON DELETE CASCADE,
               url     TEXT NOT NULL,
               title   TEXT,
               source  TEXT,
               PRIMARY KEY (fact_id, url)
             )''',
          '''CREATE TABLE IF NOT EXISTS loaded_months (
               month   TEXT PRIMARY KEY,
               version INTEGER DEFAULT 1
             )''',
        ]);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE facts ADD COLUMN tih_month INTEGER');
          await db.execute('ALTER TABLE facts ADD COLUMN tih_day   INTEGER');
        }
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE loaded_months ADD COLUMN version INTEGER DEFAULT 1');
        }
      },
    );

    // Load existing data into the in-memory cache.
    await _rebuildCache();
  }

  // Reads all facts + tags + links from SQLite into _cache and _loadedMonths.
  // Paginated in batches of 300 so no single platform-channel call tries to
  // marshal the entire dataset into one buffer (avoids OOM on large datasets).
  static Future<void> _rebuildCache() async {
    _cache.clear();
    _loadedMonths.clear();

    const batchSize = 300;
    var offset = 0;

    while (true) {
      final factRows = await _db.query('facts', limit: batchSize, offset: offset);
      if (factRows.isEmpty) break;

      final ids          = factRows.map((r) => r['id'] as String).toList();
      final placeholders = List.filled(ids.length, '?').join(',');

      final tagRows  = await _db.rawQuery(
        'SELECT fact_id, tag FROM fact_tags WHERE fact_id IN ($placeholders)', ids);
      final linkRows = await _db.rawQuery(
        'SELECT fact_id, url, title, source FROM fact_links WHERE fact_id IN ($placeholders)', ids);

      final tagsByFactId = <String, List<String>>{};
      for (final row in tagRows) {
        tagsByFactId.putIfAbsent(row['fact_id'] as String, () => [])
            .add(row['tag'] as String);
      }

      final linksByFactId = <String, List<Map<String, dynamic>>>{};
      for (final row in linkRows) {
        linksByFactId.putIfAbsent(row['fact_id'] as String, () => [])
            .add(Map<String, dynamic>.from(row));
      }

      for (final row in factRows) {
        final id   = row['id'] as String;
        final fact = Fact.fromSqlite(
          row:   row,
          tags:  tagsByFactId[id]  ?? [],
          links: linksByFactId[id] ?? [],
        );
        _cache[id] = fact;
      }

      offset += batchSize;
    }

    final monthRows = await _db.query('loaded_months');
    for (final row in monthRows) {
      _loadedMonths[row['month'] as String] = (row['version'] as int?) ?? 1;
    }
  }

  // ── Hive convenience getters ─────────────────────────────────────────────

  static Box<int>    get _seenTs       => Hive.box<int>(_seenTsBox);
  static Box<String> get _reactions    => Hive.box<String>(_reactionsBox);
  static Box<String> get _bookmarks    => Hive.box<String>(_bookmarksBox);
  static Box<double> get _weights      => Hive.box<double>(_weightsBox);
  static Box<String> get _articleCache => Hive.box<String>(_articleCacheBox);

  // ── Month tracking ────────────────────────────────────────────────────────

  // Month keys already in the local DB mapped to their downloaded version.
  // Used by FactsFetcher to detect newly enriched months that need re-downloading.
  static Map<String, int> get loadedMonthVersions => Map.unmodifiable(_loadedMonths);

  // ── Facts (write) ─────────────────────────────────────────────────────────

  // Inserts a batch of facts from a monthly JSON file into SQLite and the
  // in-memory cache.  Skips duplicates by hash (INSERT OR IGNORE).
  // Marks the month as loaded so it is never re-downloaded.
  //
  // jsonFacts: the 'facts' array from the monthly JSON, each element is:
  //   { id, hash, text, image_url, mature, source, scraped_at,
  //     links: [{url, title, source}] }
  static Future<void> storeMonthFacts(
    String monthKey,
    List<Map<String, dynamic>> jsonFacts, {
    int version = 1,
    bool replace = false,
  }) async {
    // When re-downloading a stale month, wipe its existing rows first so the
    // fresh data (with updated tags/images) fully replaces the old content.
    if (replace && _loadedMonths.containsKey(monthKey)) {
      final ids = await _db.query('facts', columns: ['id'],
          where: 'month = ?', whereArgs: [monthKey]);
      for (final row in ids) { _cache.remove(row['id'] as String); }
      await _db.delete('facts', where: 'month = ?', whereArgs: [monthKey]);
      await _db.delete('loaded_months', where: 'month = ?', whereArgs: [monthKey]);
      _loadedMonths.remove(monthKey);
    }

    final batch = _db.batch();

    for (final f in jsonFacts) {
      final image   = f['image'] as Map<String, dynamic>?;
      final imageUrl     = image?['url'] as String?;
      final imageCaption = image?['caption'] as String?;

      batch.rawInsert(
        'INSERT OR IGNORE INTO facts '
        '(id, hash, text, image_url, image_caption, mature, source, month, tih_month, tih_day, scraped_at) '
        'VALUES (?,?,?,?,?,?,?,?,?,?,?)',
        [
          f['id'] as String,
          f['hash'] as String,
          f['text'] as String,
          imageUrl,
          imageCaption,
          (f['mature'] as bool? ?? false) ? 1 : 0,
          f['source'] as String?,
          monthKey,
          f['tih_month'] as int?,
          f['tih_day']   as int?,
          f['scraped_at'] as String?,
        ],
      );

      // Insert tags (empty for now; tagger agent fills these later).
      final tags = (f['tags'] as List? ?? []).cast<String>();
      for (final tag in tags) {
        batch.rawInsert(
          'INSERT OR IGNORE INTO fact_tags (fact_id, tag) VALUES (?,?)',
          [f['id'], tag],
        );
      }

      final links = (f['links'] as List? ?? []).cast<Map<String, dynamic>>();
      for (final l in links) {
        batch.rawInsert(
          'INSERT OR IGNORE INTO fact_links (fact_id, url, title, source) '
          'VALUES (?,?,?,?)',
          [f['id'], l['url'], l['title'], l['source']],
        );
      }
    }

    batch.rawInsert(
      'INSERT OR IGNORE INTO loaded_months (month, version) VALUES (?, ?)',
      [monthKey, version],
    );

    await batch.commit(noResult: true);

    // Re-build the in-memory cache for newly inserted facts.
    // Only add facts that weren't already in the cache (hash-dedup).
    final existingHashes = {for (final f in _cache.values) f.id: true};
    for (final f in jsonFacts) {
      final id = f['id'] as String;
      if (existingHashes.containsKey(id)) continue;
      final links = (f['links'] as List? ?? []).cast<Map<String, dynamic>>();
      final image = f['image'] as Map<String, dynamic>?;
      final fact  = Fact.fromSqlite(
        row: {
          'id':            f['id'],
          'hash':          f['hash'],
          'text':          f['text'],
          'image_url':     image?['url'],
          'image_caption': image?['caption'],
          'mature':        (f['mature'] as bool? ?? false) ? 1 : 0,
          'source':        f['source'],
          'month':         monthKey,
          'tih_month':     f['tih_month'],
          'tih_day':       f['tih_day'],
          'scraped_at':    f['scraped_at'],
        },
        tags:  (f['tags'] as List? ?? []).cast<String>(),
        links: links,
      );
      _cache[id] = fact;
    }
    _loadedMonths[monthKey] = version;
  }

  // ── Facts (read) ──────────────────────────────────────────────────────────

  // IDs of facts seen within the last 14 days — excluded from the feed.
  static Set<String> get _recentSeenIds {
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 14))
        .millisecondsSinceEpoch;
    return {
      for (final key in _seenTs.keys)
        if ((_seenTs.get(key) ?? 0) >= cutoff) key as String,
    };
  }

  // Weighted-random feed query (same algorithm as before, now over _cache).
  static List<Fact> queryFeed({
    required List<String> tags,
    bool excludeMature = true,
    int limit = 20,
  }) {
    final seenIds = _recentSeenIds;
    final rng = Random();

    final today = DateTime.now();
    final candidates = _cache.values.where((f) {
      if (seenIds.contains(f.id)) return false;
      if (excludeMature && f.mature) return false;
      // TIH facts only appear on their specific calendar day.
      if (f.source == 'tih') {
        if (f.tihMonth != today.month || f.tihDay != today.day) return false;
      }
      if (tags.isEmpty) return true;
      return f.tags.any((t) => tags.contains(t));
    }).toList();

    final scored = candidates.map((f) {
      final tagWeights = f.tags.map((t) => _weights.get(t) ?? 1.0);
      final avg = tagWeights.isEmpty
          ? 1.0
          : tagWeights.reduce((a, b) => a + b) / tagWeights.length;
      return (fact: f, score: rng.nextDouble() * avg);
    }).toList();

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).map((e) => e.fact).toList();
  }

  // Full-text search across fact text, tags, and credit source name.
  static List<Fact> searchFacts(String query) {
    if (query.trim().isEmpty) return [];
    final q = query.toLowerCase();
    return _cache.values.where((f) =>
      f.text.toLowerCase().contains(q) ||
      f.tags.any((t) => t.contains(q)) ||
      (f.credit?.toLowerCase().contains(q) ?? false),
    ).take(50).toList();
  }

  // Looks up a single fact by UUID.  Returns null if not found.
  static Fact? getFactById(String id) => _cache[id];

  // All unique tags across all stored facts.
  static List<String> get allTags {
    final tags = <String>{};
    for (final fact in _cache.values) {
      tags.addAll(fact.tags);
    }
    return tags.toList();
  }

  // Feed statistics (for the feed-exhaustion footer).
  static ({int total, int available, int hiddenSeen, int hiddenMature, int hiddenInterest})
      getFeedStats({required List<String> tags, bool excludeMature = true}) {
    final seenIds = _recentSeenIds;
    final today   = DateTime.now();
    int available = 0, hiddenSeen = 0, hiddenMature = 0, hiddenInterest = 0;

    for (final f in _cache.values) {
      // TIH facts not for today are simply excluded from all stats.
      if (f.source == 'tih' &&
          (f.tihMonth != today.month || f.tihDay != today.day)) {
        continue;
      }
      if (seenIds.contains(f.id)) {
        hiddenSeen++;
      } else if (excludeMature && f.mature) {
        hiddenMature++;
      } else if (tags.isNotEmpty && !f.tags.any((t) => tags.contains(t))) {
        hiddenInterest++;
      } else {
        available++;
      }
    }

    return (
      total: _cache.length,
      available: available,
      hiddenSeen: hiddenSeen,
      hiddenMature: hiddenMature,
      hiddenInterest: hiddenInterest,
    );
  }

  // Wipes all stored facts from SQLite and the cache.  Also clears loaded_months
  // so the next sync re-downloads everything.  Does NOT touch user data.
  static Future<void> clearFacts() async {
    await _db.transaction((txn) async {
      await txn.delete('fact_links');
      await txn.delete('fact_tags');
      await txn.delete('facts');
      await txn.delete('loaded_months');
    });
    _cache.clear();
    _loadedMonths.clear();
  }

  static int get totalFacts => _cache.length;
  static int get totalSeen  => _seenTs.length;

  // ── Seen facts ────────────────────────────────────────────────────────────

  static Future<void> markSeen(String factId) async {
    await _seenTs.put(factId, DateTime.now().millisecondsSinceEpoch);
  }

  static List<({Fact fact, DateTime seenAt})> getSeenHistory() {
    final entries = _seenTs.keys
        .cast<String>()
        .where((id) => _cache.containsKey(id))
        .map((id) => (id: id, ts: _seenTs.get(id)!))
        .toList()
      ..sort((a, b) => b.ts.compareTo(a.ts));
    return entries.map((e) => (
          fact:   _cache[e.id]!,
          seenAt: DateTime.fromMillisecondsSinceEpoch(e.ts),
        )).toList();
  }

  // ── Reactions ─────────────────────────────────────────────────────────────

  static String? getReaction(String factId) => _reactions.get(factId);

  static Future<void> setReaction(String factId, String? reaction) async {
    if (reaction == null) {
      await _reactions.delete(factId);
    } else {
      await _reactions.put(factId, reaction);
    }
  }

  // ── Bookmarks ─────────────────────────────────────────────────────────────

  static bool isBookmarked(String factId) => _bookmarks.containsKey(factId);

  static Future<void> toggleBookmark(String factId) async {
    if (_bookmarks.containsKey(factId)) {
      await _bookmarks.delete(factId);
    } else {
      await _bookmarks.put(factId, factId);
    }
  }

  static List<Fact> getBookmarkedFacts() {
    final ids = _bookmarks.keys.toSet();
    return _cache.values.where((f) => ids.contains(f.id)).toList();
  }

  // ── Tag weights (feed curation) ───────────────────────────────────────────

  static Future<void> adjustTagWeights(List<String> tags, double delta) async {
    final updates = <String, double>{};
    for (final tag in tags) {
      final current = _weights.get(tag) ?? 1.0;
      updates[tag] = (current + delta).clamp(0.1, 3.0);
    }
    await _weights.putAll(updates);
  }

  // ── Article cache ─────────────────────────────────────────────────────────

  static String? getCachedArticle(String factId) => _articleCache.get(factId);

  static Future<void> cacheArticle(String factId, String rawOutput) async {
    await _articleCache.put(factId, rawOutput);
  }

  static Future<void> clearCachedArticle(String factId) async {
    await _articleCache.delete(factId);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Database helper — batch execute a list of DDL statements.
// ─────────────────────────────────────────────────────────────────────────────
extension on Database {
  Future<void> executeBatch(List<String> statements) async {
    for (final sql in statements) {
      await execute(sql);
    }
  }
}
