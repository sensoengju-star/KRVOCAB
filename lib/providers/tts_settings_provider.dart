import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/narration_service.dart';
import '../services/tts_service.dart';

/// Whether a card speaks itself when it turns to the answer side.
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

/// Speaking speed for the LOCAL voice (words), 0.1–1.0. Slower than the
/// platform default by design: these are single vocabulary words, not prose.
/// Story narration has its own speed, set with the ElevenLabs voice.
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

/// How much of a story each press narrates. Persisted, because it's a
/// working style rather than a per-story choice.
class NarrationModeNotifier extends StateNotifier<NarrationMode> {
  NarrationModeNotifier() : super(NarrationMode.whole) {
    _load();
  }

  static const _key = 'narration_mode';

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    state = p.getString(_key) == NarrationMode.sentence.name
        ? NarrationMode.sentence
        : NarrationMode.whole;
  }

  Future<void> set(NarrationMode value) async {
    state = value;
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, value.name);
  }

  Future<void> toggle() => set(state == NarrationMode.whole
      ? NarrationMode.sentence
      : NarrationMode.whole);
}

final narrationModeProvider =
    StateNotifierProvider<NarrationModeNotifier, NarrationMode>(
        (ref) => NarrationModeNotifier());

/// The single story-narration player. Kept app-wide so starting one story
/// stops whatever else was speaking.
final narrationProvider = Provider<NarrationController>((ref) {
  final controller = NarrationController();
  ref.onDispose(controller.dispose);
  return controller;
});
