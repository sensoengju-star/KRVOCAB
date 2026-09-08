import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/vocab_word.dart';
import '../services/daily_set_service.dart';
import '../services/hangul.dart';
import '../services/storage_service.dart';
import 'word_set_provider.dart';

class VocabNotifier extends StateNotifier<List<VocabWord>> {
  VocabNotifier() : super([]) {
    _load();
  }

  void _load() {
    final box = StorageService.instance.box;
    state = box.values.toList()
      ..sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
  }

  void refresh() => _load();

  Future<void> add(VocabWord word) async {
    await StorageService.instance.box.put(word.id, word);
    _load();
  }

  Future<void> update(VocabWord word) async {
    await StorageService.instance.box.put(word.id, word);
    _load();
  }

  Future<void> delete(String id) async {
    await StorageService.instance.box.delete(id);
    // Drop the word's cached study page too — otherwise a later word that
    // happened to reuse the id would inherit someone else's explanation.
    await StorageService.instance.deleteWordDetail(id);
    _load();
  }

  Future<void> recordResult(String id, {required bool correct}) async {
    final w = StorageService.instance.box.get(id);
    if (w == null) return;
    final updated = w.copyWith(
      correctCount: correct ? w.correctCount + 1 : w.correctCount,
      incorrectCount: correct ? w.incorrectCount : w.incorrectCount + 1,
    );
    await StorageService.instance.box.put(id, updated);
    _load();
  }

  /// Set an explicit status (learning / reinforcement).
  Future<void> setStatus(String id, WordStatus status) async {
    final w = StorageService.instance.box.get(id);
    if (w == null) return;
    await StorageService.instance.box.put(id, w.copyWith(status: status));
    _load();
  }

  /// Toggle: learning ⇄ reinforcement. The retired `learned` status (only
  /// reachable in data written by older builds) counts as learning, so a tap
  /// promotes it to reinforcement.
  Future<void> cycleStatus(String id) async {
    final w = StorageService.instance.box.get(id);
    if (w == null) return;
    final next = w.status == WordStatus.reinforcement
        ? WordStatus.learning
        : WordStatus.reinforcement;
    await StorageService.instance.box.put(id, w.copyWith(status: next));
    _load();
  }

  /// Merges every set of entries that share a (trimmed, lower-cased) hangul.
  /// Keeps the oldest entry's id, sums correct/incorrect counts, keeps any
  /// "learned" flag true, and deletes the rest. Returns the number of
  /// duplicate entries removed.
  Future<int> mergeDuplicates() async {
    final box = StorageService.instance.box;
    final groups = <String, List<VocabWord>>{};
    for (final w in box.values) {
      final key = w.hangul.trim().toLowerCase();
      if (key.isEmpty) continue;
      groups.putIfAbsent(key, () => []).add(w);
    }

    var removed = 0;
    // Merge priority: reinforcement > learned > learning. The strongest
    // intent across the duplicates wins.
    int rank(WordStatus s) => switch (s) {
          WordStatus.learning => 0,
          WordStatus.learned => 1,
          WordStatus.reinforcement => 2,
        };
    for (final list in groups.values) {
      if (list.length < 2) continue;
      list.sort((a, b) => a.dateAdded.compareTo(b.dateAdded));
      final keeper = list.first;
      var correctSum = keeper.correctCount;
      var incorrectSum = keeper.incorrectCount;
      var status = keeper.status;
      final toDelete = <String>[];
      for (final dup in list.skip(1)) {
        correctSum += dup.correctCount;
        incorrectSum += dup.incorrectCount;
        if (rank(dup.status) > rank(status)) status = dup.status;
        toDelete.add(dup.id);
      }
      await box.put(
        keeper.id,
        keeper.copyWith(
          correctCount: correctSum,
          incorrectCount: incorrectSum,
          status: status,
        ),
      );
      await box.deleteAll(toDelete);
      await StorageService.instance.detailsBox.deleteAll(toDelete);
      removed += toDelete.length;
    }

    if (removed > 0) _load();
    return removed;
  }

  /// Bulk-delete every word that isn't reinforced (i.e. everything the
  /// Learning tab shows). Returns the count.
  Future<int> deleteAllLearning() async {
    final box = StorageService.instance.box;
    final ids = [
      for (final w in box.values)
        if (w.status != WordStatus.reinforcement) w.id,
    ];
    if (ids.isEmpty) return 0;
    await box.deleteAll(ids);
    await StorageService.instance.detailsBox.deleteAll(ids);
    _load();
    return ids.length;
  }

  /// Bulk-delete every word with status == reinforcement. Returns the count.
  Future<int> deleteAllReinforced() async {
    final box = StorageService.instance.box;
    final ids = [
      for (final w in box.values)
        if (w.status == WordStatus.reinforcement) w.id,
    ];
    if (ids.isEmpty) return 0;
    await box.deleteAll(ids);
    await StorageService.instance.detailsBox.deleteAll(ids);
    _load();
    return ids.length;
  }
}

final vocabProvider =
    StateNotifierProvider<VocabNotifier, List<VocabWord>>((ref) => VocabNotifier());

final selectedWordProvider = StateProvider<VocabWord?>((ref) => null);
final activeTabProvider = StateProvider<int>((ref) => 0);

/// When non-null, the Examples tab should auto-generate sentences for this
/// word on next build/listen. The screen clears it after consuming.
final pendingExampleWordProvider = StateProvider<VocabWord?>((ref) => null);

final searchQueryProvider = StateProvider<String>((ref) => '');
final posFilterProvider = StateProvider<String?>((ref) => null);

/// When set, the list shows only words that use this Hangul syllable block
/// anywhere in them — 학 finds 학교, 대학, 학생.
final blockFilterProvider = StateProvider<String?>((ref) => null);

/// When on, the visible list is grouped under each word's FIRST block.
final groupByBlockProvider = StateProvider<bool>((ref) => false);

/// Every syllable block used across the collection, with how many words use
/// it. A word counts once per distinct block, so 가가운 doesn't count 가 twice.
/// Sorted by frequency, then by the block itself.
final blockUsageProvider = Provider<List<({String block, int count})>>((ref) {
  final words = ref.watch(vocabProvider);
  final counts = <String, int>{};
  for (final w in words) {
    final seen = <String>{};
    for (final c in w.hangul.trim().split('')) {
      if (!Hangul.isSyllable(c) || !seen.add(c)) continue;
      counts[c] = (counts[c] ?? 0) + 1;
    }
  }
  final out = [
    for (final e in counts.entries) (block: e.key, count: e.value),
  ];
  out.sort((a, b) {
    final byCount = b.count.compareTo(a.count);
    return byCount != 0 ? byCount : a.block.compareTo(b.block);
  });
  return out;
});

/// The first syllable block of [hangul], or '' when it doesn't start with one
/// (an empty entry, or a romanization-only word).
String firstBlockOf(String hangul) {
  final h = hangul.trim();
  if (h.isEmpty) return '';
  final first = h.substring(0, 1);
  return Hangul.isSyllable(first) ? first : '';
}

/// Which section of the vocab list to show. A word is either being learned
/// or being reinforced — there is no third "learned" resting state.
enum VocabSection { learning, reinforcement }

/// The app opens on Reinforced — the words actually in rotation are what you
/// come back to day to day.
final vocabSectionProvider =
    StateProvider<VocabSection>((ref) => VocabSection.reinforcement);

/// When on, words put aside in a review set stay visible in the vocabulary
/// list, dimmed and badged. Off by default: setting a batch aside is meant to
/// clear it out of the way, and a list that still shows every archived word
/// has not actually made room for anything.
final showSetAsideProvider = StateProvider<bool>((ref) => false);

/// When on, Learning and Reinforced words share one list instead of living
/// behind separate tabs. Each type keeps its own colour so they stay tellable
/// apart at a glance. Off at launch, so the app starts on Reinforced alone.
final combinedViewProvider = StateProvider<bool>((ref) => false);

/// 0-based group index used by the Learning tab to paginate by 25s. The
/// selected group is also what the Stories tab draws its learning words from.
final learningGroupProvider = StateProvider<int>((ref) => 0);
const learningGroupSize = 25;

/// 0-based group index used by the Reinforcement tab to paginate by 25s.
/// This same selection also drives which reinforcement words appear in the
/// review deck (when "Include reinforced words" is on) and which words the
/// Stories tab weaves into its stories.
final reinforcementGroupProvider = StateProvider<int>((ref) => 0);
const reinforcementGroupSize = 25;

/// The reinforcement words (up to [reinforcementGroupSize]) in the currently
/// selected group. Ordering follows [vocabProvider] (newest first), matching
/// the Reinforcement tab's display order. Empty when there are no reinforced
/// words.
final reinforcementGroupWordsProvider = Provider<List<VocabWord>>((ref) {
  final words = ref.watch(vocabProvider);
  final reinforced = [
    for (final w in words)
      if (w.status == WordStatus.reinforcement) w,
  ];
  if (reinforced.isEmpty) return const [];
  final groupCount = (reinforced.length / reinforcementGroupSize).ceil();
  var group = ref.watch(reinforcementGroupProvider);
  if (group < 0 || group >= groupCount) group = 0;
  final start = group * reinforcementGroupSize;
  final end = (start + reinforcementGroupSize).clamp(0, reinforced.length);
  return reinforced.sublist(start, end);
});

/// The learning words in the currently selected Learning group — the same
/// idea as [reinforcementGroupWordsProvider], so the Stories tab can weave
/// learning words too without being handed a thousand of them.
final learningGroupWordsProvider = Provider<List<VocabWord>>((ref) {
  final words = ref.watch(vocabProvider);
  final learning = [
    for (final w in words)
      if (w.status != WordStatus.reinforcement) w,
  ];
  if (learning.isEmpty) return const [];
  final groupCount = (learning.length / learningGroupSize).ceil();
  var group = ref.watch(learningGroupProvider);
  if (group < 0 || group >= groupCount) group = 0;
  final start = group * learningGroupSize;
  final end = (start + learningGroupSize).clamp(0, learning.length);
  return learning.sublist(start, end);
});

/// Which pool the Stories tab weaves its stories from.
enum StorySource { both, learning, reinforcement }

final storySourceProvider =
    StateProvider<StorySource>((ref) => StorySource.both);

/// The words the Stories tab will use, per [storySourceProvider]. Duplicate
/// hangul are dropped so a word can't be assigned to two stories at once.
final storyWordsProvider = Provider<List<VocabWord>>((ref) {
  final source = ref.watch(storySourceProvider);
  final learning = ref.watch(learningGroupWordsProvider);
  final reinforced = ref.watch(reinforcementGroupWordsProvider);

  final pool = switch (source) {
    StorySource.learning => learning,
    StorySource.reinforcement => reinforced,
    StorySource.both => [...reinforced, ...learning],
  };

  final seen = <String>{};
  return [
    for (final w in pool)
      if (w.hangul.trim().isNotEmpty && seen.add(w.hangul.trim())) w,
  ];
});

/// Today's draw for the combined list, and how far the current cycle has come.
@immutable
class DailyPick {
  const DailyPick({
    this.ids = const {},
    this.cycleShown = 0,
    this.ready = false,
  });

  /// The ids of the words shown today.
  final Set<String> ids;

  /// How many words the current cycle has already spent.
  final int cycleShown;

  /// False until the stored set has been read off disk. The list shows
  /// everything until then rather than flashing empty for a frame.
  final bool ready;
}

/// Keeps [DailySetService] in step with the collection, and re-draws when the
/// day rolls over while the app is left open.
class DailyWordsNotifier extends StateNotifier<DailyPick> {
  DailyWordsNotifier(this._ref) : super(const DailyPick()) {
    _sync(_ref.read(vocabProvider));
    // Adding or deleting words can invalidate the stored set, so follow it.
    _ref.listen<List<VocabWord>>(vocabProvider, (_, next) => _sync(next));
    // Archiving a batch shrinks the pool the same way a delete would.
    _ref.listen<Set<String>>(
        setAsideIdsProvider, (_, __) => _sync(_ref.read(vocabProvider)));
    _armMidnight();
  }

  final Ref _ref;
  Timer? _midnight;

  /// Draws are serialized: two overlapping picks would each mark words as
  /// shown and burn through the cycle twice as fast.
  Future<void> _queue = Future<void>.value();

  void _sync(List<VocabWord> words) {
    _queue = _queue.then((_) async {
      final ids = await DailySetService.instance.ensureToday(_pool(words));
      _publish(ids);
    }).catchError((_) {});
  }

  /// Words a draw may pick from. Set-aside words are excluded: they don't
  /// appear in the list, so spending a day's slot on one would silently show
  /// fewer than ten.
  List<VocabWord> _pool(List<VocabWord> words) {
    final aside = _ref.read(setAsideIdsProvider);
    if (aside.isEmpty) return words;
    return [
      for (final w in words)
        if (!aside.contains(w.id)) w,
    ];
  }

  /// Draws a new set for today by hand.
  Future<void> reshuffle() {
    _queue = _queue.then((_) async {
      final ids = await DailySetService.instance
          .reshuffle(_pool(_ref.read(vocabProvider)));
      _publish(ids);
    }).catchError((_) {});
    return _queue;
  }

  void _publish(List<String> ids) {
    if (!mounted) return;
    state = DailyPick(
      ids: ids.toSet(),
      cycleShown: DailySetService.instance.cycleShownCount,
      ready: true,
    );
  }

  /// Re-draws just after midnight, so an app left running overnight shows the
  /// new day's words without needing a restart.
  void _armMidnight() {
    _midnight?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1);
    _midnight = Timer(
      next.difference(now) + const Duration(seconds: 5),
      () {
        _sync(_ref.read(vocabProvider));
        _armMidnight();
      },
    );
  }

  @override
  void dispose() {
    _midnight?.cancel();
    super.dispose();
  }
}

final dailyWordsProvider =
    StateNotifierProvider<DailyWordsNotifier, DailyPick>(
        (ref) => DailyWordsNotifier(ref));

final filteredVocabProvider = Provider<List<VocabWord>>((ref) {
  final words = ref.watch(vocabProvider);
  final q = ref.watch(searchQueryProvider).toLowerCase().trim();
  final pos = ref.watch(posFilterProvider);
  final section = ref.watch(vocabSectionProvider);
  final combined = ref.watch(combinedViewProvider);
  final block = ref.watch(blockFilterProvider);
  final daily = ref.watch(dailyWordsProvider);
  final setAside = ref.watch(setAsideIdsProvider);
  final showSetAside = ref.watch(showSetAsideProvider);

  // The combined view is a DAILY SET, not the whole collection: ten words,
  // redrawn each morning. Searching or filtering suspends it — looking for a
  // word and being told it doesn't exist because it isn't in today's ten
  // would be a lie about your own vocabulary.
  final dailyOnly = combined &&
      daily.ready &&
      daily.ids.isNotEmpty &&
      q.isEmpty &&
      pos == null &&
      block == null;

  return words.where((w) {
    // Put aside means out of sight as well as out of the review deck — the
    // whole point is to clear room for new words. The 보관 중 strip above the
    // list brings them back temporarily.
    if (!showSetAside && setAside.contains(w.id)) return false;
    if (dailyOnly && !daily.ids.contains(w.id)) return false;
    // Combined view shows both types together; otherwise honour the tab.
    if (!combined) {
      switch (section) {
        case VocabSection.learning:
          // Anything not reinforced is "learning" — including words left with
          // the retired `learned` status by an older build.
          if (w.status == WordStatus.reinforcement) return false;
          break;
        case VocabSection.reinforcement:
          if (w.status != WordStatus.reinforcement) return false;
          break;
      }
    }
    if (pos != null && w.partOfSpeech != pos) return false;
    if (block != null && !w.hangul.contains(block)) return false;
    if (q.isEmpty) return true;
    return w.hangul.toLowerCase().contains(q) ||
        w.romanization.toLowerCase().contains(q) ||
        w.englishMeaning.toLowerCase().contains(q);
  }).toList();
});

/// Counts for the section pills (cheap O(n) walk). Hidden set-aside words are
/// not counted — a tab reading 40 while showing 6 is just wrong.
final vocabCountsProvider =
    Provider<({int learning, int reinforcement, int total})>((ref) {
  final words = ref.watch(vocabProvider);
  final setAside = ref.watch(setAsideIdsProvider);
  final showSetAside = ref.watch(showSetAsideProvider);
  var learning = 0, reinforcement = 0;
  for (final w in words) {
    if (!showSetAside && setAside.contains(w.id)) continue;
    if (w.status == WordStatus.reinforcement) {
      reinforcement++;
    } else {
      learning++;
    }
  }
  return (
    learning: learning,
    reinforcement: reinforcement,
    total: learning + reinforcement,
  );
});
