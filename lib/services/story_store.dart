import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../widgets/story_card.dart';
import 'storage_service.dart';

/// A generated story kept on disk, with when it was written.
@immutable
class SavedStory {
  const SavedStory({
    required this.id,
    required this.story,
    required this.createdAt,
    this.narrated = false,
    this.read = false,
  });

  final String id;
  final VocabStory story;
  final DateTime createdAt;

  /// Every sentence has been played at least once.
  final bool narrated;

  /// The learner ticked it off by hand.
  final bool read;

  /// A story is only removable once it has actually been used: heard in
  /// full, then deliberately marked read. Deleting is otherwise too easy a
  /// way to lose something the model spent a minute writing.
  bool get canDelete => narrated && read;

  SavedStory copyWith({bool? narrated, bool? read}) => SavedStory(
        id: id,
        story: story,
        createdAt: createdAt,
        narrated: narrated ?? this.narrated,
        read: read ?? this.read,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'narrated': narrated,
        'read': read,
        'story': story.toJson(),
      };

  static SavedStory? decode(String id, String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final storyJson = decoded['story'];
      if (storyJson is! Map) return null;
      final story = VocabStory.fromJson(Map<String, dynamic>.from(storyJson));
      if (!story.isRenderable) return null;
      return SavedStory(
        id: (decoded['id'] ?? id).toString(),
        story: story,
        createdAt:
            DateTime.tryParse((decoded['createdAt'] ?? '').toString()) ??
                DateTime.fromMillisecondsSinceEpoch(0),
        narrated: decoded['narrated'] == true,
        read: decoded['read'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Every story the model has ever written, kept across restarts.
///
/// Stories cost a slow local-model generation to produce and are worth
/// re-reading (and re-listening to), so they outlive the session that made
/// them rather than vanishing when the app closes.
class StoryStore {
  StoryStore._();
  static final StoryStore instance = StoryStore._();

  /// Newest first.
  List<SavedStory> all() {
    final box = StorageService.instance.storiesBox;
    final out = <SavedStory>[];
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw == null) continue;
      final saved = SavedStory.decode('$key', raw);
      if (saved != null) out.add(saved);
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  /// Persists a freshly generated batch. Stories identical to one already
  /// stored are skipped, so regenerating the same group doesn't pile up
  /// duplicates.
  Future<List<SavedStory>> addAll(List<VocabStory> stories) async {
    final box = StorageService.instance.storiesBox;
    final existing = {
      for (final s in all()) _fingerprint(s.story),
    };

    final now = DateTime.now();
    final added = <SavedStory>[];
    var i = 0;
    for (final story in stories) {
      if (!story.isRenderable) continue;
      if (!existing.add(_fingerprint(story))) continue;
      // Millisecond + index: a batch is written inside the same millisecond.
      final id = 's-${now.millisecondsSinceEpoch}-${i++}';
      final saved = SavedStory(
        id: id,
        story: story,
        // Nudge each one so the batch keeps its generated order when sorted.
        createdAt: now.add(Duration(milliseconds: i)),
      );
      await box.put(id, jsonEncode(saved.toJson()));
      added.add(saved);
    }
    return added;
  }

  /// Flags [id] as heard in full, or as read. Silently does nothing if the
  /// story is gone.
  Future<void> setFlags(String id, {bool? narrated, bool? read}) async {
    final box = StorageService.instance.storiesBox;
    final raw = box.get(id);
    if (raw == null) return;
    final saved = SavedStory.decode(id, raw);
    if (saved == null) return;
    final updated = saved.copyWith(narrated: narrated, read: read);
    // Nothing changed — skip the write so the flush timer stays quiet.
    if (updated.narrated == saved.narrated && updated.read == saved.read) {
      return;
    }
    await box.put(id, jsonEncode(updated.toJson()));
  }

  Future<void> delete(String id) =>
      StorageService.instance.storiesBox.delete(id);

  /// Deletes only the stories that have been heard in full AND marked read;
  /// returns how many were removed and how many were left behind.
  Future<({int deleted, int kept})> clearCompleted() async {
    final box = StorageService.instance.storiesBox;
    final removable = [for (final s in all()) if (s.canDelete) s.id];
    await box.deleteAll(removable);
    return (deleted: removable.length, kept: box.length);
  }

  int get count => StorageService.instance.storiesBox.length;

  String _fingerprint(VocabStory s) =>
      '${s.title.trim()}|${s.korean.trim()}';
}
