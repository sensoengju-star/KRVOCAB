import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/block_entry.dart';
import '../providers/block_review_provider.dart';
import '../providers/blocks_provider.dart';
import '../providers/vocab_provider.dart';
import '../services/hangul.dart';
import '../theme/app_colors.dart';
import '../widgets/gold_button.dart';

/// "Blocks" tab — a flip-only drill for recognizing Hangul syllable blocks as
/// single units. Front shows the block (작), tap Reveal to flip to its sound
/// (jak). Blocks are added manually; the romanization auto-fills.
class BlocksScreen extends ConsumerStatefulWidget {
  const BlocksScreen({super.key});

  @override
  ConsumerState<BlocksScreen> createState() => _BlocksScreenState();
}

class _BlocksScreenState extends ConsumerState<BlocksScreen> {
  void _reveal() => ref.read(blockReviewProvider.notifier).reveal();
  void _next() => ref.read(blockReviewProvider.notifier).next();
  void _previous() => ref.read(blockReviewProvider.notifier).previous();

  void _restart() {
    HapticFeedback.mediumImpact();
    ref.read(blockReviewProvider.notifier).restart();
  }

  Future<void> _confirmDeleteCurrent(BlockEntry block) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${block.block}?',
            style: GoogleFonts.playfairDisplay(fontSize: 18)),
        content: Text('This removes the block from your collection.',
            style: GoogleFonts.inter(fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove',
                  style: TextStyle(color: AppColors.softRed))),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(blocksProvider.notifier).delete(block.id);
    }
  }

  void _openAdd() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddBlockSheet(),
    );
  }

  void _openSearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _BlocksSearchSheet(),
    );
  }

  void _openWordsWithBlock(String block) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WordsWithBlockSheet(block: block),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(blockReviewProvider);
    final block = state.current;

    return Stack(
      children: [
        if (block == null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'No blocks yet — tap ＋ to add one.\n'
                'Type a syllable and its sound fills in automatically.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: AppColors.mutedInk(context),
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
            ),
          )
        else
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: state.progress,
                      minHeight: 4,
                      backgroundColor:
                          AppColors.hairline(context).withValues(alpha: 0.5),
                      valueColor:
                          const AlwaysStoppedAnimation(AppColors.antiqueGold),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${state.position} / ${state.total}',
                        style: GoogleFonts.inter(
                          color: AppColors.mutedInk(context),
                          fontSize: 12,
                          letterSpacing: 1.2,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Tooltip(
                            message: 'Words using this block',
                            child: InkWell(
                              onTap: () => _openWordsWithBlock(block.block),
                              borderRadius: BorderRadius.circular(20),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(Icons.menu_book_outlined,
                                    size: 16,
                                    color: AppColors.mutedInk(context)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Tooltip(
                            message: 'Search blocks',
                            child: InkWell(
                              onTap: _openSearch,
                              borderRadius: BorderRadius.circular(20),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(Icons.search,
                                    size: 16,
                                    color: AppColors.mutedInk(context)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Tooltip(
                            message: 'Remove this block',
                            child: InkWell(
                              onTap: () => _confirmDeleteCurrent(block),
                              borderRadius: BorderRadius.circular(20),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(Icons.delete_outline,
                                    size: 16,
                                    color: AppColors.mutedInk(context)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Tooltip(
                            message: 'Shuffle / restart',
                            child: InkWell(
                              onTap: _restart,
                              borderRadius: BorderRadius.circular(20),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(Icons.refresh,
                                    size: 16,
                                    color: AppColors.mutedInk(context)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Center(
                      child: GestureDetector(
                        // Single tap always advances. Use "Reveal" to flip and
                        // check the sound in place.
                        onTap: _next,
                        child: _BlockFlashcard(
                            block: block, revealed: state.revealed),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    state.revealed
                        ? 'tap the card or Next for the next block'
                        : 'Reveal to check · tap the card or Next to continue',
                    style: GoogleFonts.inter(
                      color: AppColors.mutedInk(context),
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Tooltip(
                        message: 'Previous block',
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
          ),
        Positioned(
          right: 24,
          bottom: 24,
          child: _AddFab(onTap: _openAdd),
        ),
      ],
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
          child:
              const Icon(Icons.arrow_back, color: AppColors.deepGold, size: 18),
        ),
      ),
    );
  }
}

class _AddFab extends StatelessWidget {
  const _AddFab({required this.onTap});
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
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.goldGradient,
            boxShadow: AppColors.floatShadow(context),
          ),
          child: const Icon(Icons.add, color: Colors.white, size: 27),
        ),
      ),
    );
  }
}

/// 3D Y-axis flip card. Front = syllable block, back = romanization.
class _BlockFlashcard extends StatefulWidget {
  const _BlockFlashcard({required this.block, required this.revealed});
  final BlockEntry block;
  final bool revealed;

  @override
  State<_BlockFlashcard> createState() => _BlockFlashcardState();
}

class _BlockFlashcardState extends State<_BlockFlashcard>
    with SingleTickerProviderStateMixin {
  // Matches the vocabulary flashcard's 320 ms flip.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final Animation<double> _anim =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void didUpdateWidget(covariant _BlockFlashcard old) {
    super.didUpdateWidget(old);
    if (widget.revealed != old.revealed) {
      if (widget.revealed) {
        _c.forward();
      } else {
        _c.reverse();
      }
    }
    if (widget.block.id != old.block.id) {
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
    final front = _Face(
      child: Text(
        widget.block.block,
        style: GoogleFonts.notoSerifKr(
          color: AppColors.ink(context),
          fontWeight: FontWeight.w500,
          fontSize: 96,
          height: 1.0,
        ),
      ),
    );
    final back = _Face(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'SOUND',
            style: GoogleFonts.inter(
              color: AppColors.antiqueGold,
              fontWeight: FontWeight.w600,
              fontSize: 10,
              letterSpacing: 3.0,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            widget.block.roman,
            style: GoogleFonts.playfairDisplay(
              color: AppColors.deepGold,
              fontStyle: FontStyle.italic,
              fontSize: 56,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );

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

class _Face extends StatelessWidget {
  const _Face({required this.child});
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

/// Add-block bottom sheet. The romanization auto-fills from the typed block
/// (and can still be overridden by hand).
class _AddBlockSheet extends ConsumerStatefulWidget {
  const _AddBlockSheet();

  @override
  ConsumerState<_AddBlockSheet> createState() => _AddBlockSheetState();
}

class _AddBlockSheetState extends ConsumerState<_AddBlockSheet> {
  final _block = TextEditingController();
  final _roman = TextEditingController();
  bool _romanEdited = false;
  bool _saving = false;

  @override
  void dispose() {
    _block.dispose();
    _roman.dispose();
    super.dispose();
  }

  void _onBlockChanged(String v) {
    // Auto-fill romanization unless the user has typed their own.
    if (!_romanEdited) {
      _roman.text = Hangul.romanize(v.trim());
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final block = _block.text.trim();
    if (block.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a Hangul block')),
      );
      return;
    }
    var roman = _roman.text.trim();
    if (roman.isEmpty) roman = Hangul.romanize(block);

    // Duplicate warning — same block already in the collection.
    final dupes =
        ref.read(blocksProvider).where((b) => b.block.trim() == block).toList();
    if (dupes.isNotEmpty) {
      final addAnyway = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('"$block" is already a block',
              style: GoogleFonts.playfairDisplay(fontSize: 18)),
          content: Text(
            'You already have this block (${dupes.first.roman}). '
            'Add it again anyway?',
            style: GoogleFonts.inter(fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add anyway'),
            ),
          ],
        ),
      );
      if (addAnyway != true) return;
      if (!mounted) return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(blocksProvider.notifier).add(
            BlockEntry(
              id: 'b-${DateTime.now().millisecondsSinceEpoch}',
              block: block,
              roman: roman,
              dateAdded: DateTime.now(),
            ),
          );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (err) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $err')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: AppColors.hairline(context)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.champagne,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Add a block',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 22,
                  color: AppColors.ink(context),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.0,
                )),
            const SizedBox(height: 6),
            Text(
              'Type a Hangul block — its sound fills in automatically.',
              style: GoogleFonts.inter(
                color: AppColors.mutedInk(context),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _block,
              autofocus: true,
              onChanged: _onBlockChanged,
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSerifKr(
                fontSize: 40,
                fontWeight: FontWeight.w500,
                color: AppColors.ink(context),
              ),
              decoration: const InputDecoration(
                labelText: 'Block (한글)',
                hintText: '작',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _roman,
              onChanged: (_) => _romanEdited = true,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 22,
                color: AppColors.deepGold,
                fontStyle: FontStyle.italic,
              ),
              decoration: const InputDecoration(
                labelText: 'Sound (romanization)',
                hintText: 'jak',
              ),
            ),
            const SizedBox(height: 24),
            GoldButton(
              label: _saving ? 'Saving…' : 'Save',
              onPressed: _saving ? null : _save,
              expanded: true,
            ),
          ],
        ),
      ),
    );
  }
}

/// Searchable list of all blocks. Tap a result to jump the review to it, or
/// delete it. Search matches the block or its romanization.
class _BlocksSearchSheet extends ConsumerStatefulWidget {
  const _BlocksSearchSheet();

  @override
  ConsumerState<_BlocksSearchSheet> createState() => _BlocksSearchSheetState();
}

class _BlocksSearchSheetState extends ConsumerState<_BlocksSearchSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(blocksProvider);
    final q = _q.trim().toLowerCase();
    final filtered = q.isEmpty
        ? all
        : all
            .where((b) =>
                b.block.toLowerCase().contains(q) ||
                b.roman.toLowerCase().contains(q))
            .toList();

    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final maxH = MediaQuery.of(context).size.height * 0.7;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxH),
        decoration: BoxDecoration(
          color: AppColors.surface(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: AppColors.hairline(context)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.champagne,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search,
                    color: AppColors.antiqueGold, size: 20),
                hintText: 'Search ${all.length} blocks…',
              ),
            ),
            const SizedBox(height: 12),
            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Text(
                  'No matching blocks',
                  style: GoogleFonts.inter(
                    color: AppColors.mutedInk(context),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) {
                    final b = filtered[i];
                    return InkWell(
                      onTap: () {
                        ref.read(blockReviewProvider.notifier).jumpTo(b.id);
                        Navigator.pop(context);
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 10),
                        child: Row(
                          children: [
                            Text(
                              b.block,
                              style: GoogleFonts.notoSerifKr(
                                color: AppColors.ink(context),
                                fontSize: 26,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                b.roman,
                                style: GoogleFonts.inter(
                                  color: AppColors.antiqueGold,
                                  fontStyle: FontStyle.italic,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: Icon(Icons.delete_outline,
                                  size: 18, color: AppColors.mutedInk(context)),
                              onPressed: () => ref
                                  .read(blocksProvider.notifier)
                                  .delete(b.id),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Lists every vocabulary word whose Hangul contains the selected [block],
/// with that block underlined in each word.
class _WordsWithBlockSheet extends ConsumerWidget {
  const _WordsWithBlockSheet({required this.block});
  final String block;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = ref
        .watch(vocabProvider)
        .where((w) => w.hangul.contains(block))
        .toList();

    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final maxH = MediaQuery.of(context).size.height * 0.7;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxH),
        decoration: BoxDecoration(
          color: AppColors.surface(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: AppColors.hairline(context)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.champagne,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('Words with ',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 20,
                      color: AppColors.ink(context),
                      fontWeight: FontWeight.w600,
                    )),
                Text(block,
                    style: GoogleFonts.notoSerifKr(
                      fontSize: 22,
                      color: AppColors.deepGold,
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(width: 8),
                Text('· ${matches.length}',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppColors.mutedInk(context),
                    )),
              ],
            ),
            const SizedBox(height: 12),
            if (matches.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No vocabulary words contain this block.',
                  style: GoogleFonts.inter(
                    color: AppColors.mutedInk(context),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  itemCount: matches.length,
                  itemBuilder: (ctx, i) {
                    final w = matches[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _highlightBlock(context, w.hangul, block),
                          const SizedBox(height: 2),
                          Text(
                            '${w.romanization}  —  ${w.englishMeaning}',
                            style: GoogleFonts.inter(
                              color: AppColors.mutedInk(context),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _highlightBlock(BuildContext context, String hangul, String block) {
    final base = GoogleFonts.notoSerifKr(
      color: AppColors.ink(context),
      fontSize: 22,
      fontWeight: FontWeight.w600,
    );
    if (block.isEmpty || !hangul.contains(block)) {
      return Text(hangul, style: base);
    }
    final spans = <TextSpan>[];
    var rest = hangul;
    while (rest.isNotEmpty) {
      final idx = rest.indexOf(block);
      if (idx == -1) {
        spans.add(TextSpan(text: rest));
        break;
      }
      if (idx > 0) spans.add(TextSpan(text: rest.substring(0, idx)));
      spans.add(TextSpan(
        text: block,
        style: const TextStyle(
          color: AppColors.deepGold,
          decoration: TextDecoration.underline,
          decorationColor: AppColors.antiqueGold,
          decorationThickness: 2,
        ),
      ));
      rest = rest.substring(idx + block.length);
    }
    return RichText(text: TextSpan(style: base, children: spans));
  }
}
