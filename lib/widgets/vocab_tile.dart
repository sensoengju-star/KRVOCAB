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
    this.setAside = false,
  });

  final VocabWord word;

  /// The word belongs to a review set that is currently put aside. Only ever
  /// true while the list is showing archived words on purpose.
  final bool setAside;
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
    final card = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _pressed ? 0.988 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            // The card itself carries the word's status colour — a learning
            // word and a reinforced one are tellable apart at a glance even
            // when they sit side by side in the combined list.
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                AppColors.tintOf(context, accent),
                AppColors.surface(context),
              ],
              stops: const [0, 0.55],
            ),
            borderRadius: radius,
            border: Border.all(
              color: accent.withValues(alpha: _hovered ? 0.75 : 0.35),
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
                        width: 5,
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

    // An archived word is shown faded — present, but plainly not part of what
    // you're studying right now.
    return widget.setAside ? Opacity(opacity: 0.55, child: card) : card;
  }

  Widget _body(BuildContext context, VocabWord word) {
    final status = word.status;
    final accent = _accentFor(status);
    final posColor = AppColors.forPartOfSpeech(word.partOfSpeech);
    // Romanization follows the headword's hue, a shade lighter.
    final subtle = accent.withValues(alpha: 0.85);

    // Rearranged: the three actions moved out of a tall right-hand column
    // into a single row along the card's bottom edge, so the word, its
    // reading and its meaning get the full card width.
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 14, 10),
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
                        // The headword itself is neutral for BOTH types —
                        // white on the dark theme. The type is still obvious
                        // from the spine, the card wash, the chips and the
                        // romanization, so colouring the word too was noise.
                        //
                        // Light theme takes ink instead: the card there is
                        // white, and white-on-white would erase the word.
                        style: GoogleFonts.notoSerifKr(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : AppColors.charcoal,
                          fontSize: 32,
                          fontWeight: FontWeight.w600,
                          height: 1.22,
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
                            color: subtle,
                            fontStyle: FontStyle.italic,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (word.englishMeaning.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    word.englishMeaning,
                    style: GoogleFonts.inter(
                      color: AppColors.mutedInk(context),
                      fontSize: 15.5,
                      height: 1.45,
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
                    if (widget.setAside) ...[
                      const SizedBox(width: 6),
                      _MetaPill(
                          label: '보관됨', color: AppColors.mutedInk(context)),
                    ],
                    const Spacer(),
                    TonalIconButton(
                      icon: Icons.volume_up_outlined,
                      tooltip: '발음 듣기',
                      color: accent,
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
                            color: AppColors.onSurfaceAccent(context, accent),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ),
                      AnimatedSlide(
                        offset: _hovered ? const Offset(0.22, 0) : Offset.zero,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        child: Icon(Icons.chevron_right,
                            size: 17, color: accent),
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

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.tintOf(context, color),
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: AppColors.onSurfaceAccent(context, color),
          fontSize: 11,
          letterSpacing: 0.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
