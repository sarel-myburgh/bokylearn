// ─────────────────────────────────────────────────────────────────────────────
// bookmarks_screen.dart — List of bookmarked facts
//
// Reads bookmarked facts from FactsDb on open. Each fact is shown as a card
// identical in style to the feed. Tapping a card opens the ExpansionScreen.
// Swiping a card left or right removes the bookmark.
//
// The list is loaded once on initState. If the user removes a bookmark, the
// local _facts list is updated immediately so the UI responds without
// requiring a full rebuild from Hive.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../data/local/facts_db.dart';
import '../../data/models/fact.dart';
import '../expansion/expansion_screen.dart';

class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  late List<Fact> _facts;

  @override
  void initState() {
    super.initState();
    _facts = FactsDb.getBookmarkedFacts();
  }

  Future<void> _removeBookmark(Fact fact) async {
    await FactsDb.toggleBookmark(fact.id); // toggles off since it's currently bookmarked
    setState(() => _facts.remove(fact));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Bookmarks')),
      body: _facts.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bookmark_outline,
                      size: 48,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
                  const SizedBox(height: 12),
                  Text(
                    'No bookmarks yet',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _facts.length,
              itemBuilder: (context, index) {
                final fact = _facts[index];
                return Dismissible(
                  key: ValueKey(fact.id),
                  // Swiping in either direction removes the bookmark.
                  background: _swipeBackground(context, Alignment.centerLeft),
                  secondaryBackground: _swipeBackground(context, Alignment.centerRight),
                  onDismissed: (_) => _removeBookmark(fact),
                  child: Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ExpansionScreen(fact: fact),
                      )),
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Coloured left strip — same cycling palette as feed cards.
                            Container(
                              width: 6,
                              color: BokyPalette.cardAccents[
                                index % BokyPalette.cardAccents.length
                              ],
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(fact.text, style: theme.textTheme.bodyLarge),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  // Red background with a delete icon shown behind the card while swiping.
  Widget _swipeBackground(BuildContext context, Alignment alignment) {
    return Container(
      color: Theme.of(context).colorScheme.error,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: const Icon(Icons.bookmark_remove, color: Colors.white),
    );
  }
}
