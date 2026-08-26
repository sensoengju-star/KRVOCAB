import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/vocab_word.dart';
import '../providers/review_provider.dart';
import '../providers/review_settings_provider.dart';
import '../providers/tts_settings_provider.dart';
import '../providers/vocab_provider.dart';
import '../services/llm_service.dart';
import '../services/tts_service.dart';
import '../theme/app_colors.dart';
import '../widgets/flashcard.dart';
import '../widgets/gold_button.dart';

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  /// null = neutral, true = correct, false = wrong.
  ///
  /// A ValueNotifier rather than plain state: per-keystroke match feedback
  /// only ever changes the input border, so we repaint just the TextField via
  /// a ValueListenableBuilder instead of calling setState and rebuilding the
  /// whole screen (flashcard, progress bar, action buttons) on every key.
  final ValueNotifier<bool?> _match = ValueNotifier<bool?>(null);
  Timer? _autoAdvance;

  /// Pending auto-pronunciation, held until the flip animation finishes.
  Timer? _speakTimer;

  /// True during the post-correct reinforcement window. While locked we
  /// ignore further keystrokes so the Korean IME can't dribble extra jamo
  /// into the field before the user advances.
  bool _locked = false;

  /// Example sentence shown after a correct answer.
  ({String korean, String english, String usedForm})? _example;
  bool _loadingExample = false;
  int _exampleRequestId = 0;

  @override
  void dispose() {
    _autoAdvance?.cancel();
    _speakTimer?.cancel();
    _controller.dispose();
    _focus.dispose();
    _match.dispose();
    super.dispose();
  }

  void _resetCardUi() {
    _autoAdvance?.cancel();
    // Leaving the card cancels its pending utterance — otherwise flicking
    // through a deck queues up a chorus of half-spoken words.
    _speakTimer?.cancel();
    TtsService.instance.stop();
    _exampleRequestId++; // discard any pending example response
    // Drop focus first — this terminates any pending IME composition so the
    // next requestFocus starts from a clean slate. Setting .value (not just
    // .text) also wipes the composing TextRange.
    _focus.unfocus();
    _controller.value = TextEditingValue.empty;
    _match.value = null;
    setState(() {
      _locked = false;
      _example = null;
      _loadingExample = false;
    });
    // Re-focus on the next frame, after the IME has fully detached.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _onChanged(String raw) {
    // During the 850 ms confirmation window the field is unfocused and
    // shouldn't receive any input — bail without touching the controller.
    // Fighting the IME from inside onChanged caused desyncs (visible text
    // and platform composition diverging), which is what surfaced as
    // ghost "달달"-style doubling.
    if (_locked) return;

    final state = ref.read(reviewProvider);
    final word = state.current;
    if (word == null) return;

    // Compare on Hangul. Trim whitespace; Hangul has no casing so no lowercasing.
    final typed = raw.trim();
    final target = word.hangul.trim();

    if (typed.isEmpty) {
      _match.value = null;
      return;
    }

    if (typed == target) {
      // Correct — record stats, lock input, fetch an example sentence
      // inline as reinforcement. No auto-advance: the user taps Next when
      // they've read it.
      HapticFeedback.lightImpact();
      ref.read(reviewProvider.notifier).markCorrect();
      _match.value = true;
      setState(() {
        _locked = true;
        _loadingExample = true;
        _example = null;
      });
      _focus.unfocus();
      _autoAdvance?.cancel();
      _fetchExample(word);
      return;
    }

    // Still typing a valid prefix → neutral; otherwise → wrong. Either way
    // only the border changes, so no setState.
    _match.value = target.startsWith(typed) ? null : false;
  }

  void _onSubmitted(String _) {
    final state = ref.read(reviewProvider);
    if (state.current == null) return;
    // Pressing Enter without a correct match counts as wrong + advance.
    if (!state.revealed) {
      ref.read(reviewProvider.notifier).markIncorrect();
    }
    _next();
  }

  void _next() {
    ref.read(reviewProvider.notifier).next();
    _resetCardUi();
  }

  void _previous() {
    ref.read(reviewProvider.notifier).previous();
    _resetCardUi();
  }

  void _restart() {
    HapticFeedback.mediumImpact();
    ref.read(reviewProvider.notifier).restart();
    _resetCardUi();
  }

  void _reveal() {
    ref.read(reviewProvider.notifier).reveal();
  }

  /// Speaks [word] once the card has finished turning.
  ///
  /// Platform channel calls run on the platform thread, which on Windows and
  /// macOS is also the UI thread — and the first utterance pays for the
  /// speech engine spinning up its voice and audio pipeline. Firing that
  /// during the flip drops frames right where they're most visible, so the
  /// utterance waits for the animation to land instead.
  void _speakAfterFlip(VocabWord word) {
    _speakTimer?.cancel();
    _speakTimer = Timer(
      Flashcard.flipDuration + const Duration(milliseconds: 40),
      () {
        if (!mounted) return;
        // The user may have moved on while the card was turning.
        final current = ref.read(reviewProvider).current;
        if (current?.id != word.id) return;
        TtsService.instance.speakWord(word);
      },
    );
  }

  Future<void> _fetchExample(VocabWord word) async {
    final myId = ++_exampleRequestId;
    final result = await LlmService.instance.generateOneExample(word.hangul);
    if (!mounted || myId != _exampleRequestId) return;
    setState(() {
      _loadingExample = false;
      _example = result;
    });
  }

  void _seeExamples(VocabWord word) {
    // Stash the word for the Examples tab to consume, switch tabs, and
    // also pre-select it so the picker shows the right word.
    ref.read(selectedWordProvider.notifier).state = word;
    ref.read(pendingExampleWordProvider.notifier).state = word;
    ref.read(activeTabProvider.notifier).state = 2;
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild the deck whenever a Review preference changes. Widget-level
    // `ref.listen` fires reliably (even while the Settings route is on top),
    // so toggling "Include reinforced words" / "Learning only" takes effect
    // immediately. Reset the card UI so we don't keep a now-stale card.
    ref.listen<bool>(includeReinforcementProvider, (_, __) {
      ref.read(reviewProvider.notifier).recomputeEligibility();
      _resetCardUi();
    });
    // Switching the active reinforcement group changes which reinforced words
    // are eligible — rebuild the deck.
    ref.listen<int>(reinforcementGroupProvider, (_, __) {
      ref.read(reviewProvider.notifier).recomputeEligibility();
      _resetCardUi();
    });
    ref.listen<bool>(learningOnlyProvider, (_, __) {
      ref.read(reviewProvider.notifier).recomputeEligibility();
      _resetCardUi();
    });

    // Speak the card the moment it turns to its answer side — whether the
    // user typed it correctly or gave up and tapped Reveal. Watching the
    // state transition (rather than hooking each of those paths) means a new
    // reveal route can't forget to make a sound.
    ref.listen<ReviewState>(reviewProvider, (prev, next) {
      if (!ref.read(autoSpeakProvider)) return;
      final w = next.current;
      if (w == null || !next.revealed) return;
      final wasRevealedForSameCard =
          prev != null && prev.revealed && prev.current?.id == w.id;
      if (wasRevealedForSameCard) return;
      _speakAfterFlip(w);
    });

    final state = ref.watch(reviewProvider);
    final word = state.current;

    if (word == null) {
      // Distinguish "no words at all" from "everything is reinforced and
      // reinforced words are currently excluded".
      final hasAnyWords = ref.watch(vocabProvider).isNotEmpty;
      final message = hasAnyWords
          ? 'Every word is marked reinforced 🎉\nTurn on "Include reinforced '
              'words" in Settings to keep reviewing them.'
          : 'Add a few words first — your review deck is empty.';
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: AppColors.mutedInk(context),
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          children: [
            // 1. Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: state.progress,
                minHeight: 6,
                backgroundColor: AppColors.inset(context),
                valueColor: const AlwaysStoppedAnimation(AppColors.antiqueGold),
              ),
            ),

            const SizedBox(height: 12),

            // 3. Status row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${state.correctThisSession}/${state.totalThisSession}',
                  style: GoogleFonts.inter(
                    color: AppColors.mutedInk(context),
                    fontSize: 12,
                    letterSpacing: 1.2,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.local_fire_department,
                        color: AppColors.deepGold, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '${state.streak}',
                      style: GoogleFonts.inter(
                        color: AppColors.deepGold,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Tooltip(
                      message: 'See example sentences for this word',
                      child: InkWell(
                        onTap: () => _seeExamples(word),
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.auto_awesome_outlined,
                            size: 16,
                            color: AppColors.deepGold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Tooltip(
                      message: 'Restart session',
                      child: InkWell(
                        onTap: _restart,
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.refresh,
                            size: 16,
                            color: AppColors.mutedInk(context),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 16),

            // 5. Flashcard fills remaining space
            Expanded(
              child: Center(
                child: Flashcard(word: word, revealed: state.revealed),
              ),
            ),

            const SizedBox(height: 20),

            // 7. Hangul input (system Korean IME composes jamo into syllable blocks)
            ValueListenableBuilder<bool?>(
              valueListenable: _match,
              builder: (context, match, _) {
                final borderColor = switch (match) {
                  true => AppColors.softGreen,
                  false => AppColors.softRed,
                  _ => AppColors.hairline(context),
                };
                return TextField(
                  controller: _controller,
                  focusNode: _focus,
                  autofocus: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  readOnly: _locked,
                  textAlign: TextAlign.center,
                  textInputAction: TextInputAction.done,
                  keyboardType: TextInputType.text,
                  onChanged: _onChanged,
                  onSubmitted: _onSubmitted,
                  style: GoogleFonts.notoSerifKr(
                    fontSize: 24,
                    color: AppColors.ink(context),
                    letterSpacing: 2.0,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    hintText: '한글을 입력하세요…',
                    hintStyle: GoogleFonts.notoSerifKr(
                      color: AppColors.mutedInk(context),
                      fontStyle: FontStyle.italic,
                      fontSize: 16,
                      letterSpacing: 1.0,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      borderSide: BorderSide(color: borderColor, width: 1.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      borderSide: BorderSide(color: borderColor, width: 2),
                    ),
                  ),
                );
              },
            ),

            if (_locked && (_loadingExample || _example != null)) ...[
              const SizedBox(height: 12),
              _ExamplePreview(
                loading: _loadingExample,
                example: _example,
                target: word.hangul,
              ),
            ],

            const SizedBox(height: 16),

            // 9. Action row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Tooltip(
                  message: 'Previous card',
                  child: _CircleBackButton(onTap: _previous),
                ),
                const SizedBox(width: 12),
                GoldOutlinedButton(
                  label: 'Reveal',
                  icon: Icons.visibility_outlined,
                  onPressed: state.revealed ? null : _reveal,
                ),
                const SizedBox(width: 12),
                GoldButton(
                  label: 'Next',
                  icon: Icons.arrow_forward,
                  onPressed: _next,
                ),
              ],
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _CircleBackButton extends StatelessWidget {
  const _CircleBackButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.antiqueGold, width: 1.2),
          ),
          child: const Icon(Icons.arrow_back, color: AppColors.deepGold, size: 18),
        ),
      ),
    );
  }
}

/// Compact inline reinforcement: one Korean sentence shown after a correct
/// answer. The English translation is hidden until the user taps to reveal it.
class _ExamplePreview extends StatefulWidget {
  const _ExamplePreview({
    required this.loading,
    required this.example,
    required this.target,
  });

  final bool loading;
  final ({String korean, String english, String usedForm})? example;
  final String target;

  @override
  State<_ExamplePreview> createState() => _ExamplePreviewState();
}

class _ExamplePreviewState extends State<_ExamplePreview> {
  bool _showEnglish = false;

  @override
  void didUpdateWidget(covariant _ExamplePreview old) {
    super.didUpdateWidget(old);
    // Re-hide the translation whenever a new example arrives (or starts
    // loading) so each card starts with the English concealed.
    if (widget.example != old.example || (widget.loading && !old.loading)) {
      _showEnglish = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final example = widget.example;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.champagne.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.antiqueGold.withValues(alpha: 0.5),
        ),
      ),
      child: widget.loading
          ? Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation(AppColors.antiqueGold),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'composing an example…',
                  style: GoogleFonts.inter(
                    color: AppColors.deepGold,
                    fontStyle: FontStyle.italic,
                    fontSize: 12,
                  ),
                ),
              ],
            )
          : example == null
              ? Text(
                  'No example available',
                  style: GoogleFonts.inter(
                    color: AppColors.mutedInk(context),
                    fontStyle: FontStyle.italic,
                    fontSize: 12,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _highlightTarget(
                      context,
                      example.korean,
                      [example.usedForm, widget.target],
                    ),
                    if (example.english.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () =>
                            setState(() => _showEnglish = !_showEnglish),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _showEnglish
                                    ? Icons.keyboard_arrow_up
                                    : Icons.translate,
                                size: 14,
                                color: AppColors.antiqueGold,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _showEnglish
                                    ? 'Hide translation'
                                    : 'Show translation',
                                style: GoogleFonts.inter(
                                  color: AppColors.antiqueGold,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_showEnglish)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            example.english,
                            style: GoogleFonts.inter(
                              color: AppColors.mutedInk(context),
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
    );
  }

  /// Underline any occurrence of the candidate [forms] in [korean]. We pass
  /// both the conjugated surface form the model reported and the dictionary
  /// form, so nouns (verbatim) and conjugated verbs/adjectives both highlight.
  Widget _highlightTarget(
      BuildContext context, String korean, List<String> forms) {
    final base = GoogleFonts.notoSerifKr(
      color: AppColors.ink(context),
      fontSize: 16,
      height: 1.4,
      fontWeight: FontWeight.w500,
    );

    final targets = forms.where((f) => f.trim().isNotEmpty).toList();
    if (targets.isEmpty || korean.isEmpty) return Text(korean, style: base);
    // Longest first so we don't underline a substring of a longer match.
    targets.sort((a, b) => b.length.compareTo(a.length));

    final matched = List<bool>.filled(korean.length, false);
    for (final t in targets) {
      var from = 0;
      while (true) {
        final idx = korean.indexOf(t, from);
        if (idx == -1) break;
        var clash = false;
        for (var k = idx; k < idx + t.length; k++) {
          if (matched[k]) {
            clash = true;
            break;
          }
        }
        if (!clash) {
          for (var k = idx; k < idx + t.length; k++) {
            matched[k] = true;
          }
        }
        from = idx + t.length;
      }
    }
    if (!matched.contains(true)) return Text(korean, style: base);

    final spans = <TextSpan>[];
    final buf = StringBuffer();
    bool? bufHi;
    void flush() {
      if (buf.isEmpty) return;
      spans.add(TextSpan(
        text: buf.toString(),
        style: bufHi == true
            ? const TextStyle(
                decoration: TextDecoration.underline,
                decorationColor: AppColors.antiqueGold,
                decorationThickness: 2,
                color: AppColors.deepGold,
              )
            : null,
      ));
      buf.clear();
    }

    for (var i = 0; i < korean.length; i++) {
      if (bufHi != null && matched[i] != bufHi) flush();
      bufHi = matched[i];
      buf.write(korean[i]);
    }
    flush();
    return RichText(text: TextSpan(style: base, children: spans));
  }
}
