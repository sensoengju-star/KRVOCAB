import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/vocab_word.dart';
import '../services/tts_service.dart';
import '../theme/app_colors.dart';
import 'dictionary_form.dart';
import 'gold_button.dart';

class VocabTile extends StatefulWidget {
  const VocabTile({
    super.key,
    required this.word,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onCycleStatus,
  });

  final VocabWord word;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onCycleStatus;

  @override
  State<VocabTile> createState() => _VocabTileState();
}

class _VocabTileState extends State<VocabTile> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final word = widget.word;
    final status = word.status;
    final accent = _accentFor(status);
    final radius = BorderRadius.circular(AppRadius.md);

    // No per-tile drop shadow at rest (Gaussian blur × 30+ tiles = first-paint
    // jank on the Vocab tab). The shadow is added only on hover, where at
    // most one tile pays for it.
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _pressed ? 0.988 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.surface(context),
            borderRadius: radius,
            border: Border.all(
              color: _hovered
                  ? AppColors.antiqueGold.withValues(alpha: 0.65)
                  : AppColors.hairline(context),
            ),
            boxShadow: _hovered ? AppColors.cardShadow(context) : null,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: radius,
            child: InkWell(
              borderRadius: radius,
              onTap: widget.onTap,
              onTapDown: (_) => setState(() => _pressed = true),
              onTapUp: (_) => setState(() => _pressed = false),
              onTapCancel: () => setState(() => _pressed = false),
              child: ClipRRect(
                borderRadius: radius,
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Status shows as a coloured spine rather than by
                      // recolouring the whole border — legible at a glance
                      // without shouting.
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: 4,
                        color: accent,
                      ),
                      Expanded(child: _body(context, word)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, VocabWord word) {
    final status = word.status;
    final accent = _accentFor(status);
    final posColor = AppColors.forPartOfSpeech(word.partOfSpeech);

    // Rearranged: the three actions moved out of a tall right-hand column
    // into a single row along the card's bottom edge, so the word, its
    // reading and its meaning get the full card width.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hangul and romanization share a baseline — the reading sits
                // beside the word instead of stacking under it.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: DictionaryForm(
                        word: word.hangul,
                        partOfSpeech: word.partOfSpeech,
                        style: GoogleFonts.notoSerifKr(
                          color: AppColors.ink(context),
                          fontSize: 25,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                    ),
                    if (word.romanization.trim().isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          word.romanization,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: AppColors.antiqueGold,
                            fontStyle: FontStyle.italic,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                // Generous margins above and below: at 23 px the polite form
                // is a second headword, and it crowds the reading above it
                // and the gloss below without room to breathe.
                if (word.politeForm.trim().isNotEmpty) ...[
                  const SizedBox(height: 13),
                  _PoliteChip(form: word.politeForm),
                  const SizedBox(height: 5),
                ],
                if (word.englishMeaning.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    word.englishMeaning,
                    style: GoogleFonts.inter(
                      color: AppColors.mutedInk(context),
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                // Bottom rail: part of speech + status on the left, the three
                // card actions on the right.
                Row(
                  children: [
                    _MetaPill(
                      label: PartsOfSpeech.label(word.partOfSpeech),
                      color: posColor,
                    ),
                    const SizedBox(width: 6),
                    _MetaPill(label: _statusLabel(status), color: accent),
                    const Spacer(),
                    TonalIconButton(
                      icon: Icons.volume_up_outlined,
                      tooltip: '발음 듣기',
                      color: AppColors.antiqueGold,
                      onPressed: () => TtsService.instance.speakWord(word),
                    ),
                    TonalIconButton(
                      icon: _iconFor(status),
                      tooltip: _tooltipFor(status),
                      color: accent,
                      onPressed: widget.onCycleStatus,
                    ),
                    TonalIconButton(
                      icon: Icons.edit_outlined,
                      tooltip: 'Edit word',
                      onPressed: widget.onEdit,
                    ),
                    TonalIconButton(
                      icon: Icons.delete_outline,
                      tooltip: 'Delete word',
                      color: AppColors.vermilion.withValues(alpha: 0.85),
                      onPressed: widget.onDelete,
                    ),
                  ],
                ),
                // The link sits on its own line at the foot of the card —
                // it describes the whole tile, not the chips beside it.
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: _hovered ? 1 : 0.7,
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Click to see meaning & examples',
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: AppColors.deepGold,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ),
                      AnimatedSlide(
                        offset: _hovered ? const Offset(0.22, 0) : Offset.zero,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        child: const Icon(Icons.chevron_right,
                            size: 15, color: AppColors.antiqueGold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Two states only: reinforced, or learning. The retired `learned` status
  /// (older data) presents as learning.
  bool _isReinforced(WordStatus s) => s == WordStatus.reinforcement;

  Color _accentFor(WordStatus s) => _isReinforced(s)
      ? AppColors.statusReinforcement
      : AppColors.statusLearning;

  String _statusLabel(WordStatus s) =>
      _isReinforced(s) ? 'reinforced' : 'learning';

  IconData _iconFor(WordStatus s) =>
      _isReinforced(s) ? Icons.autorenew : Icons.add_task;

  String _tooltipFor(WordStatus s) => _isReinforced(s)
      ? 'Reinforced — tap to move back to Learning'
      : 'Learning — tap to mark Reinforced';
}

/// 해요체 form shown as a tinted chip instead of a loose label + text pair.
class _PoliteChip extends StatelessWidget {
  const _PoliteChip({required this.form});
  final String form;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 15, 8),
      decoration: BoxDecoration(
        color: AppColors.goldTint(context),
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            '해요체',
            style: GoogleFonts.inter(
              color: AppColors.mutedInk(context),
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 9),
          // Sized to sit level with the dictionary form above it — the polite
          // form is what you actually say, so it shouldn't read as a footnote.
          Text(
            form,
            style: GoogleFonts.notoSerifKr(
              color: AppColors.deepGold,
              fontSize: 23,
              height: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small tinted label. [color] carries the meaning — part of speech gets its
/// own hue from the 오방색 set, status gets the status colour.
class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.tintOf(context, color),
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: AppColors.onSurfaceAccent(context, color),
          fontSize: 9.5,
          letterSpacing: 0.6,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
