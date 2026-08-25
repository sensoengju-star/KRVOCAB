import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether words flagged `reinforcement` should appear in the review deck.
/// Persisted in SharedPreferences. Default: false (reinforced words hidden).
class IncludeReinforcementNotifier extends StateNotifier<bool> {
  IncludeReinforcementNotifier() : super(false) {
    _load();
  }

  static const _key = 'review_include_reinforcement';

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    state = p.getBool(_key) ?? false;
  }

  Future<void> set(bool value) async {
    state = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, value);
  }

  Future<void> toggle() => set(!state);
}

final includeReinforcementProvider =
    StateNotifierProvider<IncludeReinforcementNotifier, bool>(
        (ref) => IncludeReinforcementNotifier());

/// When true, the review deck is restricted to learning words ONLY (excludes
/// reinforcement). Useful when the user wants to drill brand-new words
/// without reinforcement interruptions.
class LearningOnlyNotifier extends StateNotifier<bool> {
  LearningOnlyNotifier() : super(false) {
    _load();
  }

  static const _key = 'review_learning_only';

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    state = p.getBool(_key) ?? false;
  }

  Future<void> set(bool value) async {
    state = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, value);
  }

  Future<void> toggle() => set(!state);
}

final learningOnlyProvider =
    StateNotifierProvider<LearningOnlyNotifier, bool>(
        (ref) => LearningOnlyNotifier());
