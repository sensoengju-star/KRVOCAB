import 'package:flutter/material.dart';

import '../models/vocab_word.dart';
import '../theme/app_colors.dart';

/// Renders a vocabulary word, bracketing the citation ending of verbs and
/// descriptive verbs in its own colour: 가다 → 가**(다)**.
///
/// The point is that the ending is not part of the word you ever *say* — it's
/// the dictionary's citation marker. Splitting it off makes the stem (the
/// part that actually conjugates) the thing the eye lands on, and keeps the
/// learner from writing "그는 학교에 가다".
///
/// Non-verbs, and verbs that don't end in -다, render as plain text.
class DictionaryForm extends StatelessWidget {
  const DictionaryForm({
    super.key,
    required this.word,
    required this.partOfSpeech,
    required this.style,
    this.endingColor,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  final String word;
  final String partOfSpeech;

  /// Base style for the stem. The ending inherits it, overriding only colour
  /// (and dropping a little weight).
  final TextStyle style;

  /// Colour for the "(다)". Defaults to the part of speech's own accent.
  final Color? endingColor;

  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  /// True when [word] is a verb/descriptive verb in its -다 citation form.
  static bool hasCitationEnding(String word, String partOfSpeech) {
    final w = word.trim();
    final isVerb = partOfSpeech == PartsOfSpeech.verb ||
        partOfSpeech == PartsOfSpeech.descriptiveVerb;
    return isVerb && w.length > 1 && w.endsWith('다');
  }

  @override
  Widget build(BuildContext context) {
    final w = word.trim();
    if (!hasCitationEnding(w, partOfSpeech)) {
      return Text(
        word,
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    final accent = endingColor ??
        AppColors.onSurfaceAccent(
            context, AppColors.forPartOfSpeech(partOfSpeech));

    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: w.substring(0, w.length - 1)),
          TextSpan(
            text: '(다)',
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
