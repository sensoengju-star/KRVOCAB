import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/vocab_word.dart';
import '../theme/app_colors.dart';
import 'dictionary_form.dart';

/// 3D Y-axis flip flashcard. English on the front, Hangul + romanization
/// on the back.
class Flashcard extends StatefulWidget {
  const Flashcard({super.key, required this.word, required this.revealed});

  /// How long the flip takes. Public so callers can sequence work around it —
  /// the Review screen waits this out before speaking, since a platform
  /// channel call lands on the UI thread on desktop and would stutter the
  /// animation.
  static const Duration flipDuration = Duration(milliseconds: 320);

  final VocabWord word;
  final bool revealed;

  @override
  State<Flashcard> createState() => _FlashcardState();
}

class _FlashcardState extends State<Flashcard>
    with SingleTickerProviderStateMixin {
  // 320 ms: quick enough to feel instant when you're drilling a deck, still
  // long enough to read as a flip rather than a swap.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Flashcard.flipDuration,
  );
  late final Animation<double> _anim =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

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
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Build both faces ONCE per widget-build and reuse the same instances
    // across every animation frame. The AnimatedBuilder closure only wraps
    // them in a fresh Transform each tick, so the face subtrees (and their
    // GoogleFonts text styles) aren't rebuilt 60× during the flip.
    final front = _CardFace(child: _FrontFace(word: widget.word));
    final back = _CardFace(child: _BackFace(word: widget.word));
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _anim,
        builder: (_, __) {
          final v = _anim.value;
          final angle = v * math.pi;
          final isBack = v > 0.5;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0015)
              ..rotateY(angle),
            child: isBack
                ? Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(math.pi),
                    child: back,
                  )
                : front,
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
