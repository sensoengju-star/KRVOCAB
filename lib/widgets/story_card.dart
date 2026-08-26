import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/tts_settings_provider.dart';
import '../services/narration_service.dart';
import '../theme/app_colors.dart';

/// A short Korean story that weaves in several vocabulary words.
class VocabStory {
  VocabStory({
    required this.title,
    required this.korean,
    required this.romanization,
    required this.english,
    required this.wordsUsed,
    required this.usedForms,
  });

  final String title;
  final String korean;
  final String romanization;
  final String english;
  final List<String> wordsUsed;

  /// The words used in this story: `form` is the exact surface
  /// (conjugated/inflected) substring as written in [korean] — guaranteed
  /// present so it highlights reliably — and `word` is the dictionary word it
  /// came from, used to look up the stored definition for the hover tooltip.
  final List<({String form, String word})> usedForms;

  factory VocabStory.fromJson(Map<String, dynamic> j) => VocabStory(
        title: (j['title'] ?? '').toString(),
        korean: (j['korean'] ?? '').toString(),
        romanization: (j['romanization'] ?? '').toString(),
        english: (j['english'] ?? '').toString(),
        wordsUsed: ((j['words_used'] ?? j['wordsUsed']) as List?)
                ?.map((e) => e.toString())
                .where((e) => e.trim().isNotEmpty)
                .toList() ??
            const [],
        usedForms: _parseUsed(j['used'] ?? j['used_forms'] ?? j['surfaceForms']),
      );

  static List<({String form, String word})> _parseUsed(dynamic raw) {
    if (raw is! List) return const [];
    final out = <({String form, String word})>[];
    for (final e in raw) {
      if (e is Map) {
        final form = (e['form'] ?? e['surface'] ?? '').toString().trim();
        final word = (e['word'] ?? e['base'] ?? form).toString().trim();
        if (form.isNotEmpty) out.add((form: form, word: word));
      } else {
        // Back-compat: a plain string is both the form and the lookup key.
        final s = e.toString().trim();
        if (s.isNotEmpty) out.add((form: s, word: s));
      }
    }
    return out;
  }

  bool get isRenderable => korean.trim().isNotEmpty;
}

class StoryCard extends ConsumerStatefulWidget {
  const StoryCard({
    super.key,
    required this.story,
    required this.targets,
    this.glossary = const {},
  });

  final VocabStory story;

  /// All vocabulary Hangul words — every occurrence in the story body is
  /// highlighted so the learner can spot the words they're studying.
  final Set<String> targets;

  /// Dictionary Hangul → English meaning, used for the hover tooltip shown
  /// over a highlighted word.
  final Map<String, String> glossary;

  @override
  ConsumerState<StoryCard> createState() => _StoryCardState();
}

class _StoryCardState extends ConsumerState<StoryCard> {
  bool _showEnglish = false;

  /// Identifies this card to the shared narration player. Derived from the
  /// text itself — stories are generated, not stored, so they have no id.
  String get _storyId =>
      '${widget.story.title}#${widget.story.korean.hashCode}';

  List<String> get _sentences => splitSentences(widget.story.korean);

  @override
  Widget build(BuildContext context) {
    final s = widget.story;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.hairline(context)),
        boxShadow: AppColors.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (s.title.trim().isNotEmpty)
                Expanded(
                  child: Text(
                    s.title,
                    style: GoogleFonts.playfairDisplay(
                      color: AppColors.deepGold,
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                const Spacer(),
              _narrateButton(),
            ],
          ),
          const SizedBox(height: 10),
          _narratedBody(context),
          if (s.english.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            _toggleRow(
              context,
              label: 'Translation',
              open: _showEnglish,
              onTap: () => setState(() => _showEnglish = !_showEnglish),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  s.english,
                  style: GoogleFonts.inter(
                    color: AppColors.ink(context),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ),
              crossFadeState: _showEnglish
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 180),
            ),
          ],
        ],
      ),
    );
  }

  /// Play / pause for the whole story.
  Widget _narrateButton() {
    final controller = ref.read(narrationProvider);
    return ValueListenableBuilder<NarrationState>(
      valueListenable: controller,
      builder: (context, st, _) {
        final active = st.isActive(_storyId);
        final playing = active && st.playing;
        final loading = active && st.loading;

        return Tooltip(
          message: playing ? 'narration 멈추기' : '이야기 듣기',
          child: Material(
            color: playing
                ? AppColors.goldTint(context)
                : Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () {
                // Source is applied per play so a Settings change takes
                // effect on the next press without restarting the app.
                controller.source = ref.read(narrationSourceProvider);
                if (playing) {
                  controller.pause();
                } else {
                  controller.play(
                    _storyId,
                    _sentences,
                    from: active ? st.index : 0,
                  );
                }
              },
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation(AppColors.antiqueGold),
                        ),
                      )
                    : Icon(
                        playing
                            ? Icons.pause_circle_outline
                            : Icons.play_circle_outline,
                        color: AppColors.deepGold,
                        size: 24,
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// The story, one sentence per line so the line being spoken can be
  /// highlighted and any line can be tapped to hear it again.
  Widget _narratedBody(BuildContext context) {
    final controller = ref.read(narrationProvider);
    final sentences = _sentences;
    if (sentences.isEmpty) {
      return _buildKoreanHighlighted(context, widget.story.korean);
    }

    return ValueListenableBuilder<NarrationState>(
      valueListenable: controller,
      builder: (context, st, _) {
        final active = st.isActive(_storyId);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < sentences.length; i++)
              _SentenceLine(
                highlighted: active && st.index == i,
                onTap: () {
                  controller.source = ref.read(narrationSourceProvider);
                  controller.play(_storyId, sentences, from: i);
                },
                child: _buildKoreanHighlighted(context, sentences[i]),
              ),
            if (active && st.error != null) ...[
              const SizedBox(height: 8),
              Text(
                st.error!,
                style: GoogleFonts.inter(
                  color: AppColors.softRed,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _toggleRow(
    BuildContext context, {
    required String label,
    required bool open,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(
              open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              color: AppColors.antiqueGold,
              size: 18,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                color: AppColors.antiqueGold,
                fontWeight: FontWeight.w600,
                fontSize: 12,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKoreanHighlighted(BuildContext context, String korean) {
    final base = GoogleFonts.notoSerifKr(
      color: AppColors.ink(context),
      fontSize: 19,
      height: 1.6,
      fontWeight: FontWeight.w500,
    );

    // Build the highlightable terms with their English meaning. Two sources:
    //  - dictionary targets (nouns etc. that appear verbatim) → glossary[form]
    //  - the model-reported surface forms (conjugated verbs/adjectives), whose
    //    meaning is looked up via the base "word" they came from.
    final termMeaning = <String, String>{};
    void addTerm(String form, String meaning) {
      final f = form.trim();
      if (f.isEmpty) return;
      final existing = termMeaning[f];
      if (existing == null || existing.isEmpty) {
        termMeaning[f] = meaning.trim();
      }
    }

    for (final t in widget.targets) {
      addTerm(t, widget.glossary[t.trim()] ?? '');
    }
    for (final u in widget.story.usedForms) {
      addTerm(
        u.form,
        widget.glossary[u.word.trim()] ?? widget.glossary[u.form.trim()] ?? '',
      );
    }

    final terms = termMeaning.keys.toList();
    if (terms.isEmpty || korean.isEmpty) return Text(korean, style: base);
    // Longest first so we don't underline a substring of a longer match.
    terms.sort((a, b) => b.length.compareTo(a.length));

    // owner[i] = the term form claiming char i (null = not highlighted).
    final owner = List<String?>.filled(korean.length, null);
    for (final t in terms) {
      var from = 0;
      while (true) {
        final idx = korean.indexOf(t, from);
        if (idx == -1) break;
        var clash = false;
        for (var k = idx; k < idx + t.length; k++) {
          if (owner[k] != null) {
            clash = true;
            break;
          }
        }
        if (!clash) {
          for (var k = idx; k < idx + t.length; k++) {
            owner[k] = t;
          }
        }
        from = idx + t.length;
      }
    }
    if (!owner.any((o) => o != null)) return Text(korean, style: base);

    final hlStyle = base.copyWith(
      color: AppColors.deepGold,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.antiqueGold,
      decorationThickness: 2.2,
    );

    final spans = <InlineSpan>[];
    final buf = StringBuffer();
    String? curOwner;
    var started = false;

    void flush() {
      if (buf.isEmpty) return;
      final text = buf.toString();
      if (curOwner == null) {
        spans.add(TextSpan(text: text));
      } else {
        final meaning = termMeaning[curOwner] ?? '';
        final hl = Text(text, style: hlStyle);
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          // Tooltip shows on hover (desktop) and long-press (touch). Message
          // is JUST the English definition.
          child: meaning.isEmpty
              ? hl
              : Tooltip(
                  message: meaning,
                  waitDuration: const Duration(milliseconds: 150),
                  preferBelow: false,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    color: AppColors.surface(context),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.antiqueGold, width: 1.2),
                    boxShadow: const [AppColors.warmShadow],
                  ),
                  textStyle: GoogleFonts.inter(
                    color: AppColors.ink(context),
                    fontSize: 16,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                  child: hl,
                ),
        ));
      }
      buf.clear();
    }

    for (var i = 0; i < korean.length; i++) {
      final o = owner[i];
      if (started && o != curOwner) flush();
      started = true;
      curOwner = o;
      buf.write(korean[i]);
    }
    flush();

    return RichText(text: TextSpan(style: base, children: spans));
  }
}

/// One sentence of a story: tinted while it's being spoken, tappable to
/// replay from there.
class _SentenceLine extends StatelessWidget {
  const _SentenceLine({
    required this.highlighted,
    required this.onTap,
    required this.child,
  });

  final bool highlighted;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.xs),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: highlighted
                ? AppColors.goldTint(context)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
          child: child,
        ),
      ),
    );
  }
}
