import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/vocab_word.dart';
import 'review_settings_provider.dart';
import 'vocab_provider.dart';

class ReviewState {
  ReviewState({
    required this.deck,
    required this.index,
    required this.streak,
    required this.correctThisSession,
    required this.totalThisSession,
    required this.revealed,
  });

  final List<VocabWord> deck;
  final int index;
  final int streak;
  final int correctThisSession;
  final int totalThisSession;
  final bool revealed;

  VocabWord? get current => deck.isEmpty ? null : deck[index % deck.length];

  double get progress {
    if (totalThisSession == 0) return 0;
    return (correctThisSession / totalThisSession).clamp(0.0, 1.0);
  }

  ReviewState copyWith({
    List<VocabWord>? deck,
    int? index,
    int? streak,
    int? correctThisSession,
    int? totalThisSession,
    bool? revealed,
  }) {
    return ReviewState(
      deck: deck ?? this.deck,
      index: index ?? this.index,
      streak: streak ?? this.streak,
      correctThisSession: correctThisSession ?? this.correctThisSession,
      totalThisSession: totalThisSession ?? this.totalThisSession,
      revealed: revealed ?? this.revealed,
    );
  }

  static final empty = ReviewState(
    deck: const [],
    index: 0,
    streak: 0,
    correctThisSession: 0,
    totalThisSession: 0,
    revealed: false,
  );
}

class ReviewNotifier extends StateNotifier<ReviewState> {
  ReviewNotifier(this._ref) : super(ReviewState.empty) {
    final initial = _ref.read(vocabProvider);
    _knownIds = _eligibleIds(initial);
    _rebuildDeck(initial);
    // Only rebuild the deck when the SET of eligible word IDs changes — i.e.
    // an add, a delete, or a learned-flag toggle that changes membership.
    // Per-card stats updates (correctCount/incorrectCount) flow through the
    // same provider but must NOT reshuffle the deck mid-session, otherwise
    // every answer resets the order and the user sees duplicates.
    _ref.listen<List<VocabWord>>(vocabProvider, (_, next) {
      final nextIds = _eligibleIds(next);
      if (nextIds.length != _knownIds.length ||
          !nextIds.containsAll(_knownIds)) {
        _knownIds = nextIds;
        _rebuildDeck(next);
      } else {
        _knownIds = nextIds;
        _refreshDeckReferences(next);
      }
    });
  }

  /// Recompute the eligible set and rebuild the deck from scratch. Called when
  /// either Review preference (Include learned / Learning only) changes. The
  /// Review screen drives this through a widget-level `ref.listen`, which
  /// fires reliably even while the Settings route sits on top of the
  /// navigator — unlike a constructor-time `ref.listen`, which in practice
  /// could be missed.
  void recomputeEligibility() {
    final words = _ref.read(vocabProvider);
    _knownIds = _eligibleIds(words);
    _rebuildDeck(words);
  }

  Set<String> _eligibleIds(List<VocabWord> words) {
    final includeReinforcement = _ref.read(includeReinforcementProvider);
    final learningOnly = _ref.read(learningOnlyProvider);
    final reinforcementIds = (includeReinforcement && !learningOnly)
        ? _reinforcementGroupIds(words)
        : const <String>{};
    return {
      for (final w in words)
        if (_isEligible(w, includeReinforcement, learningOnly, reinforcementIds))
          w.id,
    };
  }

  /// The IDs of the reinforcement words in the currently-selected group (of
  /// [reinforcementGroupSize]). Ordering matches the vocab list — `words` is
  /// already sorted newest-first by [vocabProvider].
  Set<String> _reinforcementGroupIds(List<VocabWord> words) {
    final reinforced = [
      for (final w in words)
        if (w.status == WordStatus.reinforcement) w,
    ];
    if (reinforced.isEmpty) return const {};
    final groupCount = (reinforced.length / reinforcementGroupSize).ceil();
    var group = _ref.read(reinforcementGroupProvider);
    if (group < 0 || group >= groupCount) group = 0;
    final start = group * reinforcementGroupSize;
    final end = (start + reinforcementGroupSize).clamp(0, reinforced.length);
    return {for (final w in reinforced.sublist(start, end)) w.id};
  }

  /// Eligibility rules:
  ///   - `learningOnly` wins: when on, ONLY learning words pass.
  ///   - reinforcement passes only when "Include reinforced words" is on AND
  ///     the word is in the currently-selected reinforcement group.
  ///
  /// The retired `learned` status counts as learning everywhere.
  bool _isEligible(
    VocabWord w,
    bool includeReinforcement,
    bool learningOnly,
    Set<String> reinforcementIds,
  ) {
    final reinforced = w.status == WordStatus.reinforcement;
    if (learningOnly) return !reinforced;
    if (!reinforced) return true;
    return includeReinforcement && reinforcementIds.contains(w.id);
  }

  final Ref _ref;
  final Random _rng = Random();
  Set<String> _knownIds = const {};

  /// Sliding window of the most recently shown card ids. Used to push
  /// recently-seen cards toward the back when reshuffling, so the user
  /// doesn't see the same word two or three cards apart across a lap
  /// boundary. Most-recent first.
  final List<String> _recentlySeen = <String>[];
  static const _maxRecent = 5;

  void _markSeen(String? id) {
    if (id == null) return;
    _recentlySeen.remove(id); // dedupe
    _recentlySeen.insert(0, id);
    if (_recentlySeen.length > _maxRecent) {
      _recentlySeen.removeRange(_maxRecent, _recentlySeen.length);
    }
  }

  /// Replace each deck entry with the latest object from [latest] (same id,
  /// updated counts). Preserves order and index.
  void _refreshDeckReferences(List<VocabWord> latest) {
    if (state.deck.isEmpty) return;
    final byId = {for (final w in latest) w.id: w};
    final updated = [
      for (final w in state.deck) byId[w.id] ?? w,
    ];
    state = state.copyWith(deck: updated);
  }

  void _rebuildDeck(List<VocabWord> source) {
    final includeReinforcement = _ref.read(includeReinforcementProvider);
    // Dedupe by trimmed hangul (case-insensitive). If the store contains
    // accidental duplicates from past races, the user still sees only one
    // card per word in review. Keep the entry with the most attempts so
    // stats aren't reset.
    final learningOnly = _ref.read(learningOnlyProvider);
    final reinforcementIds = (includeReinforcement && !learningOnly)
        ? _reinforcementGroupIds(source)
        : const <String>{};
    final seen = <String, VocabWord>{};
    for (final w in source) {
      if (!_isEligible(w, includeReinforcement, learningOnly, reinforcementIds)) {
        continue;
      }
      final key = w.hangul.trim().toLowerCase();
      if (key.isEmpty) continue;
      final existing = seen[key];
      if (existing == null) {
        seen[key] = w;
      } else {
        final aAttempts = existing.correctCount + existing.incorrectCount;
        final bAttempts = w.correctCount + w.incorrectCount;
        if (bAttempts > aAttempts) seen[key] = w;
      }
    }
    final pool = seen.values.toList();
    if (pool.isEmpty) {
      state = ReviewState.empty;
      return;
    }
    final shuffled = _shuffleAvoiding(pool, state.current);
    state = ReviewState(
      deck: shuffled,
      index: 0,
      streak: 0,
      correctThisSession: 0,
      totalThisSession: pool.length,
      revealed: false,
    );
  }

  /// Fisher-Yates shuffle that then pushes any recently-seen card out of
  /// the first `avoidWindow` slots, so right after a lap boundary the user
  /// doesn't immediately see the last few cards from the previous lap.
  ///
  /// `avoid` (the current card) is treated as the most-recent for this
  /// call even if it's not yet in [_recentlySeen].
  List<VocabWord> _shuffleAvoiding(List<VocabWord> source, VocabWord? avoid) {
    final list = [...source];
    for (var i = list.length - 1; i > 0; i--) {
      final j = _rng.nextInt(i + 1);
      final tmp = list[i];
      list[i] = list[j];
      list[j] = tmp;
    }

    if (list.length < 3) return list;

    // Window scales with deck size — for a 5-card deck we avoid 2; for 10+
    // we avoid up to 4. Never block more than half the deck or the swap
    // becomes impossible.
    final avoidWindow = (list.length ~/ 2).clamp(1, 4);
    final avoidIds = <String>{
      if (avoid != null) avoid.id,
      ..._recentlySeen.take(avoidWindow),
    };
    if (avoidIds.isEmpty) return list;

    // For each "bad" position in the front window, swap with a random
    // card from the back half that's NOT in the avoid set.
    for (var pos = 0; pos < avoidWindow && pos < list.length; pos++) {
      if (!avoidIds.contains(list[pos].id)) continue;
      // Find candidate swap targets in [avoidWindow, list.length).
      final candidates = <int>[];
      for (var k = avoidWindow; k < list.length; k++) {
        if (!avoidIds.contains(list[k].id)) candidates.add(k);
      }
      if (candidates.isEmpty) break; // nothing safe to swap with
      final swapWith = candidates[_rng.nextInt(candidates.length)];
      final tmp = list[pos];
      list[pos] = list[swapWith];
      list[swapWith] = tmp;
    }
    return list;
  }

  void reveal() {
    if (!state.revealed) state = state.copyWith(revealed: true);
  }

  /// Record a correct answer. Does NOT advance — the screen schedules the
  /// advance after the 850 ms confirmation window so the user actually sees
  /// the revealed back face before the next card loads.
  void markCorrect() {
    final cur = state.current;
    if (cur == null) return;
    _markSeen(cur.id);
    _ref.read(vocabProvider.notifier).recordResult(cur.id, correct: true);
    state = state.copyWith(
      streak: state.streak + 1,
      correctThisSession: state.correctThisSession + 1,
    );
  }

  void markIncorrect() {
    final cur = state.current;
    if (cur == null) return;
    _ref.read(vocabProvider.notifier).recordResult(cur.id, correct: false);
    state = state.copyWith(streak: 0);
    // No advance — caller (next button) decides whether to move on.
  }

  void _advance() {
    // Record the card the user just left as "seen" so the next reshuffle
    // pushes it (and the few before it) toward the back.
    _markSeen(state.current?.id);
    final next = state.index + 1;
    if (next >= state.deck.length) {
      // Auto-reshuffle at end of deck; reset session counters.
      final reshuffled = _shuffleAvoiding(state.deck, state.current);
      state = state.copyWith(
        deck: reshuffled,
        index: 0,
        correctThisSession: 0,
        totalThisSession: reshuffled.length,
        revealed: false,
      );
    } else {
      state = state.copyWith(index: next, revealed: false);
    }
  }

  void next() {
    // Move to the next card unconditionally (used by the Next button).
    _advance();
  }

  void previous() {
    if (state.deck.isEmpty) return;
    final len = state.deck.length;
    final prev = (state.index - 1 + len) % len;
    state = state.copyWith(index: prev, revealed: false);
  }

  void restart() {
    _recentlySeen.clear();
    _rebuildDeck(_ref.read(vocabProvider));
  }
}

final reviewProvider =
    StateNotifierProvider<ReviewNotifier, ReviewState>((ref) => ReviewNotifier(ref));
