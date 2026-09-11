import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/block_entry.dart';
import '../services/storage_service.dart';

class BlocksNotifier extends StateNotifier<List<BlockEntry>> {
  BlocksNotifier() : super([]) {
    _load();
  }

  void _load() {
    final box = StorageService.instance.blocksBox;
    state = box.values.toList()
      ..sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
  }

  Future<void> add(BlockEntry entry) async {
    await StorageService.instance.blocksBox.put(entry.id, entry);
    _load();
  }

  /// Replaces the block with the same id. Hive keys by id, so this is the
  /// same write as [add]; the separate name is for the reader.
  Future<void> update(BlockEntry entry) async {
    await StorageService.instance.blocksBox.put(entry.id, entry);
    _load();
  }

  Future<void> delete(String id) async {
    await StorageService.instance.blocksBox.delete(id);
    _load();
  }
}

final blocksProvider =
    StateNotifierProvider<BlocksNotifier, List<BlockEntry>>(
        (ref) => BlocksNotifier());
