import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../data/local/facts_db.dart';
import '../../data/models/fact.dart';
import '../feed/fact_card.dart';

class SeenScreen extends StatefulWidget {
  const SeenScreen({super.key});

  @override
  State<SeenScreen> createState() => _SeenScreenState();
}

class _SeenScreenState extends State<SeenScreen> {
  late List<({Fact fact, DateTime seenAt})> _history;

  @override
  void initState() {
    super.initState();
    _history = FactsDb.getSeenHistory();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: BokyPalette.feedBackground,
      appBar: AppBar(title: const Text('History')),
      body: _history.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history,
                      size: 48,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
                  const SizedBox(height: 12),
                  Text(
                    'No history yet',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Facts you scroll past will appear here',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _history.length,
              itemBuilder: (context, index) {
                final entry = _history[index];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FactCard(
                      fact: entry.fact,
                      accentColor: BokyPalette.cardAccents[
                          index % BokyPalette.cardAccents.length],
                      visibilityKeyPrefix: 'seen',
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 24, bottom: 4),
                      child: Text(
                        _formatDate(entry.seenAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: BokyPalette.cardBackground.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
