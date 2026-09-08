import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/word_set_store.dart';

/// The finished review sets, newest first.
class WordSetNotifier extends StateNotifier<List<WordSet>> {
  WordSetNotifier() : super(WordSetStore.instance.all());

  void _reload() => state = WordSetStore.instance.all();

  Future<WordSet> create(String name, List<String> wordIds) async {
    final set = await WordSetStore.instance.create(name, wordIds);
    _reload();
    return set;
  }

  Future<void> setActive(String id, bool active) async {
    await WordSetStore.instance.setActive(id, active);
    _reload();
  }

  Future<void> rename(String id, String name) async {
    await WordSetStore.instance.rename(id, name);
    _reload();
  }

  /// Dissolves the set; its words return to the ordinary review pool.
  Future<void> release(String id) async {
    await WordSetStore.instance.release(id);
    _reload();
  }
}

final wordSetsProvider =
    StateNotifierProvider<WordSetNotifier, List<WordSet>>(
        (ref) => WordSetNotifier());

/// Words currently put aside — everything in a set that isn't switched back
/// on. Review skips these, which is the whole point of setting a batch aside.
final setAsideIdsProvider = Provider<Set<String>>((ref) {
  final sets = ref.watch(wordSetsProvider);
  return {
    for (final s in sets)
      if (!s.active) ...s.wordIds,
  };
});
