import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../../core/constants.dart';
import '../../data/local/app_settings.dart';
import '../../data/local/facts_db.dart';
import '../../data/models/fact.dart';
import '../expansion/expansion_screen.dart';

// Public feed card widget — reused in the feed, seen history, and search screens.
//
// [visibilityKeyPrefix] must be unique per screen so that the same fact can
// appear in multiple lists simultaneously without key conflicts.
class FactCard extends ConsumerStatefulWidget {
  const FactCard({
    super.key,
    required this.fact,
    required this.accentColor,
    this.visibilityKeyPrefix = 'feed',
  });

  final Fact fact;
  final Color accentColor;
  final String visibilityKeyPrefix;

  @override
  ConsumerState<FactCard> createState() => _FactCardState();
}

class _FactCardState extends ConsumerState<FactCard> {
  late String? _reaction;
  late bool _bookmarked;
  bool _hasBeenVisible = false;

  @override
  void initState() {
    super.initState();
    _reaction = FactsDb.getReaction(widget.fact.id);
    _bookmarked = FactsDb.isBookmarked(widget.fact.id);
  }

  Future<void> _onTap() async {
    await FactsDb.adjustTagWeights(widget.fact.tags, 0.1);
    final settings = ref.read(appSettingsProvider);
    if (settings.trackSeen) await FactsDb.markSeen(widget.fact.id);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ExpansionScreen(fact: widget.fact),
    ));
  }

  Future<void> _toggleReaction(String reaction) async {
    final next = _reaction == reaction ? null : reaction;
    if (_reaction == 'like')    await FactsDb.adjustTagWeights(widget.fact.tags, -0.2);
    if (_reaction == 'dislike') await FactsDb.adjustTagWeights(widget.fact.tags,  0.3);
    if (next == 'like')         await FactsDb.adjustTagWeights(widget.fact.tags,  0.2);
    if (next == 'dislike')      await FactsDb.adjustTagWeights(widget.fact.tags, -0.3);
    await FactsDb.setReaction(widget.fact.id, next);
    if (mounted) setState(() => _reaction = next);
  }

  Future<void> _toggleBookmark() async {
    await FactsDb.toggleBookmark(widget.fact.id);
    if (mounted) setState(() => _bookmarked = !_bookmarked);
  }

  void _share() {
    final fact = widget.fact;
    final buffer = StringBuffer(fact.text)..write(' — via BokyLearn');
    if (fact.readMoreUrl != null) buffer.write('\n${fact.readMoreUrl}');
    Share.share(buffer.toString());
  }

  String? get _creditHomeUrl {
    final explicit = widget.fact.creditUrl?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final logo = widget.fact.creditLogoUrl;
    if (logo == null || logo.isEmpty) return null;
    final uri = Uri.tryParse(logo);
    if (uri == null) return null;
    return '${uri.scheme}://${uri.host}';
  }

  String? get _creditDomain {
    final home = _creditHomeUrl;
    if (home == null) return null;
    final host = Uri.tryParse(home)?.host ?? '';
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  Future<void> _openCreditUrl() async {
    final url = _creditHomeUrl;
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fact = widget.fact;
    final creditDomain = _creditDomain;
    final credit = fact.credit?.trim();

    return VisibilityDetector(
      key: Key('${widget.visibilityKeyPrefix}-${widget.fact.id}'),
      onVisibilityChanged: (info) {
        if (info.visibleFraction > 0) {
          _hasBeenVisible = true;
        } else if (_hasBeenVisible) {
          final settings = ref.read(appSettingsProvider);
          if (settings.trackSeen) FactsDb.markSeen(widget.fact.id);
        }
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _onTap,
          child: DefaultTextStyle.merge(
            style: const TextStyle(color: BokyPalette.cardText),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (credit != null && credit.isNotEmpty) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _SourceAvatar(fact: fact, accentColor: widget.accentColor),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                credit,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (creditDomain != null)
                                GestureDetector(
                                  onTap: _openCreditUrl,
                                  child: Text(
                                    creditDomain,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.primary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],

                  if (fact.source == 'tih') ...[
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 13,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'On this day…',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],

                  Text(fact.text, style: theme.textTheme.bodyLarge),

                  if (fact.imageUrl != null) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 60, maxHeight: 480),
                        child: Image.network(
                          fact.imageUrl!,
                          width: double.infinity,
                          fit: BoxFit.fitWidth,
                          errorBuilder: (_, e, st) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                    if (fact.imageCaption != null || fact.imageSource != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          [fact.imageCaption, fact.imageSource]
                              .whereType<String>()
                              .join(' · '),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                          ),
                        ),
                      ),
                  ],

                  if (fact.tags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _TagRow(tags: fact.tags),
                  ],

                  const SizedBox(height: 8),

                  Row(
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          _reaction == 'like' ? Icons.thumb_up : Icons.thumb_up_outlined,
                          color: _reaction == 'like' ? const Color(0xFFDA7422) : null,
                        ),
                        onPressed: () => _toggleReaction('like'),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          _reaction == 'dislike' ? Icons.thumb_down : Icons.thumb_down_outlined,
                          color: _reaction == 'dislike' ? const Color(0xFFDA7422) : null,
                        ),
                        onPressed: () => _toggleReaction('dislike'),
                      ),
                      const Spacer(),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.share_outlined),
                        onPressed: _share,
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          _bookmarked ? Icons.bookmark : Icons.bookmark_outline,
                          color: _bookmarked ? theme.colorScheme.primary : null,
                        ),
                        onPressed: _toggleBookmark,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SourceAvatar extends StatelessWidget {
  const _SourceAvatar({required this.fact, required this.accentColor});

  final Fact fact;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final credit = fact.credit?.trim();
    final fallback = CircleAvatar(
      radius: 18,
      backgroundColor: accentColor,
      child: Text(
        (credit != null && credit.isNotEmpty) ? credit[0].toUpperCase() : '?',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );

    final logoUrl = fact.creditLogoUrl;
    if (logoUrl == null || logoUrl.isEmpty) return fallback;
    final domain = Uri.tryParse(logoUrl)?.host;
    if (domain == null || domain.isEmpty) return fallback;

    return ClipOval(
      child: Image.network(
        'https://www.google.com/s2/favicons?domain=$domain&sz=64',
        width: 36,
        height: 36,
        fit: BoxFit.cover,
        errorBuilder: (_, e, st) => fallback,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TagRow — shows up to 2 tag chips, then a "+N more" label if there are more.
// ─────────────────────────────────────────────────────────────────────────────
class _TagRow extends StatelessWidget {
  const _TagRow({required this.tags});

  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    final theme   = Theme.of(context);
    final visible = tags.take(2).toList();
    final extra   = tags.length - visible.length;

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final tag in visible)
          _TagChip(label: tag.replaceAll('_', ' '), theme: theme),
        if (extra > 0)
          _TagChip(label: '+$extra', theme: theme, muted: true),
      ],
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label, required this.theme, this.muted = false});

  final String    label;
  final ThemeData theme;
  final bool      muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: muted
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: muted
              ? theme.colorScheme.onSurface.withValues(alpha: 0.5)
              : theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
