// ─────────────────────────────────────────────────────────────────────────────
// fact.dart — Data model for a single fact
//
// A Fact is the atomic unit of content in BokyLearn. Facts come from the
// SQLite database (sarel-myburgh/facts) and are stored locally in Hive
// so the feed works offline after the first download.
//
// The Hive adapter (fact.g.dart) is auto-generated — run:
//   flutter pub run build_runner build
// after changing any @HiveField annotations.
//
// SQLite schema (from the facts repo):
//   facts:      id, hash, text, image_url, mature, source (dyk/tih), scraped_at
//   fact_tags:  fact_id, tag
//   fact_links: fact_id, url, title, source
// ─────────────────────────────────────────────────────────────────────────────

import 'package:hive/hive.dart';

part 'fact.g.dart';

// typeId must be unique across all Hive models in the app.
@HiveType(typeId: 0)
class Fact extends HiveObject {
  // Stable UUID from the facts repo — used as the Hive box key and for
  // tracking seen/liked/bookmarked state across sessions.
  @HiveField(0)
  final String id;

  // The tweet-like fact text shown on feed cards (1–2 sentences).
  @HiveField(1)
  final String text;

  // Free-form tags assigned to the fact (e.g. "ancient_egypt", "deep_sea").
  // Used to match facts against user interests and to update tag weights
  // when the user likes/dislikes.
  @HiveField(2)
  final List<String> tags;

  // Attribution string shown as a small label on the card (e.g. "Wikipedia Did You Know").
  // Derived from the source column (dyk/tih) when reading from SQLite.
  @HiveField(3)
  final String? credit;

  // True if the fact contains sexual, graphic, or adult content.
  // The app filters these out by default; the user can enable them in Settings.
  @HiveField(4)
  final bool mature;

  // ISO date string of when the fact was collected (informational only).
  @HiveField(5)
  final String? scrapedAt;

  // URL opened when the user taps "Read more" in the expanded view.
  // Points to the first entry in fact_links (Wikipedia article, Britannica, etc.).
  @HiveField(6)
  final String? readMoreUrl;

  // Human-readable name of the read-more source (e.g. "Wikipedia").
  // Derived from the first fact_links entry's source column.
  @HiveField(7)
  final String? readMoreSource;

  // Optional Wikipedia infobox image URL.
  // Present when the original fact had "(pictured)" in the DYK/TIH archive.
  @HiveField(8)
  final String? imageUrl;

  // Image source attribution (e.g. "Wikimedia Commons").
  @HiveField(9)
  final String? imageSource;

  // Image caption / description text.
  @HiveField(10)
  final String? imageCaption;

  // Main homepage URL of the credit source (e.g. "https://en.wikipedia.org").
  // Used to derive the tappable domain handle on feed cards.
  @HiveField(11)
  final String? creditUrl;

  // Direct URL to the credit source's favicon.
  // Used as the circular avatar on feed cards.
  @HiveField(12)
  final String? creditLogoUrl;

  // Further reading links from fact_links (parallel lists — index N matches).
  @HiveField(13)
  final List<String> furtherReadingUrls;

  @HiveField(14)
  final List<String> furtherReadingTitles;

  // Origin source identifier: "dyk" (Did You Know) or "tih" (Today In History).
  @HiveField(15)
  final String? source;

  // Calendar month (1–12) on which this TIH fact should appear. Null for DYK.
  @HiveField(16)
  final int? tihMonth;

  // Day of month (1–31) on which this TIH fact should appear. Null for DYK.
  @HiveField(17)
  final int? tihDay;

  Fact({
    required this.id,
    required this.text,
    required this.tags,
    this.credit,
    this.mature = false,
    this.scrapedAt,
    this.readMoreUrl,
    this.readMoreSource,
    this.imageUrl,
    this.imageSource,
    this.imageCaption,
    this.creditUrl,
    this.creditLogoUrl,
    this.furtherReadingUrls = const [],
    this.furtherReadingTitles = const [],
    this.source,
    this.tihMonth,
    this.tihDay,
  });

  // ── SQLite constructor ────────────────────────────────────────────────────────

  // Builds a Fact from a row in the `facts` table, combined with its tags from
  // `fact_tags` and links from `fact_links`.
  //
  // Attribution is derived from the source column:
  //   "dyk" → "Wikipedia Did You Know"
  //   "tih" → "Wikipedia On This Day"
  //
  // The first link in `links` becomes the primary readMoreUrl/readMoreSource.
  // All links populate furtherReadingUrls/Titles for the expansion screen.
  factory Fact.fromSqlite({
    required Map<String, dynamic> row,
    required List<String> tags,
    required List<Map<String, dynamic>> links,
  }) {
    final src = row['source'] as String?;
    final (credit, creditUrl) = switch (src) {
      'dyk' => ('Wikipedia Did You Know', 'https://en.wikipedia.org/wiki/Wikipedia:Did_you_know'),
      'tih' => ('Wikipedia On This Day',  'https://en.wikipedia.org/wiki/Wikipedia:Selected_anniversaries'),
      _     => ('Wikipedia', 'https://en.wikipedia.org'),
    };

    final firstLink = links.isNotEmpty ? links.first : null;

    return Fact(
      id:          row['id'] as String,
      text:        _fixPunctSpacing(row['text'] as String),
      tags:        tags,
      source:      src,
      mature:      (row['mature'] as int? ?? 0) == 1,
      scrapedAt:   row['scraped_at'] as String?,
      imageUrl:     _resolvedImageUrl(row['image_url'] as String?, row['image_caption'] as String?),
      imageSource:  _resolvedImageUrl(row['image_url'] as String?, row['image_caption'] as String?) != null ? 'Wikimedia Commons' : null,
      imageCaption: _resolvedImageCaption(row['image_caption'] as String?),
      credit:      credit,
      creditUrl:   creditUrl,
      creditLogoUrl: 'https://en.wikipedia.org/favicon.ico',
      readMoreUrl:    firstLink?['url'] as String?,
      readMoreSource: firstLink?['source'] as String?,
      furtherReadingUrls: links
          .map((l) => l['url'] as String? ?? '')
          .where((u) => u.isNotEmpty)
          .toList(),
      furtherReadingTitles: links
          .map((l) => l['title'] as String? ?? '')
          .where((t) => t.isNotEmpty)
          .toList(),
      tihMonth: row['tih_month'] as int?,
      tihDay:   row['tih_day']   as int?,
    );
  }

  // ── JSON constructor (legacy) ─────────────────────────────────────────────────

  // Kept for backward compatibility with the old JSON-based facts file.
  factory Fact.fromJson(Map<String, dynamic> json) {
    final image = (json['fact_image'] as Map<String, dynamic>?) ??
        (json['image'] as Map<String, dynamic>?);
    final furtherReading = json['further_reading'] as List<dynamic>?;
    return Fact(
      id: json['id'] as String,
      text: json['text'] as String,
      tags: List<String>.from(json['tags'] as List? ?? []),
      credit: json['credit'] as String?,
      mature: json['mature'] as bool? ?? false,
      scrapedAt: json['scraped_at'] as String?,
      readMoreUrl: json['read_more_url'] as String?,
      readMoreSource: json['read_more_source'] as String?,
      imageUrl: _normalizeImageUrl(image?['url'] as String?),
      imageSource: (image?['source'] as String?) ?? (image?['publisher'] as String?),
      imageCaption: (image?['caption'] as String?) ?? (image?['description'] as String?),
      creditUrl: json['credit_url'] as String?,
      creditLogoUrl: (json['credit_logo'] as Map<String, dynamic>?)?['url'] as String?,
      furtherReadingUrls: furtherReading
          ?.map((e) => (e as Map<String, dynamic>)['url'] as String? ?? '')
          .where((u) => u.isNotEmpty)
          .toList() ?? [],
      furtherReadingTitles: furtherReading
          ?.map((e) {
            final m = e as Map<String, dynamic>;
            return (m['title'] as String?) ?? (m['publisher'] as String?) ?? '';
          })
          .where((t) => t.isNotEmpty)
          .toList() ?? [],
    );
  }

  static String _fixPunctSpacing(String text) =>
      text.replaceAllMapped(RegExp(r' ([,;:!?.])'), (m) => m.group(1)!);

  // Returns null if the caption marks the image as a placeholder (no real image).
  static bool _isPlaceholderCaption(String? caption) =>
      caption != null &&
      caption.toLowerCase().contains('no image available');

  static String? _resolvedImageUrl(String? url, String? caption) =>
      _isPlaceholderCaption(caption) ? null : _normalizeImageUrl(url);

  static String? _resolvedImageCaption(String? caption) =>
      _isPlaceholderCaption(caption) ? null : caption;

  static String? _normalizeImageUrl(String? url) {
    if (url == null || url.isEmpty) return null;

    final uri = Uri.tryParse(url);
    if (uri == null) return url;

    final isWikimediaFilePage =
        uri.host == 'commons.wikimedia.org' &&
        uri.pathSegments.length >= 2 &&
        uri.pathSegments[0] == 'wiki' &&
        uri.pathSegments[1].startsWith('File:');

    if (!isWikimediaFilePage) return url;

    final fileName = uri.pathSegments[1].substring('File:'.length);
    return 'https://commons.wikimedia.org/wiki/Special:FilePath/$fileName';
  }
}
