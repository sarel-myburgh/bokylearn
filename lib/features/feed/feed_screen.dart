// ─────────────────────────────────────────────────────────────────────────────
// feed_screen.dart — The main scrollable fact feed
//
// Three widgets live here:
//
//   FeedScreen      — The full-screen scaffold. Manages the scroll controller
//                     and requests more facts when the user approaches the end.
//                     Shows loading / error / data states from feedProvider.
//                     Also loads the saved session on init and shows the
//                     "Pick up where you left off" banner when one exists.
//
//   _SessionBanner  — Compact card shown at the top of the feed when a saved
//                     session exists. Offers Resume and Dismiss actions.
//
//   _FactCard       — A single feed card. Maintains its own local state for
//                     like, dislike, and bookmark (read from Hive in initState,
//                     written on tap). Tapping the card opens ExpansionScreen
//                     and, if "Track seen facts" is on, marks the fact as seen.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants.dart';
import '../../data/local/app_settings.dart';
import '../../data/local/facts_db.dart';
import '../../data/local/session_service.dart';
import '../bookmarks/bookmarks_screen.dart';
import '../expansion/expansion_screen.dart';
import '../search/search_screen.dart';
import '../seen/seen_screen.dart';
import 'fact_card.dart';
import 'feed_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FeedScreen
// ─────────────────────────────────────────────────────────────────────────────
class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  final _scrollController = ScrollController();

  // Saved session entries loaded on init. Non-empty → show the resume banner.
  List<SessionEntry> _sessionEntries = [];

  // The topic label shown in the banner: the deepest question, or the root
  // fact text if no follow-ups were reached.
  String _sessionTopic = '';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadSession();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // Loads the persisted session from SharedPreferences. If a session exists,
  // stores the entries and computes the topic label for the banner.
  Future<void> _loadSession() async {
    await SessionService.load();
    if (!mounted || !SessionService.hasSession) return;

    final entries = SessionService.current.toList();
    final last = entries.last;

    // Show the deepest question reached, or fall back to the root fact text.
    final topic = last.questionAsked
        ?? FactsDb.getFactById(last.factId)?.text
        ?? 'your last session';

    setState(() {
      _sessionEntries = entries;
      _sessionTopic = topic;
    });
  }

  // Re-pushes all saved expansion screens in order, restoring the rabbit hole.
  // clearInMemory() is called first so each initState rebuilds the stack
  // correctly via push() rather than double-counting the existing entries.
  void _restoreSession() {
    final entries = List<SessionEntry>.from(_sessionEntries);
    setState(() => _sessionEntries = []);

    final rootFact = FactsDb.getFactById(entries.first.factId);
    if (rootFact == null) return; // Fact no longer in DB — can't restore.

    SessionService.clearInMemory();

    for (final entry in entries) {
      if (!mounted) break;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ExpansionScreen(
          fact: rootFact,
          questionAsked: entry.questionAsked,
          priorQuestions: List<String>.from(entry.priorQuestions),
        ),
      ));
    }
  }

  // Dismisses the banner and wipes the saved session.
  void _dismissSession() {
    SessionService.clear();
    setState(() => _sessionEntries = []);
  }

  // Triggered continuously as the user scrolls. When within 400 logical pixels
  // of the bottom, requests the next batch of facts from the provider so the
  // feed feels infinite (pre-buffering).
  void _onScroll() {
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 400) {
      ref.read(feedProvider.notifier).requestMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final feedState = ref.watch(feedProvider);
    final topInset = MediaQuery.paddingOf(context).top;
    const headerTopPadding = 10.0;
    const headerBottomPadding = 5.0;
    const collapsedContentHeight = 40.0;
    const expandedContentHeight = 72.0;
    final collapsedHeaderHeight =
        topInset + headerTopPadding + collapsedContentHeight + headerBottomPadding;
    final expandedHeaderHeight =
        topInset + headerTopPadding + expandedContentHeight + headerBottomPadding;

    return Scaffold(
      backgroundColor: BokyPalette.feedBackground,
      body: feedState.when(
        loading: () => const Center(child: CircularProgressIndicator()),

        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: BokyPalette.cardBackground),
              const SizedBox(height: 12),
              Text(
                'Could not load facts',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: BokyPalette.cardBackground,
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.read(feedProvider.notifier).refresh(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),

        data: (facts) => Stack(
          children: [
            // CustomScrollView lets the SliverAppBar collapse as the user scrolls.
            RefreshIndicator(
              onRefresh: () => ref.read(feedProvider.notifier).refresh(),
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  // ── Collapsing header ────────────────────────────────────
                  SliverAppBar(
                    backgroundColor: const Color(0xFFA59132),
                    foregroundColor: BokyPalette.cardBackground,
                    primary: false,
                    collapsedHeight: collapsedHeaderHeight,
                    expandedHeight: expandedHeaderHeight,
                    toolbarHeight: collapsedHeaderHeight,
                    pinned: true,
                    floating: false,
                    snap: false,
                    scrolledUnderElevation: 0,
                    automaticallyImplyLeading: false,
                    // No title or actions — everything lives inside flexibleSpace
                    // so logo, text, and buttons are always on the same row.
                    flexibleSpace: LayoutBuilder(
                      builder: (context, constraints) {
                        const logoMinSize = 36.0;
                        const logoMaxSize = 50.0;
                        const sideSlotWidth = 84.0;
                        const titleFontSize = 24.0;
                        const taglineFontSize = 10.0;
                        const titleGap = 2.0;
                        final currentContentHeight =
                            constraints.maxHeight -
                            topInset -
                            headerTopPadding -
                            headerBottomPadding;
                        final range = expandedContentHeight - collapsedContentHeight;
                        final t = range <= 0
                            ? 0.0
                            : ((currentContentHeight - collapsedContentHeight) / range)
                                .clamp(0.0, 1.0);

                        final contentHeight = lerpDouble(
                              collapsedContentHeight,
                              expandedContentHeight,
                              t,
                            ) ??
                            collapsedContentHeight;
                        final logoSize = lerpDouble(logoMinSize, logoMaxSize, t) ?? logoMinSize;
                        final titleOpacity = Curves.easeOut.transform(
                          ((t - 0.2) / 0.8).clamp(0.0, 1.0),
                        );

                        return ClipRect(
                          child: Container(
                            color: const Color(0xFFA59132),
                            padding: EdgeInsets.fromLTRB(
                              12,
                              topInset + headerTopPadding,
                              8,
                              headerBottomPadding,
                            ),
                            child: SizedBox(
                              height: contentHeight,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: sideSlotWidth,
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () => ref.read(feedProvider.notifier).refresh(),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 2),
                                          child: Image.asset(
                                            'assets/images/bokylearnlogo.png',
                                            height: logoSize,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Opacity(
                                      opacity: titleOpacity,
                                      child: Center(
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Text(
                                                'BokyLearn',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: BokyPalette.cardBackground,
                                                  fontSize: titleFontSize,
                                                  height: 1.0,
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: 0.3,
                                                ),
                                              ),
                                              const SizedBox(height: titleGap),
                                              const Text(
                                                'Down the rabbit hole 🐇',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: BokyPalette.cardBackground,
                                                  fontSize: taglineFontSize,
                                                  height: 1.0,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints.tightFor(
                                          width: 30,
                                          height: 36,
                                        ),
                                        visualDensity: VisualDensity.compact,
                                        iconSize: 18,
                                        icon: const Icon(Icons.search),
                                        color: BokyPalette.cardBackground,
                                        onPressed: () => Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => const SearchScreen(),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints.tightFor(
                                          width: 30,
                                          height: 36,
                                        ),
                                        visualDensity: VisualDensity.compact,
                                        iconSize: 18,
                                        icon: const Icon(Icons.history),
                                        color: BokyPalette.cardBackground,
                                        onPressed: () => Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => const SeenScreen(),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints.tightFor(
                                          width: 30,
                                          height: 36,
                                        ),
                                        visualDensity: VisualDensity.compact,
                                        iconSize: 18,
                                        icon: const Icon(Icons.bookmark_outline),
                                        color: BokyPalette.cardBackground,
                                        onPressed: () => Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => const BookmarksScreen(),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints.tightFor(
                                          width: 30,
                                          height: 36,
                                        ),
                                        visualDensity: VisualDensity.compact,
                                        iconSize: 18,
                                        icon: const Icon(Icons.settings),
                                        color: BokyPalette.cardBackground,
                                        onPressed: () => context.push('/settings'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // ── Session resume banner ────────────────────────────────
                  if (_sessionEntries.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _SessionBanner(
                        topic: _sessionTopic,
                        onResume: _restoreSession,
                        onDismiss: _dismissSession,
                      ),
                    ),

                  // ── Fact cards ───────────────────────────────────────────
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    sliver: SliverList.builder(
                      itemCount: facts.length,
                      itemBuilder: (context, index) => FactCard(
                        fact: facts[index],
                        accentColor: BokyPalette.cardAccents[
                          index % BokyPalette.cardAccents.length
                        ],
                      ),
                    ),
                  ),

                  // Feed exhaustion message — shown when no more eligible facts remain.
                  if (ref.read(feedProvider.notifier).isExhausted)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 32),
                        child: Column(
                          children: [
                            Icon(Icons.auto_awesome,
                                size: 40,
                                color: BokyPalette.cardBackground.withValues(alpha: 0.3)),
                            const SizedBox(height: 12),
                            Text(
                              "You've seen everything!",
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: BokyPalette.cardBackground.withValues(alpha: 0.6),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Pull down to refresh, or check back in a couple of weeks when seen facts resurface.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: BokyPalette.cardBackground.withValues(alpha: 0.35),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Floating stats chip — bottom-right corner.
            const Positioned(
              bottom: 16,
              right: 16,
              child: _FeedStatsChip(),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SessionBanner — "Pick up where you left off" card shown at the top of the
// feed when a saved rabbit-hole session exists.
//
// Shows the deepest topic the user was exploring and offers Resume / Dismiss.
// ─────────────────────────────────────────────────────────────────────────────
class _SessionBanner extends StatelessWidget {
  final String topic;
  final VoidCallback onResume;
  final VoidCallback onDismiss;

  const _SessionBanner({
    required this.topic,
    required this.onResume,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Icon(Icons.history, color: theme.colorScheme.onSecondaryContainer),
            const SizedBox(width: 12),

            // Topic label — takes all remaining space, truncates if too long.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Pick up where you left off',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    topic,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer
                          .withValues(alpha: 0.7),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            TextButton(
              onPressed: onResume,
              child: const Text('Resume'),
            ),

            // Dismiss — wipes the session without restoring.
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              visualDensity: VisualDensity.compact,
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _FeedStatsChip — floating pill in the bottom-right corner of the feed
//
// Shows "N facts in feed" — the number of facts currently eligible to appear
// given the user's seen history and active interest/mature filters.
// Updates whenever appSettingsProvider changes.
// ─────────────────────────────────────────────────────────────────────────────
class _FeedStatsChip extends ConsumerWidget {
  const _FeedStatsChip();

  static List<String> _tagsFromInterests(List<String> interests) {
    if (interests.isEmpty) return [];
    final allTags = FactsDb.allTags;
    final result = <String>{};
    for (final interest in interests) {
      final words = interest.toLowerCase().split(RegExp(r'\W+'))
          .where((w) => w.length > 2).toList();
      for (final tag in allTags) {
        if (words.any((w) => tag.contains(w))) result.add(tag);
      }
    }
    return result.toList();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final tags = _tagsFromInterests(settings.interests);
    final s = FactsDb.getFeedStats(
      tags: tags,
      excludeMature: !settings.matureEnabled,
    );

    final theme = Theme.of(context);

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(20),
      color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.92),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          '${s.available} facts in feed',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}
