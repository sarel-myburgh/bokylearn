// ─────────────────────────────────────────────────────────────────────────────
// expansion_screen.dart — Expanded fact view with streaming AI article
//
// Shown when the user taps a feed card. Also reused for every level of the
// "rabbit hole" — follow-up questions push a new ExpansionScreen onto the
// Navigator stack.
//
// Layout (top to bottom):
//   1. Original fact text (bold title)
//   2. Image (if the fact has one) with caption and source credit
//   3. AI-generated article (streams in word-by-word with a blinking cursor)
//   4. "Read more on [source]" link (shown after stream completes)
//   5. Three follow-up question chips (shown after stream completes)
//   6. Custom question text field
//   7. Credit attribution (small, at the bottom)
//
// Streaming behaviour:
//   - On init, an SSE stream is opened to the AI provider.
//   - Incoming text chunks are appended to _accumulated.
//   - _displayText is updated on every chunk, causing a rebuild (word-by-word).
//   - When the stream completes, parseStreamedOutput() splits the raw text
//     into article + questions, and the post-stream UI elements appear.
//   - _started gates the "Connecting to model..." vs actual text display.
//   - _done gates the follow-up questions and read-more button.
//
// Navigation:
//   - Tapping a follow-up question or submitting a custom question pushes a
//     new ExpansionScreen with questionAsked set and priorQuestions extended.
//   - The home button pops the entire stack back to the feed.
//   - The back button pops one level (standard Navigator behaviour).
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/models/fact.dart';
import '../../data/local/app_settings.dart';
import '../../data/local/facts_db.dart';
import '../../data/local/session_service.dart';
import '../../data/remote/ai_client.dart';

class ExpansionScreen extends ConsumerStatefulWidget {
  // The fact that this screen expands on. Passed down through the rabbit hole.
  final Fact fact;

  // If set, this screen is answering a follow-up question rather than
  // expanding the original fact. The AI uses answerQuestion() instead of
  // expandFact().
  final String? questionAsked;

  // The chain of questions leading to this screen. Passed to the AI as context
  // so its answer is coherent with the exploration path so far.
  final List<String> priorQuestions;

  const ExpansionScreen({
    super.key,
    required this.fact,
    this.questionAsked,
    this.priorQuestions = const [],
  });

  @override
  ConsumerState<ExpansionScreen> createState() => _ExpansionScreenState();
}

class _ExpansionScreenState extends ConsumerState<ExpansionScreen> {
  final _questionController = TextEditingController();

  // Active SSE stream subscription. Stored so it can be cancelled on dispose
  // or before a refresh, preventing setState calls on a defunct widget.
  StreamSubscription<String>? _subscription;

  // Accumulates all received text chunks into a single buffer.
  final _accumulated = StringBuffer();

  // The text currently displayed — updated on every chunk.
  String _displayText = '';

  // Parsed article + questions, available after the stream completes.
  ExpandedFact? _parsed;

  // True once the stream has finished (success or error).
  bool _done = false;

  // True once the first chunk has arrived — used to switch from the
  // "Connecting to model..." spinner to the actual streaming text.
  bool _started = false;

  // Set if the stream errors out — replaces the article area with an error message.
  String? _error;

  // Like/dislike reaction on the root fact. Initialised from Hive in initState.
  // Null means no reaction set. Applies to widget.fact regardless of depth.
  String? _reaction;

  // Bookmark state for the root fact. Shown in the app bar so it's accessible
  // at any depth without needing to scroll or wait for the article to load.
  late bool _bookmarked;

  @override
  void initState() {
    super.initState();

    // Track this screen in the session so the user can resume after closing the
    // app. push() updates the in-memory stack synchronously before its first
    // await, so it's safe to fire-and-forget here.
    SessionService.push(SessionEntry(
      factId: widget.fact.id,
      questionAsked: widget.questionAsked,
      priorQuestions: widget.priorQuestions,
    ));

    // Load current reaction and bookmark state from Hive.
    _reaction   = FactsDb.getReaction(widget.fact.id);
    _bookmarked = FactsDb.isBookmarked(widget.fact.id);

    // For root expansion screens (not follow-up questions), check if the AI
    // article was already generated and cached. If so, apply it immediately
    // without making an AI call — instant load for bookmarked facts.
    if (widget.questionAsked == null) {
      final cached = FactsDb.getCachedArticle(widget.fact.id);
      if (cached != null) {
        final result = parseStreamedOutput(cached);
        // Apply synchronously in initState — setState is safe here because the
        // widget hasn't rendered yet (called before the first frame).
        _displayText = result.article;
        _parsed = result;
        _started = true;
        _done = true;
        return; // Skip streaming entirely.
      }
    }

    _startStream();
  }

  @override
  void dispose() {
    // Cancel the stream before disposal so in-flight chunks don't call
    // setState on a defunct widget.
    _subscription?.cancel();
    SessionService.pop();
    _questionController.dispose();
    super.dispose();
  }

  // Toggles like/dislike on the root fact. Same logic as _FactCard:
  // tapping the active reaction clears it; reactions are mutually exclusive;
  // tag weights are adjusted to reflect the change.
  Future<void> _toggleReaction(String reaction) async {
    final next = _reaction == reaction ? null : reaction;

    // Reverse the old reaction's weight effect before applying the new one.
    if (_reaction == 'like')    await FactsDb.adjustTagWeights(widget.fact.tags, -0.2);
    if (_reaction == 'dislike') await FactsDb.adjustTagWeights(widget.fact.tags,  0.3);

    // Apply the new reaction's weight effect.
    if (next == 'like')    await FactsDb.adjustTagWeights(widget.fact.tags,  0.2);
    if (next == 'dislike') await FactsDb.adjustTagWeights(widget.fact.tags, -0.3);

    await FactsDb.setReaction(widget.fact.id, next);
    if (mounted) setState(() => _reaction = next);
  }

  // Clears the cached article (if any) and regenerates it from scratch.
  // Pull-down gesture on the scroll view triggers this.
  Future<void> _refresh() async {
    await _subscription?.cancel();
    _subscription = null;
    if (widget.questionAsked == null) {
      await FactsDb.clearCachedArticle(widget.fact.id);
    }
    _accumulated.clear();
    setState(() {
      _displayText = '';
      _parsed = null;
      _done = false;
      _started = false;
      _error = null;
    });
    _startStream();
  }

  // Parses the finished article text into a TextSpan tree.
  // Inline markdown links [label](url) become tappable accent-coloured spans.
  // Everything else is rendered as plain body text.
  TextSpan _buildArticleSpans(ThemeData theme) {
    final base = theme.textTheme.bodyLarge!.copyWith(height: 1.6);
    final link = base.copyWith(
      color: const Color(0xFFDA7422),
      decoration: TextDecoration.underline,
      decorationColor: const Color(0xFFDA7422),
    );

    final spans = <InlineSpan>[];
    final pattern = RegExp(r'\[([^\]]+)\]\(([^)]+)\)');
    int last = 0;

    for (final match in pattern.allMatches(_displayText)) {
      if (match.start > last) {
        spans.add(TextSpan(
          text: _displayText.substring(last, match.start),
          style: base,
        ));
      }
      final label = match.group(1)!;
      final url   = match.group(2)!;
      spans.add(TextSpan(
        text: label,
        style: link,
        recognizer: TapGestureRecognizer()..onTap = () => _openUrl(url),
      ));
      last = match.end;
    }
    if (last < _displayText.length) {
      spans.add(TextSpan(text: _displayText.substring(last), style: base));
    }
    return TextSpan(children: spans);
  }

  // Opens the SSE stream and wires up chunk, done, and error handlers.
  void _startStream() {
    final settings = ref.read(appSettingsProvider);
    final client = AiClient(
      apiKey: settings.activeApiKey,
      model: settings.activeModel,
      provider: settings.provider,
      ollamaBaseUrl: settings.ollamaBaseUrl,
    );

    // Choose the correct prompt type depending on whether this is an initial
    // expansion or a follow-up question answer.
    final stream = widget.questionAsked != null
        ? client.answerQuestion(
            widget.questionAsked!,
            widget.fact.text,
            widget.priorQuestions,
            widget.fact.furtherReadingUrls,
          )
        : client.expandFact(
            widget.fact.text,
            widget.fact.tags,
            widget.fact.furtherReadingUrls,
          );

    _subscription = stream.listen(
      // Each chunk: append to buffer, update display text, trigger rebuild.
      (chunk) {
        if (!mounted) return;
        _accumulated.write(chunk);
        setState(() {
          _started = true;
          _displayText = _accumulated.toString();
        });
      },

      // Stream complete: parse the full output to separate article from
      // questions, then show post-stream UI elements.
      onDone: () {
        if (!mounted) return;
        final raw = _accumulated.toString();
        final result = parseStreamedOutput(raw);

        // Cache root expansions so re-opening (e.g. from bookmarks) is instant.
        if (widget.questionAsked == null) {
          FactsDb.cacheArticle(widget.fact.id, raw);
        }

        setState(() {
          _parsed = result;
          _displayText = result.article;
          _done = true;
        });
      },

      onError: (e) {
        if (!mounted) return;
        setState(() {
          _error = 'Could not generate content. Check your API key and try again.';
          _done = true;
        });
      },
    );
  }

  // Pushes a new ExpansionScreen for a follow-up question.
  // The current question is appended to priorQuestions so the AI has the
  // full exploration chain as context.
  void _pushQuestion(String question) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ExpansionScreen(
        fact: widget.fact,
        questionAsked: question,
        priorQuestions: [...widget.priorQuestions, question],
      ),
    ));
  }

  // Opens a URL in the device's default browser.
  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // Shows a centered dialog with a zoom-overshoot entrance animation and a
  // short AI-generated explanation of the selected text.
  // Called from the "Explain" context menu item on the article text.
  void _showExplanation(String selectedText) {
    final settings = ref.read(appSettingsProvider);
    final client = AiClient(
      apiKey: settings.activeApiKey,
      model: settings.activeModel,
      provider: settings.provider,
      ollamaBaseUrl: settings.ollamaBaseUrl,
    );

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 380),
      transitionBuilder: (ctx, animation, _, child) {
        // easeOutBack overshoots 1.0 slightly before settling — gives the
        // "pops in, overextends a little, snaps back" game-UI feel.
        final scale = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );
        // Fade in quickly so the overshoot doesn't start on an invisible widget.
        final fade = CurvedAnimation(
          parent: animation,
          curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
        );
        return ScaleTransition(
          scale: scale,
          child: FadeTransition(opacity: fade, child: child),
        );
      },
      pageBuilder: (ctx, _, _) => _ExplanationDialog(
        selectedText: selectedText,
        client: client,
        onDiveDeeper: (text) {
          Navigator.of(context).pop(); // Close dialog
          _pushQuestion(text);         // Push new ExpansionScreen
        },
      ),
    );
  }

  // Shares the content via the native share sheet.
  // If the article has finished generating, shares the full article text.
  // If still loading or errored, falls back to the original fact text.
  // Format: "[heading]\n\n[article]\n\n— via BokyLearn\n[source_url]"
  void _share() {
    final fact = widget.fact;
    final heading = widget.questionAsked ?? fact.text;
    final body = (_done && _displayText.isNotEmpty) ? _displayText : fact.text;

    final buffer = StringBuffer(heading);
    if (body != heading) {
      buffer.write('\n\n$body');
    }
    buffer.write('\n\n— via BokyLearn');
    if (fact.readMoreUrl != null) {
      buffer.write('\n${fact.readMoreUrl}');
    }
    Share.share(buffer.toString());
  }

  // Called when the user submits their own question via the text field.
  // Sanitizes input (strips injection patterns, caps length) before
  // pushing it into the rabbit hole.
  void _submitCustomQuestion() {
    final raw = _questionController.text.trim();
    if (raw.isEmpty) return;
    final q = AiClient.sanitizeUserInput(raw);
    if (q.isEmpty) return;
    _questionController.clear();
    FocusScope.of(context).unfocus();
    _pushQuestion(q);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fact = widget.fact;

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        actions: [
          // Share button — shares the original fact text and source URL.
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: _share,
          ),
          // Bookmark button — always accessible regardless of scroll position or depth.
          IconButton(
            icon: Icon(
              _bookmarked ? Icons.bookmark : Icons.bookmark_outline,
              color: _bookmarked ? Colors.white : null,
            ),
            onPressed: () async {
              await FactsDb.toggleBookmark(widget.fact.id);
              if (mounted) setState(() => _bookmarked = !_bookmarked);
            },
          ),
          // Home button always visible — pops the entire navigator stack back
          // to the feed root and clears the session (the dispose calls on each
          // popped screen would eventually do the same, but clearing eagerly
          // ensures the prefs are wiped before the feed screen re-renders).
          IconButton(
            icon: const Icon(Icons.home_outlined),
            onPressed: () {
              SessionService.clear();
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Heading ──────────────────────────────────────────────────────
            // On the root expansion screen this is the original fact text.
            // On follow-up / dive-deeper screens it's the question being
            // answered, since that's the actual topic the user is exploring.
            Text(
              widget.questionAsked ?? fact.text,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 20),

            // ── Image (optional) ─────────────────────────────────────────────
            // Only shown if the fact has an image URL. Images are specific
            // (Wikimedia, NASA, etc.) not generic stock photos.
            if (fact.imageUrl != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  fact.imageUrl!,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  // If the image fails to load, silently hide it.
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
              if (fact.imageCaption != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    // Show caption and source separated by a middle dot.
                    [fact.imageCaption, fact.imageSource].whereType<String>().join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
            ],

            // ── Article area ─────────────────────────────────────────────────
            // Three states:
            //   error    → show error message
            //   !started → show "Connecting to model..." spinner
            //   default  → show streaming text (updates on every chunk)
            if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error))
            else if (!_started)
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Connecting to model...',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              )
            else if (!_done)
              // While streaming: plain selectable text — partial markdown looks
              // fine while being typed, and the blinking cursor provides feedback.
              SelectableText(
                _displayText,
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
              )
            else
              // Once done: parse inline markdown links into tappable spans.
              // SelectableText.rich preserves the "Explain" context menu.
              SelectableText.rich(
                _buildArticleSpans(theme),
                contextMenuBuilder: (ctx, editableTextState) {
                  final value = editableTextState.textEditingValue;
                  final sel = value.selection;
                  final selected = (sel.isValid && !sel.isCollapsed)
                      ? value.text.substring(sel.start, sel.end).trim()
                      : '';
                  return AdaptiveTextSelectionToolbar.buttonItems(
                    anchors: editableTextState.contextMenuAnchors,
                    buttonItems: [
                      if (selected.isNotEmpty)
                        ContextMenuButtonItem(
                          label: 'Explain',
                          onPressed: () {
                            ContextMenuController.removeAny();
                            _showExplanation(selected);
                          },
                        ),
                      ...editableTextState.contextMenuButtonItems,
                    ],
                  );
                },
              ),

            // Blinking cursor shown while the stream is in progress.
            if (_started && !_done && _error == null) ...[
              const SizedBox(height: 4),
              _BlinkingCursor(),
            ],

            // ── Post-stream content ──────────────────────────────────────────
            // Only rendered after the stream completes and the output is parsed.
            if (_done && _parsed != null) ...[
              const SizedBox(height: 20),

              // Like / Dislike row — lets the user react after reading the article.
              // Same weight adjustment logic as feed cards.
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      _reaction == 'like' ? Icons.thumb_up : Icons.thumb_up_outlined,
                      color: _reaction == 'like' ? const Color(0xFFDA7422) : null,
                    ),
                    onPressed: () => _toggleReaction('like'),
                  ),
                  IconButton(
                    icon: Icon(
                      _reaction == 'dislike' ? Icons.thumb_down : Icons.thumb_down_outlined,
                      color: _reaction == 'dislike' ? const Color(0xFFDA7422) : null,
                    ),
                    onPressed: () => _toggleReaction('dislike'),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Further reading pills — one per entry in the further_reading array.
              // Only shown on root expansion screens (not follow-up questions).
              if (widget.questionAsked == null &&
                  fact.furtherReadingUrls.isNotEmpty) ...[
                Text(
                  'Further reading',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < fact.furtherReadingUrls.length; i++)
                      _FurtherReadingChip(
                        url: fact.furtherReadingUrls[i],
                        title: i < fact.furtherReadingTitles.length
                            ? fact.furtherReadingTitles[i]
                            : fact.furtherReadingUrls[i],
                        onPressed: () => _openUrl(fact.furtherReadingUrls[i]),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
              ],

              const SizedBox(height: 28),

              // Follow-up question chips — each tappable, pushes a new screen.
              if (_parsed!.questions.isNotEmpty) ...[
                Text(
                  'Dive deeper',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                ..._parsed!.questions.map((q) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _pushQuestion(q),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: theme.colorScheme.outline.withValues(alpha: 0.5),
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Expanded(child: Text(q, style: theme.textTheme.bodyMedium)),
                              Icon(
                                Icons.chevron_right,
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )),
              ],

              const SizedBox(height: 20),

              // Custom question input — pushes a new ExpansionScreen on submit.
              Text(
                'Ask your own question',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _questionController,
                      decoration: const InputDecoration(
                        hintText: 'What else do you want to know?',
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _submitCustomQuestion(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFDA7422),
                      foregroundColor: const Color(0xFFFFFBDB),
                    ),
                    onPressed: _submitCustomQuestion,
                    child: const Icon(Icons.arrow_forward),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Attribution credit.
              if (fact.credit != null)
                Text(
                  'Source: ${fact.credit}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                ),

              // Tags — all of them, shown at the bottom of root screens only.
              if (widget.questionAsked == null && fact.tags.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Tags',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in fact.tags)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          tag.replaceAll('_', ' '),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                  ],
                ),
              ],

              // Fact ID — tappable to copy; for reporting issues.
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: fact.id));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Fact ID copied'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                child: Row(
                  children: [
                    Icon(
                      Icons.fingerprint,
                      size: 13,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.25),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        fact.id,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.25),
                          fontFamily: 'monospace',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      Icons.copy,
                      size: 13,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.25),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _FurtherReadingChip — an ActionChip with a favicon avatar fetched via the
// Google favicon API for the pill's URL domain.
// ─────────────────────────────────────────────────────────────────────────────
class _FurtherReadingChip extends StatelessWidget {
  final String url;
  final String title;
  final VoidCallback onPressed;

  const _FurtherReadingChip({
    required this.url,
    required this.title,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final domain = Uri.tryParse(url)?.host ?? '';
    final faviconUrl = domain.isNotEmpty
        ? 'https://www.google.com/s2/favicons?domain=$domain&sz=64'
        : null;

    return ActionChip(
      avatar: faviconUrl != null
          ? Image.network(
              faviconUrl,
              width: 16,
              height: 16,
              errorBuilder: (_, e, st) => const Icon(Icons.open_in_new, size: 14),
            )
          : const Icon(Icons.open_in_new, size: 14),
      label: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      onPressed: onPressed,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ExplanationDialog — centered lightbox shown when the user selects text and
// taps "Explain" in the context menu.
//
// Displayed via showGeneralDialog with a scale+overshoot animation (see
// _showExplanation). Streams a short AI explanation, then offers a
// "Dive Deeper" button to push the selection into the rabbit hole.
// ─────────────────────────────────────────────────────────────────────────────
class _ExplanationDialog extends StatefulWidget {
  final String selectedText;
  final AiClient client;
  final ValueChanged<String> onDiveDeeper;

  const _ExplanationDialog({
    required this.selectedText,
    required this.client,
    required this.onDiveDeeper,
  });

  @override
  State<_ExplanationDialog> createState() => _ExplanationDialogState();
}

class _ExplanationDialogState extends State<_ExplanationDialog> {
  final _buffer = StringBuffer();
  String _text = '';
  bool _started = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    widget.client
        .explainSelection(widget.selectedText)
        .listen(
          (chunk) {
            _buffer.write(chunk);
            if (mounted) setState(() { _started = true; _text = _buffer.toString(); });
          },
          onDone: () { if (mounted) setState(() => _done = true); },
          onError: (_) { if (mounted) setState(() => _done = true); },
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Dialog is centered in the screen with a max width so it doesn't stretch
    // edge-to-edge on tablets or landscape phones.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Material(
          borderRadius: BorderRadius.circular(20),
          color: const Color(0xFFFFFBDB),
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Selected text — shown in italic as the dialog "title".
                Text(
                  '"${widget.selectedText}"',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: const Color(0xFF30362F),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 14),

                // Explanation body — spinner until first token arrives.
                if (!_started)
                  Row(children: [
                    const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFFDA7422),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Thinking...',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF30362F).withValues(alpha: 0.5),
                      ),
                    ),
                  ])
                else
                  Text(
                    _text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.5,
                      color: const Color(0xFF30362F),
                    ),
                  ),

                if (_done) ...[
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFDA7422),
                        foregroundColor: const Color(0xFFFFFBDB),
                      ),
                      onPressed: () => widget.onDiveDeeper(widget.selectedText),
                      icon: const Icon(Icons.arrow_forward, size: 18),
                      label: const Text('Dive Deeper'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BlinkingCursor — animated cursor shown while the AI stream is in progress
//
// Uses an AnimationController set to repeat(reverse: true) to fade in/out
// at 500ms per half-cycle, giving a ~1Hz blink.
// ─────────────────────────────────────────────────────────────────────────────
class _BlinkingCursor extends StatefulWidget {
  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true); // Oscillates opacity between 0 and 1
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 2,
        height: 18,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}
