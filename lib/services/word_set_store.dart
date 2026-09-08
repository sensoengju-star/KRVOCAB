import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'storage_service.dart';

/// A batch of words the learner has finished reviewing and set aside.
///
/// Setting a batch aside is not deleting it and not changing the words: the
/// words stay in the vocabulary list, keep their status and their counts. All
/// a set does is take them OUT of the review deck, so the deck empties out for
/// whatever is added next — and hand back a single switch to bring the whole
/// batch back later.
@immutable
class WordSet {
  const WordSet({
    required this.id,
    required this.name,
    required this.wordIds,
    required this.createdAt,
    this.active = false,
  });

  final String id;
  final String name;

  /// The words in the batch. Ids, not copies — a word edited later shows its
  /// new text here too, and a deleted word simply drops out.
  final List<String> wordIds;

  final DateTime createdAt;

  /// True while the batch is back in the review deck.
  final bool active;

  int get size => wordIds.length;

  WordSet copyWith({String? name, bool? active, List<String>? wordIds}) =>
      WordSet(
        id: id,
        name: name ?? this.name,
        wordIds: wordIds ?? this.wordIds,
        createdAt: createdAt,
        active: active ?? this.active,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'wordIds': wordIds,
        'createdAt': createdAt.toIso8601String(),
        'active': active,
      };

  static WordSet? decode(String id, String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final ids = (decoded['wordIds'] as List?) ?? const [];
      return WordSet(
        id: (decoded['id'] ?? id).toString(),
        name: (decoded['name'] ?? 'Set').toString(),
        wordIds: [for (final i in ids) i.toString()],
        createdAt:
            DateTime.tryParse((decoded['createdAt'] ?? '').toString()) ??
                DateTime.fromMillisecondsSinceEpoch(0),
        active: decoded['active'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Persistence for [WordSet]s. Newest first, like every other list in the app.
class WordSetStore {
  WordSetStore._();
  static final WordSetStore instance = WordSetStore._();

  List<WordSet> all() {
    final box = StorageService.instance.setsBox;
    final out = <WordSet>[];
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw == null) continue;
      final s = WordSet.decode(key.toString(), raw);
      if (s != null) out.add(s);
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  /// Ids belonging to a set that is currently put aside. These are the words
  /// review must skip.
  Set<String> setAsideIds() => {
        for (final s in all())
          if (!s.active) ...s.wordIds,
      };

  Future<WordSet> create(String name, List<String> wordIds) async {
    final now = DateTime.now();
    final set = WordSet(
      id: 'set-${now.microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? _defaultName(now) : name.trim(),
      wordIds: wordIds,
      createdAt: now,
    );
    await StorageService.instance.setsBox.put(set.id, jsonEncode(set.toJson()));
    return set;
  }

  static String _defaultName(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.'
      '${d.day.toString().padLeft(2, '0')} 세트';

  /// Name a new set after the ones already stored: 세트 1, 세트 2, …
  String suggestName() => '세트 ${all().length + 1}';

  Future<void> setActive(String id, bool active) async {
    final box = StorageService.instance.setsBox;
    final raw = box.get(id);
    if (raw == null) return;
    final set = WordSet.decode(id, raw);
    if (set == null || set.active == active) return;
    await box.put(id, jsonEncode(set.copyWith(active: active).toJson()));
  }

  Future<void> rename(String id, String name) async {
    final box = StorageService.instance.setsBox;
    final raw = box.get(id);
    if (raw == null) return;
    final set = WordSet.decode(id, raw);
    if (set == null || name.trim().isEmpty) return;
    await box.put(id, jsonEncode(set.copyWith(name: name.trim()).toJson()));
  }

  /// Dissolves the set. The WORDS are untouched — they simply return to the
  /// ordinary review pool, which is why this is worded as "release" rather
  /// than "delete" everywhere it's offered.
  Future<void> release(String id) =>
      StorageService.instance.setsBox.delete(id);
}
