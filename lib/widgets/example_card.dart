import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';

class ExampleSentence {
  ExampleSentence({
    required this.korean,
    required this.romanization,
    required this.english,
    required this.breakdown,
  });

  final String korean;
  final String romanization;
  final String english;
  final List<BreakdownItem> breakdown;

  factory ExampleSentence.fromJson(Map<String, dynamic> j) => ExampleSentence(
        korean: (j['korean'] ?? '').toString(),
        romanization: (j['romanization'] ?? '').toString(),
        english: (j['english'] ?? '').toString(),
        breakdown: ((j['breakdown'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => BreakdownItem(
                  word: (e['word'] ?? '').toString(),
                  meaning: (e['meaning'] ?? '').toString(),
                ))
            .toList(),
      );
}

class BreakdownItem {
  BreakdownItem({required this.word, required this.meaning});
  final String word;
  final String meaning;
}

class ExampleCard extends StatefulWidget {
  const ExampleCard({super.key, required this.sentence, required this.target});
  final ExampleSentence sentence;
  final String target;

  @override
  State<ExampleCard> createState() => _ExampleCardState();
}

class _ExampleCardState extends State<ExampleCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline(context)),
        boxShadow: const [AppColors.warmShadow],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildKoreanWithUnderline(context),
          const SizedBox(height: 10),
          Text(
            widget.sentence.romanization,
            style: GoogleFonts.inter(
              color: AppColors.mutedInk(context),
              fontStyle: FontStyle.italic,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.sentence.english,
            style: GoogleFonts.inter(
              color: AppColors.ink(context),
              fontSize: 14,
              height: 1.45,
            ),
          ),
          if (widget.sentence.breakdown.isNotEmpty) ...[
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      _open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      color: AppColors.antiqueGold,
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Breakdown',
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
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final b in widget.sentence.breakdown)
                      _BreakdownChip(item: b),
                  ],
                ),
              ),
              crossFadeState:
                  _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildKoreanWithUnderline(BuildContext context) {
    final korean = widget.sentence.korean;
    final t = widget.target;
    final base = GoogleFonts.notoSerifKr(
      color: AppColors.ink(context),
      fontSize: 20,
      height: 1.4,
      fontWeight: FontWeight.w500,
    );
    if (t.isEmpty || !korean.contains(t)) {
      return Text(korean, style: base);
    }
    final spans = <TextSpan>[];
    var rest = korean;
    while (rest.isNotEmpty) {
      final idx = rest.indexOf(t);
      if (idx == -1) {
        spans.add(TextSpan(text: rest));
        break;
      }
      if (idx > 0) spans.add(TextSpan(text: rest.substring(0, idx)));
      spans.add(TextSpan(
        text: t,
        style: TextStyle(
          decoration: TextDecoration.underline,
          decorationColor: AppColors.antiqueGold,
          decorationThickness: 2.2,
          color: AppColors.deepGold,
        ),
      ));
      rest = rest.substring(idx + t.length);
    }
    return RichText(text: TextSpan(style: base, children: spans));
  }
}

class _BreakdownChip extends StatelessWidget {
  const _BreakdownChip({required this.item});
  final BreakdownItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.champagne.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.antiqueGold.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            item.word,
            style: GoogleFonts.notoSerifKr(
              color: AppColors.deepGold,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            item.meaning,
            style: GoogleFonts.inter(
              color: AppColors.ink(context),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
