import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/grammar_topic.dart';
import '../services/storage_service.dart';

class GrammarNotifier extends StateNotifier<List<GrammarTopic>> {
  GrammarNotifier() : super([]) {
    _load();
  }

  void _load() {
    final box = StorageService.instance.grammarBox;
    state = box.values.toList()
      ..sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
  }

  Future<void> add(GrammarTopic topic) async {
    await StorageService.instance.grammarBox.put(topic.id, topic);
    _load();
  }

  Future<void> update(GrammarTopic topic) async {
    await StorageService.instance.grammarBox.put(topic.id, topic);
    _load();
  }

  Future<void> delete(String id) async {
    await StorageService.instance.grammarBox.delete(id);
    _load();
  }
}

final grammarProvider =
    StateNotifierProvider<GrammarNotifier, List<GrammarTopic>>(
        (ref) => GrammarNotifier());
