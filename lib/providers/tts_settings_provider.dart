import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/narration_service.dart';
import '../services/tts_service.dart';

/// Whether a card speaks itself when it flips to the answer side.
/// Persisted in SharedPreferences. Default: on — hearing the word is the
/// point of the feature; tap-to-hear stays available either way.
class AutoSpeakNotifier extends StateNotifier<bool> {
  AutoSpeakNotifier() : super(true) {
    _load();
  }

  static const _key = 'tts_auto_speak';

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    state = p.getBool(_key) ?? true;
  }

  Future<void> set(bool value) async {
    state = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, value);
  }

  Future<void> toggle() => set(!state);
}

final autoSpeakProvider =
    StateNotifierProvider<AutoSpeakNotifier, bool>((ref) => AutoSpeakNotifier());

/// Speaking speed, 0.1–1.0. Slower than the platform default by design:
/// these are single vocabulary words, not prose.
class SpeechRateNotifier extends StateNotifier<double> {
  SpeechRateNotifier() : super(0.45) {
    _load();
  }

  static const _key = 'tts_rate';

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getDouble(_key) ?? 0.45;
    state = v;
    await TtsService.instance.setRate(v);
  }

  Future<void> set(double value) async {
    state = value;
    await TtsService.instance.setRate(value);
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_key, value);
  }
}

final speechRateProvider =
    StateNotifierProvider<SpeechRateNotifier, double>(
        (ref) => SpeechRateNotifier());

/// Which engine narrates STORIES. Everything else — word taps, the flashcard
/// answer, the word page — always uses the free local engine, so a paid API
/// can only ever be spent on story narration.
class NarrationSourceNotifier extends StateNotifier<NarrationSource> {
  NarrationSourceNotifier() : super(NarrationSource.local) {
    _load();
  }

  static const _key = 'narration_source';

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getString(_key);
    state = saved == NarrationSource.elevenLabs.name
        ? NarrationSource.elevenLabs
        : NarrationSource.local;
  }

  Future<void> set(NarrationSource value) async {
    state = value;
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, value.name);
  }
}

final narrationSourceProvider =
    StateNotifierProvider<NarrationSourceNotifier, NarrationSource>(
        (ref) => NarrationSourceNotifier());

/// The single story-narration player. Kept app-wide so starting one story
/// stops whatever else was speaking.
final narrationProvider = Provider<NarrationController>((ref) {
  final controller = NarrationController();
  ref.onDispose(controller.dispose);
  return controller;
});
