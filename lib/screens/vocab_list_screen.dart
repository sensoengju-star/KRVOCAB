import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../models/vocab_word.dart';
import '../providers/vocab_provider.dart';
import '../providers/word_set_provider.dart';
import '../services/hangul.dart';
import '../services/llm_launcher.dart';
import '../services/llm_service.dart';
import '../theme/app_colors.dart';
import '../widgets/gold_button.dart';
import '../widgets/vocab_tile.dart';
import '../widgets/word_sets_sheet.dart';
import 'word_detail_screen.dart';

class VocabListScreen extends ConsumerStatefulWidget {
  const VocabListScreen({super.key});

  @override
  ConsumerState<VocabListScreen> createState() => _VocabListScreenState();
}

class _VocabListScreenState extends ConsumerState<VocabListScreen> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  /// Drives the clear button only — kept separate from the (debounced) query
  /// so the ✕ appears the instant the user types.
  bool _hasSearchText = false;

  /// Filters start folded away so the words themselves get the screen. The
  /// compact bar still shows whether any filter is active.
  bool _filtersOpen = false;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    final has = v.isNotEmpty;
    if (has != _hasSearchText) setState(() => _hasSearchText = has);
    // Debounce so 1000-row filtering doesn't fire on every keystroke.
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 120), () {
      if (mounted) ref.read(searchQueryProvider.notifier).state = v;
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() => _hasSearchText = false);
    ref.read(searchQueryProvider.notifier).state = '';
  }

  Future<void> _confirmDelete(VocabWord w) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${w.hangul}?',
            style: GoogleFonts.playfairDisplay(fontSize: 18)),
        content: Text('This will remove the word from your collection.',
            style: GoogleFonts.inter(fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete', style: TextStyle(color: AppColors.softRed))),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(vocabProvider.notifier).delete(w.id);
    }
  }

  /// Tapping a word opens its own page — meaning, usage, related words and
  /// example sentences, all explained in Korean.
  void _openWordPage(VocabWord w) {
    ref.read(selectedWordProvider.notifier).state = w;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => WordDetailScreen(wordId: w.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    var words = ref.watch(filteredVocabProvider);
    final pos = ref.watch(posFilterProvider);
    final section = ref.watch(vocabSectionProvider);
    final counts = ref.watch(vocabCountsProvider);
    final groupByBlock = ref.watch(groupByBlockProvider);
    final blockFilter = ref.watch(blockFilterProvider);
    final combined = ref.watch(combinedViewProvider);
    final daily = ref.watch(dailyWordsProvider);
    final setAside = ref.watch(setAsideIdsProvider);
    final sets = ref.watch(wordSetsProvider);
    final showSetAside = ref.watch(showSetAsideProvider);
    // The combined list is today's draw — unless a search or filter is on,
    // in which case it falls back to the whole collection (see
    // filteredVocabProvider).
    final dailyActive = combined &&
        daily.ready &&
        daily.ids.isNotEmpty &&
        ref.watch(searchQueryProvider).trim().isEmpty &&
        pos == null &&
        blockFilter == null;

    // Group pagination — active on the Learning and Reinforcement tabs (both
    // in groups of 25), and only when there's more than one group's worth of
    // words. The selected group on each tab is also what the Stories tab
    // draws from.
    // Group pagination belongs to a single-type list; the combined view
    // shows everything at once (the list is lazily built either way).
    final isReinforce = !combined && section == VocabSection.reinforcement;
    final isLearning = !combined && section == VocabSection.learning;
    final groupSize =
        isReinforce ? reinforcementGroupSize : learningGroupSize;
    final groupProvider =
        isReinforce ? reinforcementGroupProvider : learningGroupProvider;
    final showGroupPicker =
        (isLearning || isReinforce) && words.length > groupSize;
    final groupCount = (words.length / groupSize).ceil();
    var group = ref.watch(groupProvider);
    if (showGroupPicker) {
      // Clamp out-of-range index without firing setState during build —
      // schedule the correction for after the frame.
      if (group >= groupCount) {
        group = 0;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) ref.read(groupProvider.notifier).state = 0;
        });
      }
      final start = group * groupSize;
      final end = (start + groupSize).clamp(0, words.length);
      words = words.sublist(start, end);
    }

    return Stack(
      children: [
        Column(
          children: [
            // Rearranged: search, sections and part-of-speech filters are now
            // one control panel under the header instead of three loose bands
            // stacked down the page. Search leads, because it's what you reach
            // for first.
            Container(
              margin: const EdgeInsets.fromLTRB(12, 6, 12, 4),
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              decoration: BoxDecoration(
                color: AppColors.surface(context),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.hairline(context)),
              ),
              child: Column(
                children: [
            // Always-visible row: search plus the filter disclosure. Anything
            // that isn't search lives behind it, so the list gets the space.
            Row(
              children: [
                Expanded(
                  child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                // The field accepts Hangul, so it's set in the Korean face.
                style: GoogleFonts.notoSerifKr(fontSize: 14),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search,
                      color: AppColors.antiqueGold, size: 19),
                  hintText: '단어 검색…',
                  hintStyle: GoogleFonts.notoSerifKr(
                    color: AppColors.mutedInk(context),
                    fontSize: 14,
                  ),
                  suffixIcon: _hasSearchText
                      ? IconButton(
                          tooltip: '검색 지우기',
                          icon: Icon(Icons.close,
                              size: 17, color: AppColors.mutedInk(context)),
                          onPressed: _clearSearch,
                        )
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 9),
                  // Fully rounded — a search field should read as a pill.
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide(color: AppColors.hairline(context)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: const BorderSide(
                        color: AppColors.antiqueGold, width: 1.6),
                  ),
                  ),
                ),
                ),
                const SizedBox(width: 6),
                // Which words are listed — always reachable, since it's the
                // switch you actually flip while studying.
                _TypeDropdown(
                  combined: combined,
                  section: section,
                  learning: counts.learning,
                  reinforced: counts.reinforcement,
                  total: counts.total,
                  onChanged: (c, sec) {
                    ref.read(combinedViewProvider.notifier).state = c;
                    if (sec != null) {
                      ref.read(vocabSectionProvider.notifier).state = sec;
                    }
                  },
                ),
                const SizedBox(width: 6),
                _FilterDisclosure(
                  open: _filtersOpen,
                  activeCount: (pos != null ? 1 : 0) +
                      (blockFilter != null ? 1 : 0) +
                      (groupByBlock ? 1 : 0),
                  onTap: () => setState(() => _filtersOpen = !_filtersOpen),
                ),
              ],
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 200),
              sizeCurve: Curves.easeOutCubic,
              crossFadeState: _filtersOpen
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Column(
                children: [
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(2, 8, 2, 4),
                children: [
                  for (final p in PartsOfSpeech.all)
                    Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: _FilterChip(
                        label: PartsOfSpeech.label(p),
                        color: AppColors.forPartOfSpeech(p),
                        active: pos == p,
                        onTap: () => ref
                            .read(posFilterProvider.notifier)
                            .state = (pos == p ? null : p),
                      ),
                    ),
                ],
              ),
            ),
            // Block tools: group the list by each word's first block, and
            // filter down to the words that use one specific block.
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 2, 2, 4),
              child: Row(
                children: [
                  Expanded(
                    child: _BlockGroupToggle(
                      on: groupByBlock,
                      onChanged: (v) =>
                          ref.read(groupByBlockProvider.notifier).state = v,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _BlockFilterButton(
                    block: blockFilter,
                    onTap: _openBlockPicker,
                    onClear: () =>
                        ref.read(blockFilterProvider.notifier).state = null,
                  ),
                ],
              ),
            ),
                ],
              ),
            ),
                ],
              ),
            ),
            if (!combined &&
                section == VocabSection.learning &&
                !showGroupPicker &&
                words.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                child: _ExportSectionRow(
                  label: 'Learning',
                  icon: Icons.school_outlined,
                  count: words.length,
                  onCopy: () async {
                    final text = _buildNumberedHangul(words);
                    await Clipboard.setData(ClipboardData(text: text));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              'Copied ${words.length} learning word${words.length == 1 ? '' : 's'} to clipboard'),
                        ),
                      );
                    }
                  },
                  onShare: () async {
                    final text = _buildNumberedHangul(words);
                    await Share.share(
                      text,
                      subject: 'Maldari — Learning words',
                    );
                  },
                ),
              ),
            if (!combined &&
                section == VocabSection.reinforcement &&
                !showGroupPicker &&
                words.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                child: _ExportSectionRow(
                  label: 'Reinforcement',
                  icon: Icons.autorenew,
                  count: words.length,
                  onCopy: () async {
                    final text = _buildNumberedHangul(words);
                    await Clipboard.setData(ClipboardData(text: text));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              'Copied ${words.length} reinforcement word${words.length == 1 ? '' : 's'} to clipboard'),
                        ),
                      );
                    }
                  },
                  onShare: () async {
                    final text = _buildNumberedHangul(words);
                    await Share.share(
                      text,
                      subject: 'Maldari — Reinforcement words',
                    );
                  },
                ),
              ),
            // Words held in a review set are hidden from the list. Say so
            // where the missing words would have been, with the switch that
            // brings them back — otherwise they just look deleted.
            //
            // Shown whenever ANY set exists, not just when words are hidden:
            // it is the list's only door to the shelf, and switching every
            // set back on used to take that door away with it.
            if (sets.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
                child: _SetAsideStrip(
                  count: setAside.length,
                  setCount: sets.length,
                  showing: showSetAside,
                  onToggle: () => ref
                      .read(showSetAsideProvider.notifier)
                      .state = !showSetAside,
                  onOpenShelf: () => WordSetsSheet.show(context),
                ),
              ),
            if (combined && daily.ready && counts.total > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                child: _DailySetBanner(
                  shown: words.length,
                  cycleShown: daily.cycleShown,
                  total: counts.total,
                  active: dailyActive,
                  onShuffle: () =>
                      ref.read(dailyWordsProvider.notifier).reshuffle(),
                ),
              ),
            // Combined view — copy/share the full list with Korean, English
            // and (for verbs) the present polite form.
            if (combined && words.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                child: _ExportSectionRow(
                  label: 'Learning + Reinforced',
                  icon: Icons.copy_all_outlined,
                  count: words.length,
                  onCopy: () async {
                    final text = _buildDetailedExport(words);
                    await Clipboard.setData(ClipboardData(text: text));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              'Copied ${words.length} word${words.length == 1 ? '' : 's'} to clipboard'),
                        ),
                      );
                    }
                  },
                  onShare: () async {
                    final text = _buildDetailedExport(words);
                    await Share.share(text, subject: 'Maldari — vocabulary');
                  },
                ),
              ),
            if (showGroupPicker)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                child: _GroupPicker(
                  group: group,
                  groupCount: groupCount,
                  groupSize: groupSize,
                  total: isReinforce ? counts.reinforcement : counts.learning,
                  note: isReinforce
                      ? 'This group is what appears in the review deck and in '
                          'Stories.'
                      : 'Stories can weave this group into its stories.',
                  onChanged: (g) =>
                      ref.read(groupProvider.notifier).state = g,
                  onCopy: () async {
                    final text = _buildNumberedHangul(words);
                    await Clipboard.setData(ClipboardData(text: text));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              'Copied group ${group + 1} (${words.length} words) to clipboard'),
                        ),
                      );
                    }
                  },
                  onShare: () async {
                    final text = _buildNumberedHangul(words);
                    await Share.share(
                      text,
                      subject:
                          'Maldari — ${isReinforce ? 'Reinforcement' : 'Learning'} group ${group + 1}',
                    );
                  },
                ),
              ),
            const SizedBox(height: 6),
            Expanded(
              child: words.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(40, 24, 40, 60),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.goldTint(context),
                              ),
                              child: Icon(
                                blockFilter == null
                                    ? Icons.local_florist_outlined
                                    : Icons.search_off,
                                color: AppColors.antiqueGold,
                                size: 28,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              // A filter that matches nothing isn't an empty
                              // collection — say which one is hiding the words.
                              blockFilter != null
                                  ? '"$blockFilter" 블록을 쓰는 단어가 여기에 없어요.'
                                  : _emptyMessage(section),
                              textAlign: TextAlign.center,
                              // Playfair has no Hangul, so the Korean message
                              // takes the Korean serif instead.
                              style: blockFilter != null
                                  ? GoogleFonts.notoSerifKr(
                                      color: AppColors.mutedInk(context),
                                      fontSize: 15,
                                      height: 1.5,
                                    )
                                  : GoogleFonts.playfairDisplay(
                                      color: AppColors.mutedInk(context),
                                      fontSize: 17,
                                      height: 1.45,
                                      fontStyle: FontStyle.italic,
                                    ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Builder(
                      builder: (ctx) {
                        // Grouping flattens to a single item list of headers
                        // and words, so the whole thing stays one lazily-built
                        // ListView rather than nested scrollables.
                        final rows = groupByBlock
                            ? _groupByFirstBlock(words)
                            : [for (final w in words) _WordRow(w)];
                        return ListView.builder(
                          padding: const EdgeInsets.only(bottom: 100, top: 4),
                          itemCount: rows.length,
                          // Reduce off-screen tile builds during first paint.
                          cacheExtent: 300,
                          addAutomaticKeepAlives: false,
                          addRepaintBoundaries: true,
                          itemBuilder: (ctx, i) {
                            final row = rows[i];
                            if (row is _BlockHeaderRow) {
                              return _BlockHeader(
                                block: row.block,
                                count: row.count,
                                onTap: () => ref
                                    .read(blockFilterProvider.notifier)
                                    .state = row.block.isEmpty ? null : row.block,
                              );
                            }
                            final w = (row as _WordRow).word;
                            return VocabTile(
                              word: w,
                              setAside: setAside.contains(w.id),
                              onTap: () => _openWordPage(w),
                              onEdit: () => _openEdit(w),
                              onDelete: () => _confirmDelete(w),
                              onCycleStatus: () => ref
                                  .read(vocabProvider.notifier)
                                  .cycleStatus(w.id),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
        Positioned(
          right: 24,
          bottom: 24,
          child: _AddFab(onTap: _openAddSheet),
        ),
      ],
    );
  }

  void _openBlockPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _BlockPickerSheet(),
    );
  }

  void _openAddSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AddWordSheet(),
    );
  }

  void _openEdit(VocabWord w) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddWordSheet(existing: w),
    );
  }
}

/// One row of the (optionally grouped) list.
sealed class _ListRow {
  const _ListRow();
}

class _WordRow extends _ListRow {
  const _WordRow(this.word);
  final VocabWord word;
}

class _BlockHeaderRow extends _ListRow {
  const _BlockHeaderRow(this.block, this.count);

  /// Empty for words that don't start with a Hangul block.
  final String block;
  final int count;
}

/// Buckets [words] by their first syllable block, preserving each bucket's
/// internal order and sorting the buckets by block. Words with no leading
/// Hangul block collect in a trailing group.
List<_ListRow> _groupByFirstBlock(List<VocabWord> words) {
  final buckets = <String, List<VocabWord>>{};
  for (final w in words) {
    buckets.putIfAbsent(firstBlockOf(w.hangul), () => []).add(w);
  }
  final keys = buckets.keys.toList()
    ..sort((a, b) {
      if (a.isEmpty) return 1; // "no block" always last
      if (b.isEmpty) return -1;
      return a.compareTo(b);
    });
  return [
    for (final k in keys) ...[
      _BlockHeaderRow(k, buckets[k]!.length),
      for (final w in buckets[k]!) _WordRow(w),
    ],
  ];
}

/// Sticky-looking header above each block group: the block itself, its
/// romanization, and how many words start with it. Tapping filters to it.
class _BlockHeader extends StatelessWidget {
  const _BlockHeader({
    required this.block,
    required this.count,
    required this.onTap,
  });

  final String block;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final roman = block.isEmpty ? '' : Hangul.romanizeSyllable(block);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.xs),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.goldTint(context),
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                  child: Text(
                    block.isEmpty ? '—' : block,
                    style: GoogleFonts.notoSerifKr(
                      color: AppColors.deepGold,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                if (roman.isNotEmpty)
                  Text(
                    roman,
                    style: GoogleFonts.inter(
                      color: AppColors.antiqueGold,
                      fontSize: 12.5,
                      fontStyle: FontStyle.italic,
                    ),
                  )
                else
                  Text(
                    'other',
                    style: GoogleFonts.inter(
                      color: AppColors.mutedInk(context),
                      fontSize: 12.5,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    height: 1,
                    color: AppColors.hairline(context),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '$count',
                  style: GoogleFonts.inter(
                    color: AppColors.mutedInk(context),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Toggle for "group by first block".
class _BlockGroupToggle extends StatelessWidget {
  const _BlockGroupToggle({required this.on, required this.onChanged});
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.xs),
        onTap: () => onChanged(!on),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: on ? AppColors.goldTint(context) : AppColors.inset(context),
            borderRadius: BorderRadius.circular(AppRadius.xs),
            border: Border.all(
              color: on
                  ? AppColors.antiqueGold.withValues(alpha: 0.6)
                  : AppColors.hairline(context),
            ),
          ),
          child: Row(
            children: [
              Icon(
                on ? Icons.segment : Icons.sort,
                size: 16,
                color: on ? AppColors.deepGold : AppColors.mutedInk(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '첫 블록으로 묶기',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSerifKr(
                    color: on ? AppColors.deepGold : AppColors.mutedInk(context),
                    fontSize: 12.5,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // A compact track/knob rather than a full Switch, which would
              // tower over this row.
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 30,
                height: 17,
                padding: const EdgeInsets.all(2),
                alignment: on ? Alignment.centerRight : Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: on
                      ? AppColors.antiqueGold
                      : AppColors.hairline(context),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: on ? Colors.white : AppColors.surface(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the block picker, or shows/clears the block currently filtered on.
class _BlockFilterButton extends StatelessWidget {
  const _BlockFilterButton({
    required this.block,
    required this.onTap,
    required this.onClear,
  });

  final String? block;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final active = block != null;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.xs),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.fromLTRB(10, 6, active ? 4 : 10, 6),
          decoration: BoxDecoration(
            color: active ? AppColors.goldTint(context) : AppColors.inset(context),
            borderRadius: BorderRadius.circular(AppRadius.xs),
            border: Border.all(
              color: active
                  ? AppColors.antiqueGold.withValues(alpha: 0.6)
                  : AppColors.hairline(context),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.grid_view_outlined,
                size: 15,
                color: active ? AppColors.deepGold : AppColors.mutedInk(context),
              ),
              const SizedBox(width: 7),
              Text(
                active ? block! : '블록 검색',
                style: GoogleFonts.notoSerifKr(
                  color: active ? AppColors.deepGold : AppColors.mutedInk(context),
                  fontSize: active ? 16 : 12.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              if (active)
                TonalIconButton(
                  icon: Icons.close,
                  tooltip: '블록 필터 지우기',
                  color: AppColors.deepGold,
                  size: 14,
                  onPressed: onClear,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _emptyMessage(VocabSection s) {
  switch (s) {
    case VocabSection.learning:
      return 'Your hangul garden awaits 🌸';
    case VocabSection.reinforcement:
      return 'No reinforced words yet — tap the ↻ icon on any card to keep it '
          'in rotation.';
  }
}

/// Opens and closes the filter panel, badging how many filters are on so a
/// hidden filter can never quietly narrow the list.
class _FilterDisclosure extends StatelessWidget {
  const _FilterDisclosure({
    required this.open,
    required this.activeCount,
    required this.onTap,
  });

  final bool open;
  final int activeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final on = open || activeCount > 0;
    return Tooltip(
      message: open ? '필터 접기' : '필터 펼치기',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.xs),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: on ? AppColors.goldTint(context) : AppColors.inset(context),
              borderRadius: BorderRadius.circular(AppRadius.xs),
              border: Border.all(
                color: on
                    ? AppColors.antiqueGold.withValues(alpha: 0.6)
                    : AppColors.hairline(context),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.tune,
                  size: 16,
                  color: on ? AppColors.deepGold : AppColors.mutedInk(context),
                ),
                if (activeCount > 0) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.deepGold,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$activeCount',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 3),
                AnimatedRotation(
                  turns: open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: 16,
                    color:
                        on ? AppColors.deepGold : AppColors.mutedInk(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact copy / share row used by single-section tabs (Reinforcement
/// today; reusable for any future "export this section" need).
class _ExportSectionRow extends StatelessWidget {
  const _ExportSectionRow({
    required this.label,
    required this.count,
    required this.onCopy,
    required this.onShare,
    this.icon = Icons.autorenew,
  });

  final String label;
  final IconData icon;
  final int count;
  final VoidCallback onCopy;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.inset(context),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.hairline(context)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
      child: Row(
        children: [
          Icon(icon, size: 15, color: AppColors.antiqueGold),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: AppColors.ink(context),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _CountBadge(count: count),
          const Spacer(),
          TonalIconButton(
            icon: Icons.copy_outlined,
            tooltip: 'Copy these words to clipboard',
            color: AppColors.deepGold,
            size: 16,
            onPressed: onCopy,
          ),
          TonalIconButton(
            icon: Icons.ios_share,
            tooltip: 'Share these words',
            color: AppColors.deepGold,
            size: 16,
            onPressed: onShare,
          ),
        ],
      ),
    );
  }
}

/// Small pill showing how many words an action covers.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.goldTint(context),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$count',
        style: GoogleFonts.inter(
          color: AppColors.deepGold,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Plain numbered list of every word's Hangul — same format as the
/// Examples-tab full export, just over a subset.
String _buildNumberedHangul(List<VocabWord> words) {
  final buf = StringBuffer();
  for (var i = 0; i < words.length; i++) {
    buf.writeln('${i + 1}. ${words[i].hangul}');
  }
  return buf.toString().trimRight();
}

/// Numbered list with Korean, English meaning, and — for verbs/adjectives that
/// have one — the present polite form: `1. 가다 — to go (가요)`.
String _buildDetailedExport(List<VocabWord> words) {
  final buf = StringBuffer();
  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    final line = StringBuffer('${i + 1}. ${w.hangul}');
    if (w.englishMeaning.trim().isNotEmpty) {
      line.write(' — ${w.englishMeaning.trim()}');
    }
    if (w.politeForm.trim().isNotEmpty) {
      line.write(' (${w.politeForm.trim()})');
    }
    buf.writeln(line.toString());
  }
  return buf.toString().trimRight();
}

/// Group dropdown — paginates a section [groupSize] words at a time and
/// exposes copy/share actions over the current group. Used by both the
/// Learned (10s) and Reinforcement (25s) tabs.
/// The header for the combined list's daily draw.
///
/// It answers the two questions the ten words raise: why are there only ten,
/// and how much of the collection is left before they start repeating.
/// Header strip shown whenever some words are held in a put-aside set.
///
/// It exists so an archived word never reads as a deleted one: it names how
/// many are hidden, brings them back into view temporarily, and offers the
/// shelf where a whole set is switched back on for good.
class _SetAsideStrip extends StatelessWidget {
  const _SetAsideStrip({
    required this.count,
    required this.setCount,
    required this.showing,
    required this.onToggle,
    required this.onOpenShelf,
  });

  /// Words currently hidden. Zero when every set is switched back on — the
  /// strip stays put and simply changes what it says.
  final int count;

  /// How many sets exist at all.
  final int setCount;

  final bool showing;
  final VoidCallback onToggle;
  final VoidCallback onOpenShelf;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
      decoration: BoxDecoration(
        color: AppColors.inset(context),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.hairline(context)),
      ),
      child: Row(
        children: [
          Icon(Icons.inventory_2_outlined,
              size: 15, color: AppColors.mutedInk(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              count == 0
                  ? '보관한 세트 $setCount개 · 모두 복습 중이에요'
                  : showing
                      ? '보관 중인 단어 $count개를 함께 보는 중'
                      : '보관 중인 단어 $count개는 숨겨져 있어요',
              style: GoogleFonts.notoSerifKr(
                color: AppColors.mutedInk(context),
                fontSize: 12,
              ),
            ),
          ),
          // Nothing to reveal when nothing is hidden — but the strip itself
          // stays, so the shelf is still one tap away.
          if (count > 0)
            TextButton(
              onPressed: onToggle,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.antiqueGold,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: Text(
                showing ? '숨기기' : '보기',
                style: GoogleFonts.notoSerifKr(
                    fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          Tooltip(
            message: '보관한 세트 열기',
            child: IconButton(
              onPressed: onOpenShelf,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.chevron_right,
                  size: 18,
                  color: count == 0
                      ? AppColors.antiqueGold
                      : AppColors.mutedInk(context)),
            ),
          ),
        ],
      ),
    );
  }
}

class _DailySetBanner extends StatelessWidget {
  const _DailySetBanner({
    required this.shown,
    required this.cycleShown,
    required this.total,
    required this.active,
    required this.onShuffle,
  });

  /// How many words are on screen.
  final int shown;

  /// Words already spent in the current cycle.
  final int cycleShown;

  /// The whole collection.
  final int total;

  /// False while a search or filter has suspended the draw.
  final bool active;

  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : (cycleShown / total).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.goldTint(context),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
            color: AppColors.antiqueGold.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(
            active ? Icons.today_outlined : Icons.search,
            size: 17,
            color: AppColors.antiqueGold,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  active ? '오늘의 단어 $shown개' : '검색 중 — 전체 단어에서 찾는 중',
                  style: GoogleFonts.notoSerifKr(
                    color: AppColors.ink(context),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  active
                      ? '매일 새로 뽑혀요 · 이번 주기 $cycleShown / $total'
                      : '검색이나 필터를 지우면 오늘의 단어로 돌아가요',
                  style: GoogleFonts.notoSerifKr(
                    color: AppColors.mutedInk(context),
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
                if (active) ...[
                  const SizedBox(height: 7),
                  // How much of the collection this rotation has covered. It
                  // resets when every word has had its day.
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor:
                          AppColors.antiqueGold.withValues(alpha: 0.16),
                      valueColor: const AlwaysStoppedAnimation(
                          AppColors.antiqueGold),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (active)
            IconButton(
              tooltip: '다시 뽑기',
              icon: const Icon(Icons.casino_outlined,
                  size: 18, color: AppColors.antiqueGold),
              onPressed: onShuffle,
            ),
        ],
      ),
    );
  }
}

class _GroupPicker extends StatelessWidget {
  const _GroupPicker({
    required this.group,
    required this.groupCount,
    required this.groupSize,
    required this.total,
    required this.onChanged,
    required this.onCopy,
    required this.onShare,
    this.note,
  });
  final int group;
  final int groupCount;
  final int groupSize;
  final int total;
  final String? note;
  final ValueChanged<int> onChanged;
  final VoidCallback onCopy;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.inset(context),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.hairline(context)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.layers_outlined,
                  size: 15, color: AppColors.antiqueGold),
              const SizedBox(width: 9),
              Text(
                'Group',
                style: GoogleFonts.inter(
                  color: AppColors.ink(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                ),
              ),
              const Spacer(),
              DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: group,
                  isDense: true,
                  icon: const Icon(Icons.unfold_more,
                      size: 18, color: AppColors.antiqueGold),
                  style: GoogleFonts.inter(
                    color: AppColors.ink(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  items: [
                    for (var i = 0; i < groupCount; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text(_labelFor(i)),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) onChanged(v);
                  },
                ),
              ),
              const SizedBox(width: 4),
              TonalIconButton(
                icon: Icons.copy_outlined,
                tooltip: 'Copy this group to clipboard',
                color: AppColors.deepGold,
                size: 16,
                onPressed: onCopy,
              ),
              TonalIconButton(
                icon: Icons.ios_share,
                tooltip: 'Share this group',
                color: AppColors.deepGold,
                size: 16,
                onPressed: onShare,
              ),
            ],
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 8, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  note!,
                  style: GoogleFonts.inter(
                    color: AppColors.mutedInk(context),
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _labelFor(int i) {
    final start = i * groupSize + 1;
    final endIfFull = start + groupSize - 1;
    final end = endIfFull > total ? total : endIfFull;
    return 'Group ${i + 1}  ·  $start–$end';
  }
}

/// Part-of-speech chip. Each part of speech owns a colour from the 오방색
/// set, so the filter row doubles as the legend for the coloured chips on
/// every card.
/// Picks what the list shows: both types together, or one on its own.
///
/// Lives in the always-visible row rather than the filter panel — switching
/// between learning and reinforced words is the thing you do constantly, and
/// having to unfold a panel for it every time was the wrong trade.
class _TypeDropdown extends StatelessWidget {
  const _TypeDropdown({
    required this.combined,
    required this.section,
    required this.learning,
    required this.reinforced,
    required this.total,
    required this.onChanged,
  });

  final bool combined;
  final VocabSection section;
  final int learning;
  final int reinforced;
  final int total;

  /// (combined, section) — section is null when picking the combined view.
  final void Function(bool combined, VocabSection? section) onChanged;

  Color get _color => combined
      ? AppColors.plum
      : (section == VocabSection.reinforcement
          ? AppColors.statusReinforcement
          : AppColors.statusLearning);

  String get _label => combined
      ? '함께'
      : (section == VocabSection.reinforcement ? '복습' : '학습');

  int get _count => combined
      ? total
      : (section == VocabSection.reinforcement ? reinforced : learning);

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: '무엇을 볼까요',
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        side: BorderSide(color: AppColors.hairline(context)),
      ),
      color: AppColors.surface(context),
      onSelected: (v) {
        switch (v) {
          case 0:
            onChanged(true, null);
            break;
          case 1:
            onChanged(false, VocabSection.learning);
            break;
          case 2:
            onChanged(false, VocabSection.reinforcement);
            break;
        }
      },
      itemBuilder: (context) => [
        _item(context, 0, '함께 보기', 'both together', total,
            AppColors.plum, combined),
        _item(context, 1, '학습 중', 'learning', learning,
            AppColors.statusLearning,
            !combined && section == VocabSection.learning),
        _item(context, 2, '복습 중', 'reinforced', reinforced,
            AppColors.statusReinforcement,
            !combined && section == VocabSection.reinforcement),
      ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(9, 8, 4, 8),
        decoration: BoxDecoration(
          color: AppColors.tintOf(context, _color),
          borderRadius: BorderRadius.circular(AppRadius.xs),
          border: Border.all(color: _color.withValues(alpha: 0.55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: _color),
            ),
            const SizedBox(width: 7),
            Text(
              _label,
              style: GoogleFonts.notoSerifKr(
                color: AppColors.onSurfaceAccent(context, _color),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '$_count',
              style: GoogleFonts.inter(
                color: AppColors.mutedInk(context),
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Icon(Icons.arrow_drop_down,
                size: 18, color: AppColors.antiqueGold),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<int> _item(
    BuildContext context,
    int value,
    String korean,
    String english,
    int count,
    Color color,
    bool selected,
  ) {
    return PopupMenuItem<int>(
      value: value,
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                korean,
                style: GoogleFonts.notoSerifKr(
                  color: selected
                      ? AppColors.onSurfaceAccent(context, color)
                      : AppColors.ink(context),
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              Text(
                english,
                style: GoogleFonts.inter(
                  color: AppColors.mutedInk(context),
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Text(
            '$count',
            style: GoogleFonts.inter(
              color: AppColors.mutedInk(context),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (selected) ...[
            const SizedBox(width: 8),
            const Icon(Icons.check, size: 15, color: AppColors.deepGold),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.active,
    required this.color,
    required this.onTap,
  });
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.fromLTRB(active ? 9 : 13, 7, 13, 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: active ? color : AppColors.inset(context),
            border: Border.all(
              color: active
                  ? Colors.transparent
                  : AppColors.tintOf(context, color),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (active) ...[
                const Icon(Icons.check, size: 13, color: Colors.white),
                const SizedBox(width: 5),
              ] else ...[
                // A colour dot marks which hue this part of speech owns.
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                ),
                const SizedBox(width: 7),
              ],
              Text(
                label,
                style: GoogleFonts.inter(
                  color: active ? Colors.white : AppColors.mutedInk(context),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddFab extends StatefulWidget {
  const _AddFab({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_AddFab> createState() => _AddFabState();
}

class _AddFabState extends State<_AddFab> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _down ? 0.93 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _down = true),
          onTapUp: (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
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
      ),
    );
  }
}

/// Picks the syllable block to filter the list by. Lists every block the
/// collection actually uses, most-used first, and can be narrowed by typing
/// a block or its romanization.
class _BlockPickerSheet extends ConsumerStatefulWidget {
  const _BlockPickerSheet();

  @override
  ConsumerState<_BlockPickerSheet> createState() => _BlockPickerSheetState();
}

class _BlockPickerSheetState extends ConsumerState<_BlockPickerSheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _choose(String? block) {
    ref.read(blockFilterProvider.notifier).state = block;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(blockFilterProvider);
    final all = ref.watch(blockUsageProvider);
    final q = _query.text.trim().toLowerCase();
    final blocks = q.isEmpty
        ? all
        : [
            for (final b in all)
              if (b.block.contains(q) ||
                  Hangul.romanizeSyllable(b.block).toLowerCase().contains(q))
                b,
          ];

    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.72,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface(context),
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadius.xl)),
          border: Border.all(color: AppColors.hairline(context)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
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
            const SizedBox(height: 14),
            Text(
              '블록으로 찾기',
              style: GoogleFonts.notoSerifKr(
                fontSize: 20,
                color: AppColors.ink(context),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '이 블록이 들어간 단어만 보여 줘요 — 학 → 학교, 대학, 학생',
              style: GoogleFonts.notoSerifKr(
                fontSize: 12.5,
                color: AppColors.mutedInk(context),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _query,
              onChanged: (_) => setState(() {}),
              style: GoogleFonts.notoSerifKr(fontSize: 15),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search,
                    color: AppColors.antiqueGold, size: 19),
                hintText: '블록 또는 로마자 (예: 학, hak)',
                hintStyle: _sheetHint(context),
                contentPadding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
            const SizedBox(height: 14),
            if (selected != null) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: GoldOutlinedButton(
                  label: '필터 지우기  ($selected)',
                  icon: Icons.close,
                  onPressed: () => _choose(null),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Flexible(
              child: blocks.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Text(
                        all.isEmpty
                            ? '아직 한글 블록이 없어요.'
                            : '해당하는 블록이 없어요.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.notoSerifKr(
                          color: AppColors.mutedInk(context),
                          fontSize: 14,
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final b in blocks)
                            _BlockChip(
                              block: b.block,
                              count: b.count,
                              selected: b.block == selected,
                              onTap: () => _choose(b.block),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockChip extends StatelessWidget {
  const _BlockChip({
    required this.block,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String block;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.xs),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(11, 7, 11, 8),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.goldTint(context)
                : AppColors.inset(context),
            borderRadius: BorderRadius.circular(AppRadius.xs),
            border: Border.all(
              color: selected
                  ? AppColors.antiqueGold
                  : AppColors.hairline(context),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    block,
                    style: GoogleFonts.notoSerifKr(
                      color: selected
                          ? AppColors.deepGold
                          : AppColors.ink(context),
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$count',
                    style: GoogleFonts.inter(
                      color: AppColors.mutedInk(context),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Text(
                Hangul.romanizeSyllable(block),
                style: GoogleFonts.inter(
                  color: AppColors.antiqueGold,
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chooses whether the word being added or edited goes to the Learning or
/// the Reinforced list. Uses the same two colours the tiles do, so the choice
/// here reads as the colour you'll see in the list afterwards.
class _StatusPicker extends StatelessWidget {
  const _StatusPicker({required this.status, required this.onChanged});

  final WordStatus status;
  final ValueChanged<WordStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget option(WordStatus value, String korean, String english, Color color) {
      final active = value == status;
      final radius = BorderRadius.circular(AppRadius.xs);
      return Expanded(
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: () => onChanged(value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              decoration: BoxDecoration(
                color: active ? AppColors.tintOf(context, color) : null,
                borderRadius: radius,
                border: Border.all(
                  color: active ? color.withValues(alpha: 0.7) : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active
                          ? color
                          : color.withValues(alpha: 0.35),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          korean,
                          style: GoogleFonts.notoSerifKr(
                            color: active
                                ? AppColors.onSurfaceAccent(context, color)
                                : AppColors.mutedInk(context),
                            fontSize: 14,
                            fontWeight:
                                active ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                        Text(
                          english,
                          style: GoogleFonts.inter(
                            color: AppColors.mutedInk(context),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '어디에 넣을까요',
          style: GoogleFonts.notoSerifKr(
            color: AppColors.mutedInk(context),
            fontSize: 12.5,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.inset(context),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: AppColors.hairline(context)),
          ),
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              option(WordStatus.learning, '학습 중', 'Learning',
                  AppColors.statusLearning),
              option(WordStatus.reinforcement, '복습 중', 'Reinforced',
                  AppColors.statusReinforcement),
            ],
          ),
        ),
      ],
    );
  }
}

/// The add/edit sheet is written in Korean, so its labels and hints need the
/// Korean face rather than the theme's Inter defaults.
TextStyle _sheetLabel(BuildContext context) => GoogleFonts.notoSerifKr(
      color: AppColors.mutedInk(context),
      fontSize: 14,
    );

TextStyle _sheetHint(BuildContext context) => GoogleFonts.notoSerifKr(
      color: AppColors.mutedInk(context),
      fontSize: 13,
    );

class AddWordSheet extends ConsumerStatefulWidget {
  const AddWordSheet({super.key, this.existing});

  /// When non-null the sheet edits this word instead of adding a new one.
  final VocabWord? existing;

  @override
  ConsumerState<AddWordSheet> createState() => _AddWordSheetState();
}

class _AddWordSheetState extends ConsumerState<AddWordSheet> {
  final _hangul = TextEditingController();
  final _roman = TextEditingController();
  final _english = TextEditingController();
  final _polite = TextEditingController();
  String _pos = PartsOfSpeech.noun;

  /// Which list the word lands in. A new word follows the tab you added it
  /// from, so adding while reading 복습 files it as reinforced without a
  /// second tap. The picker below still overrides it.
  late WordStatus _status;

  final Set<String> _userSet = {};
  Timer? _debounce;
  int _fillRequestId = 0;
  String _lastFillSignature = '';
  bool _filling = false;
  String? _fillError;

  bool get _isEditing => widget.existing != null;

  /// The status implied by the list on screen behind the sheet.
  WordStatus _statusForCurrentTab() {
    if (ref.read(combinedViewProvider)) return WordStatus.learning;
    return ref.read(vocabSectionProvider) == VocabSection.reinforcement
        ? WordStatus.reinforcement
        : WordStatus.learning;
  }

  @override
  void initState() {
    super.initState();
    final w = widget.existing;
    // Editing keeps the word's current status; a new word takes the status of
    // the tab it was added from. 함께 implies neither type, so it falls back
    // to Learning — where a word you've only just met belongs.
    _status = w?.status ?? _statusForCurrentTab();
    if (w != null) {
      _hangul.text = w.hangul;
      _roman.text = w.romanization;
      _english.text = w.englishMeaning;
      _polite.text = w.politeForm;
      _pos = w.partOfSpeech;
      // Mark filled fields as user-owned so auto-fill never clobbers them.
      if (w.hangul.trim().isNotEmpty) _userSet.add('hangul');
      if (w.romanization.trim().isNotEmpty) _userSet.add('roman');
      if (w.englishMeaning.trim().isNotEmpty) _userSet.add('english');
      if (w.politeForm.trim().isNotEmpty) _userSet.add('polite');
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _hangul.dispose();
    _roman.dispose();
    _english.dispose();
    _polite.dispose();
    super.dispose();
  }

  void _onFieldChanged(String field, String value) {
    if (value.trim().isEmpty) {
      _userSet.remove(field);
    } else {
      _userSet.add(field);
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _runAutoFill);
    // No setState here. _userSet/_debounce aren't read by build, and
    // calling setState per-keystroke was rebuilding the GoldButton's
    // InkWell mid-tap — that was the "Save sometimes does nothing" bug.
    // Visual state (spinner, error) is updated by _runAutoFill, which
    // setStates on its own when needed.
  }

  Future<void> _runAutoFill() async {
    final h = _userSet.contains('hangul') ? _hangul.text.trim() : '';
    final r = _userSet.contains('roman') ? _roman.text.trim() : '';
    final e = _userSet.contains('english') ? _english.text.trim() : '';

    if (h.isEmpty && r.isEmpty && e.isEmpty) {
      if (mounted) setState(() => _filling = false);
      return;
    }

    final sig = '$h|$r|$e';
    if (sig == _lastFillSignature) return;
    _lastFillSignature = sig;

    final myId = ++_fillRequestId;
    if (mounted) setState(() {
      _filling = true;
      _fillError = null;
    });

    // Pre-flight: if the server isn't healthy, try waking it before we
    // make a call that would otherwise fail with SocketException.
    if (!await LlmLauncher.instance.isHealthy()) {
      final ok = await LlmLauncher.instance.ensureRunning();
      if (myId != _fillRequestId) return;
      if (!ok) {
        if (mounted) setState(() {
          _filling = false;
          _fillError = '로컬 모델이 꺼져 있어요. 설정에서 실행해 주세요.';
        });
        return;
      }
    }

    try {
      final result = await LlmService.instance.autoFillWord(
        hangul: h.isEmpty ? null : h,
        romanization: r.isEmpty ? null : r,
        english: e.isEmpty ? null : e,
      );
      if (myId != _fillRequestId) return; // stale
      if (!mounted) return;

      // Only overwrite fields the user hasn't claimed.
      if (!_userSet.contains('hangul') && (result['hangul'] ?? '').isNotEmpty) {
        _hangul.text = result['hangul']!;
      }
      if (!_userSet.contains('roman') && (result['romanization'] ?? '').isNotEmpty) {
        _roman.text = result['romanization']!;
      }
      if (!_userSet.contains('english') && (result['english'] ?? '').isNotEmpty) {
        _english.text = result['english']!;
      }
      // Polite form: only fill if the user left it blank, so a manual entry
      // is never clobbered.
      if (!_userSet.contains('polite') && (result['politeForm'] ?? '').isNotEmpty) {
        _polite.text = result['politeForm']!;
      }
      final modelPos = result['partOfSpeech'] ?? '';
      if (PartsOfSpeech.all.contains(modelPos)) {
        _pos = modelPos;
      }
      setState(() => _filling = false);
    } on LlmException catch (e) {
      if (myId != _fillRequestId) return;
      if (mounted) setState(() {
        _filling = false;
        _fillError = e.message;
      });
    } catch (err) {
      if (myId != _fillRequestId) return;
      // Surface the concrete error class for debuggability — "Connection
      // refused" reads very differently from a parser failure.
      final msg = err.toString();
      String friendly;
      if (msg.contains('SocketException') ||
          msg.contains('Connection refused') ||
          msg.contains('Failed host lookup')) {
        friendly = '모델 서버에 연결할 수 없어요. 설정 → LLM Server를 열어 주세요.';
      } else if (msg.contains('TimeoutException')) {
        friendly = '모델 응답이 너무 오래 걸려요 — 더 짧게 입력해 보세요.';
      } else {
        friendly = '자동 완성 실패: ${msg.replaceFirst('Exception: ', '')}';
      }
      if (mounted) setState(() {
        _filling = false;
        _fillError = friendly;
      });
    }
  }

  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return; // Guard against rapid double-taps.

    // Stop any pending autofill timer and invalidate any in-flight request
    // so its setState can't fire after we pop. This was the source of
    // intermittent "Save did nothing" — autofill races between the user's
    // last keystroke and the tap, leaving the sheet in a half-rebuilding
    // state when the click arrived.
    _debounce?.cancel();
    _fillRequestId++;

    final h = _hangul.text.trim();
    final r = _roman.text.trim();
    final e = _english.text.trim();
    if (h.isEmpty && r.isEmpty && e.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('한 가지 이상 입력해 주세요')),
      );
      return;
    }

    // Duplicate check — if a word with the same Hangul already exists, warn
    // and let the user decide whether to add it again. When editing, ignore
    // the word being edited itself.
    if (h.isNotEmpty) {
      final lower = h.toLowerCase();
      final existing = ref
          .read(vocabProvider)
          .where((w) =>
              w.hangul.trim().toLowerCase() == lower &&
              w.id != widget.existing?.id)
          .toList();
      if (existing.isNotEmpty) {
        final addAnyway = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('"$h" 은(는) 이미 목록에 있어요',
                style: GoogleFonts.notoSerifKr(
                    fontSize: 17, fontWeight: FontWeight.w600)),
            content: Text(
              existing.length == 1
                  ? '이미 저장된 단어예요. 그래도 추가할까요?'
                  : '이 단어가 이미 ${existing.length}개 있어요. 그래도 추가할까요?',
              style: GoogleFonts.notoSerifKr(fontSize: 13.5, height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('취소'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('그래도 추가'),
              ),
            ],
          ),
        );
        if (addAnyway != true) return;
        if (!mounted) return;
      }
    }

    setState(() => _saving = true);

    try {
      final existing = widget.existing;
      if (existing != null) {
        // Edit: keep id, status, dateAdded and stats; update the fields.
        await ref.read(vocabProvider.notifier).update(
              existing.copyWith(
                hangul: h,
                romanization: r,
                englishMeaning: e,
                partOfSpeech: _pos,
                politeForm: _polite.text.trim(),
                status: _status,
              ),
            );
      } else {
        // Add: drop the new word into whichever section the user is viewing.
        // (All / Learning both default to learning.)
        await ref.read(vocabProvider.notifier).add(
              VocabWord(
                id: 'w-${DateTime.now().millisecondsSinceEpoch}',
                hangul: h,
                romanization: r,
                englishMeaning: e,
                partOfSpeech: _pos,
                dateAdded: DateTime.now(),
                politeForm: _polite.text.trim(),
                status: _status,
              ),
            );
      }
      if (!mounted) return;
      Navigator.pop(context);
    } catch (err) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장하지 못했어요: $err')),
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
        child: SingleChildScrollView(
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
              Text(_isEditing ? '단어 수정' : '단어 추가',
                  style: GoogleFonts.notoSerifKr(
                    fontSize: 22,
                    color: AppColors.ink(context),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  )),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (_filling) ...[
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.6,
                        valueColor: AlwaysStoppedAnimation(AppColors.antiqueGold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('생각하는 중…',
                        style: GoogleFonts.notoSerifKr(
                          color: AppColors.antiqueGold,
                          fontSize: 12.5,
                        )),
                  ] else
                    Text(
                      _fillError ?? '모두 선택 사항이에요 — 나머지는 모델이 채워 줘요',
                      style: GoogleFonts.notoSerifKr(
                        color: _fillError != null
                            ? AppColors.softRed
                            : AppColors.mutedInk(context),
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _hangul,
                onChanged: (v) => _onFieldChanged('hangul', v),
                style: GoogleFonts.notoSerifKr(fontSize: 18),
                decoration: InputDecoration(
                  labelText: '한글',
                  labelStyle: _sheetLabel(context),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _roman,
                onChanged: (v) => _onFieldChanged('roman', v),
                style: GoogleFonts.inter(fontSize: 15),
                decoration: InputDecoration(
                  labelText: '로마자 표기',
                  labelStyle: _sheetLabel(context),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _polite,
                onChanged: (v) => _onFieldChanged('polite', v),
                style: GoogleFonts.notoSerifKr(fontSize: 18),
                decoration: InputDecoration(
                  labelText: '해요체 (현재 존댓말)',
                  labelStyle: _sheetLabel(context),
                  hintText: '예: 가요 — 비워 두면 자동으로 채워져요',
                  hintStyle: _sheetHint(context),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _english,
                onChanged: (v) => _onFieldChanged('english', v),
                style: GoogleFonts.inter(fontSize: 15),
                decoration: InputDecoration(
                  labelText: '영어 뜻',
                  labelStyle: _sheetLabel(context),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _pos,
                items: [
                  for (final p in PartsOfSpeech.all)
                    DropdownMenuItem(
                      value: p,
                      child: Text(
                        PartsOfSpeech.koreanLabel(p),
                        style: GoogleFonts.notoSerifKr(fontSize: 15),
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _pos = v ?? PartsOfSpeech.noun),
                decoration: InputDecoration(
                  labelText: '품사',
                  labelStyle: _sheetLabel(context),
                ),
              ),
              const SizedBox(height: 18),
              _StatusPicker(
                status: _status,
                onChanged: (v) => setState(() => _status = v),
              ),
              const SizedBox(height: 24),
              GoldButton(
                label: _saving
                    ? '저장 중…'
                    : (_isEditing ? '변경 사항 저장' : '저장'),
                onPressed: _saving ? null : _save,
                expanded: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
