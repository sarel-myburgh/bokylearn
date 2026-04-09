import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../data/local/facts_db.dart';
import '../../data/models/fact.dart';
import '../feed/fact_card.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  List<Fact> _results = [];
  bool _hasQuery = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String query) {
    setState(() {
      _hasQuery = query.trim().isNotEmpty;
      _results = FactsDb.searchFacts(query);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: BokyPalette.feedBackground,
      appBar: AppBar(
        backgroundColor: const Color(0xFFA59132),
        foregroundColor: BokyPalette.cardBackground,
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _onChanged,
          style: const TextStyle(color: BokyPalette.cardBackground),
          cursorColor: BokyPalette.cardBackground,
          decoration: InputDecoration(
            hintText: 'Search facts...',
            hintStyle: TextStyle(
              color: BokyPalette.cardBackground.withValues(alpha: 0.6),
            ),
            border: InputBorder.none,
          ),
        ),
        actions: [
          if (_hasQuery)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _controller.clear();
                _onChanged('');
              },
            ),
        ],
      ),
      body: !_hasQuery
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search,
                      size: 48,
                      color: BokyPalette.cardBackground.withValues(alpha: 0.3)),
                  const SizedBox(height: 12),
                  Text(
                    'Search facts',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: BokyPalette.cardBackground.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            )
          : _results.isEmpty
              ? Center(
                  child: Text(
                    'No results for "${_controller.text}"',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: BokyPalette.cardBackground.withValues(alpha: 0.5),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _results.length,
                  itemBuilder: (context, index) => FactCard(
                    fact: _results[index],
                    accentColor: BokyPalette.cardAccents[
                        index % BokyPalette.cardAccents.length],
                    visibilityKeyPrefix: 'search',
                  ),
                ),
    );
  }
}
