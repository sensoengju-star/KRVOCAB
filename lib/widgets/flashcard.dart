import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/vocab_word.dart';
import '../theme/app_colors.dart';
import 'dictionary_form.dart';

/// Flashcard with a simple cross-dissolve reveal. English on the front,
/// Hangul + romanization on the back.
class Flashcard extends StatefulWidget {
  const Flashcard({super.key, required this.word, required this.revealed});

  /// How long the reveal takes. Public so callers can sequence work around
  /// it — the Review screen waits this out before speaking, since a platform
  /// channel call lands on the UI thread on desktop and would stutter the
  /// animation.
  static const Duration revealDuration = Duration(milliseconds: 320);

  final VocabWord word;
  final bool revealed;

  @override
  State<Flashcard> createState() => _FlashcardState();
}

// TickerProvider (not SingleTicker): this state drives two controllers —
// the reveal and the new-card entrance.
class _FlashcardState extends State<Flashcard>
    with TickerProviderStateMixin {
  // 320 ms: quick enough to feel instant when you're drilling a deck, still
  // long enough to register as a change rather than a jump cut.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Flashcard.revealDuration,
  );
  late final Animation<double> _anim =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  /// Separate from the reveal: advancing to a new word used to swap the card's
  /// contents instantly, which read as a jump cut between questions. The new
  /// card now arrives with its own short entrance.
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: 1,
  );
  late final Animation<double> _enterAnim =
      CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic);

  @override
  void didUpdateWidget(covariant Flashcard old) {
    super.didUpdateWidget(old);
    if (widget.revealed != old.revealed) {
      if (widget.revealed) {
        _c.forward();
      } else {
        _c.reverse();
      }
    }
    if (widget.word.id != old.word.id) {
      // Show the new word's question side, then play it in.
      _c.value = 0;
      _enter.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Build both faces ONCE per widget-build and reuse the same instances
    // across every animation frame. The AnimatedBuilder closure only wraps
    // them in a fresh Opacity/Transform each tick, so the face subtrees (and
    // their GoogleFonts text styles) aren't rebuilt 60x during the reveal.
    final front = _CardFace(child: _FrontFace(word: widget.word));
    final back = _CardFace(child: _BackFace(word: widget.word));

    return RepaintBoundary(
      child: AnimatedBuilder(
        // Both animations drive the same subtree, so listen to the pair.
        animation: Listenable.merge([_anim, _enter]),
        builder: (_, __) {
          final v = _anim.value;
          final isBack = v > 0.5;

          // Two phases so the faces never overlap: the outgoing one fades to
          // nothing by the midpoint, then the incoming one fades up. Blending
          // two different words on top of each other just looks muddy.
          final t = isBack ? (v - 0.5) * 2 : 1 - (v * 2);
          final opacity = t.clamp(0.0, 1.0);

          // A touch of scale so it settles rather than simply appearing.
          final scale = 0.97 + (0.03 * opacity);

          // The entrance slides the card up a few pixels as it fades in, so a
          // new question feels handed to you rather than teleported in.
          final enter = _enterAnim.value;
          return Opacity(
            opacity: opacity * enter,
            child: Transform.translate(
              offset: Offset(0, 14 * (1 - enter)),
              child: Transform.scale(
                scale: scale,
                child: isBack ? back : front,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CardFace extends StatelessWidget {
  const _CardFace({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.raised(context),
            AppColors.goldTint(context),
          ],
          stops: const [0.55, 1],
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.hairline(context), width: 1),
        boxShadow: AppColors.cardShadow(context),
      ),
      child: Center(child: child),
    );
  }
}

class _PosPill extends StatelessWidget {
  const _PosPill({required this.pos});
  final String pos;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: AppColors.goldTint(context),
        border: Border.all(
          color: AppColors.antiqueGold.withValues(alpha: 0.45),
          width: 1,
        ),
      ),
      child: Text(
        PartsOfSpeech.label(pos).toUpperCase(),
        style: GoogleFonts.inter(
          color: AppColors.deepGold,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

class _FrontFace extends StatelessWidget {
  const _FrontFace({required this.word});
  final VocabWord word;

  @override
  Widget build(BuildContext context) {
    final english =
        word.englishMeaning.trim().isEmpty ? '—' : word.englishMeaning;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'MEANING',
          style: GoogleFonts.inter(
            color: AppColors.antiqueGold,
            fontWeight: FontWeight.w600,
            fontSize: 10,
            letterSpacing: 3.0,
          ),
        ),
        const SizedBox(height: 18),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              english,
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(
                color: AppColors.ink(context),
                fontWeight: FontWeight.w600,
                fontSize: 38,
                height: 1.2,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        _PosPill(pos: word.partOfSpeech),
      ],
    );
  }
}

class _BackFace extends StatelessWidget {
  const _BackFace({required this.word});
  final VocabWord word;

  @override
  Widget build(BuildContext context) {
    // Defensive fallback: if hangul is empty, surface romanization instead.
    final hasHangul = word.hangul.trim().isNotEmpty;
    final primary = hasHangul ? word.hangul : word.romanization;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 10),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: DictionaryForm(
              word: primary,
              // Romanization fallback isn't a dictionary form — pass a
              // non-verb code so it renders plain.
              partOfSpeech: hasHangul ? word.partOfSpeech : '',
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSerifKr(
                color: AppColors.ink(context),
                fontWeight: FontWeight.w500,
                fontSize: 56,
                height: 1.1,
                letterSpacing: 4.0,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (hasHangul && word.romanization.trim().isNotEmpty)
          Text(
            word.romanization,
            style: GoogleFonts.playfairDisplay(
              color: AppColors.deepGold,
              fontStyle: FontStyle.italic,
              fontSize: 20,
              letterSpacing: 1.5,
            ),
          ),
        if (word.politeForm.trim().isNotEmpty) ...[
          const SizedBox(height: 22),
          Text(
            '해요체',
            style: GoogleFonts.inter(
              color: AppColors.antiqueGold,
              fontWeight: FontWeight.w600,
              fontSize: 10,
              letterSpacing: 3.0,
            ),
          ),
          const SizedBox(height: 6),
          // Rendered at near-headword scale: the polite form is the one the
          // learner actually speaks, so it carries the same weight as the
          // dictionary form above it.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                word.politeForm,
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSerifKr(
                  color: AppColors.deepGold,
                  fontWeight: FontWeight.w500,
                  fontSize: 40,
                  height: 1.15,
                  letterSpacing: 2.0,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        // The answer side repeats the English meaning, so a revealed card is
        // a complete entry on its own — no flipping back to check what it
        // was you were being asked for.
        if (word.englishMeaning.trim().isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            width: 26,
            height: 1,
            color: AppColors.antiqueGold.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 14),
          Flexible(
            child: Text(
              word.englishMeaning,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: AppColors.ink(context),
                fontSize: 17,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        _PosPill(pos: word.partOfSpeech),
      ],
    );
  }
}
