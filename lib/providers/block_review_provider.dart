import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/block_entry.dart';
import 'blocks_provider.dart';

class BlockReviewState {
  BlockReviewState({
    required this.deck,
    required this.index,
    required this.revealed,
  });

  final List<BlockEntry> deck;
  final int index;
  final bool revealed;

  BlockEntry? get current => deck.isEmpty ? null : deck[index % deck.length];

  int get position => deck.isEmpty ? 0 : (index % deck.length) + 1;
  int get total => deck.length;

  double get progress {
    if (deck.isEmpty) return 0;
    return (position / deck.length).clamp(0.0, 1.0);
  }

  BlockReviewState copyWith({
    List<BlockEntry>? deck,
    int? index,
    bool? revealed,
  }) {
    return BlockReviewState(
      deck: deck ?? this.deck,
      index: index ?? this.index,
      revealed: revealed ?? this.revealed,
    );
  }

  static final empty = BlockReviewState(deck: const [], index: 0, revealed: false);
}

/// Flip-only review over the user's manually-added block collection. No typing
/// and no grading — show the block, reveal the sound, move on.
class BlockReviewNotifier extends StateNotifier<BlockReviewState> {
  BlockReviewNotifier(this._ref) : super(BlockReviewState.empty) {
    _knownIds = _idsOf(_ref.read(blocksProvider));
    _rebuildDeck(_ref.read(blocksProvider));
    // Rebuild only when the SET of blocks changes (add / delete), not on
    // unrelated rebuilds.
    _ref.listen<List<BlockEntry>>(blocksProvider, (_, next) {
      final ids = _idsOf(next);
      if (ids.length != _knownIds.length || !ids.containsAll(_knownIds)) {
        _knownIds = ids;
        _rebuildDeck(next);
      }
    });
  }

  final Ref _ref;
  final Random _rng = Random();
  Set<String> _knownIds = const {};

  Set<String> _idsOf(List<BlockEntry> blocks) => {for (final b in blocks) b.id};

  void _rebuildDeck(List<BlockEntry> source) {
    if (source.isEmpty) {
      state = BlockReviewState.empty;
      return;
    }
    final pool = [...source]..shuffle(_rng);
    state = BlockReviewState(deck: pool, index: 0, revealed: false);
  }

  void reveal() {
    if (!state.revealed) state = state.copyWith(revealed: true);
  }

  void next() {
    if (state.deck.isEmpty) return;
    final nextIndex = state.index + 1;
    if (nextIndex >= state.deck.length) {
      // End of deck — reshuffle for a fresh pass.
      final reshuffled = [...state.deck]..shuffle(_rng);
      state = BlockReviewState(deck: reshuffled, index: 0, revealed: false);
    } else {
      state = state.copyWith(index: nextIndex, revealed: false);
    }
  }

  void previous() {
    if (state.deck.isEmpty) return;
    final len = state.deck.length;
    final prev = (state.index - 1 + len) % len;
    state = state.copyWith(index: prev, revealed: false);
  }

  /// Jump the review to a specific block by id (used by the search sheet).
  void jumpTo(String id) {
    final i = state.deck.indexWhere((b) => b.id == id);
    if (i >= 0) state = state.copyWith(index: i, revealed: false);
  }

  void restart() => _rebuildDeck(_ref.read(blocksProvider));
}

final blockReviewProvider =
    StateNotifierProvider<BlockReviewNotifier, BlockReviewState>(
        (ref) => BlockReviewNotifier(ref));
