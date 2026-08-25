import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/vocab_word.dart';

/// Korean text-to-speech through the operating system's own speech engine.
///
/// Deliberately NOT a cloud service: the app is offline-first (it runs its
/// own model server), so pronunciation shouldn't be the one feature that
/// needs a network and an API key.
///
/// Platform reality:
///   - Android / iOS / macOS ship Korean voices, so this just works.
///   - Windows only has ko-KR voices if the Korean language pack (with the
///     optional Speech feature) is installed. Without it the engine silently
///     substitutes an English voice, which mangles Hangul — hence
///     [isKoreanAvailable], which the UI uses to disable the feature and
///     explain how to fix it rather than appearing broken.
class TtsService {
  TtsService._();
  static final TtsService instance = TtsService._();

  static const String koreanLocale = 'ko-KR';

  final FlutterTts _tts = FlutterTts();

  bool _initialized = false;

  /// Whether a Korean voice actually exists on this machine.
  bool isKoreanAvailable = false;

  /// Why Korean is unavailable, when it is — shown in Settings.
  String? unavailableReason;

  /// Set while an utterance is in flight, so overlapping taps don't stack.
  bool _speaking = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      // Desktop engines report completion unreliably without this.
      await _tts.awaitSpeakCompletion(true);

      // A definite `false` means the engine looked and has no Korean voice.
      // `null` means it couldn't answer the question (not every platform
      // implementation supports the query) — that's not evidence of absence,
      // so we try to select the language and let THAT be the verdict.
      final available = await _tts.isLanguageAvailable(koreanLocale);
      if (available == false) {
        isKoreanAvailable = false;
        unavailableReason = _missingVoiceMessage;
        return;
      }

      await _tts.setLanguage(koreanLocale);
      await _tts.setPitch(1.0);
      await setRate(_rate);
      isKoreanAvailable = true;
    } catch (e) {
      isKoreanAvailable = false;
      // Selecting ko-KR is what usually throws when the voice isn't there,
      // so report the actionable message rather than the raw exception.
      unavailableReason = '$_missingVoiceMessage\n\n($e)';
      _log('init failed: $e');
    }
  }

  static String get _missingVoiceMessage => Platform.isWindows
      ? 'Windows has no Korean voice installed. Add it in Settings → Time & '
          'language → Language & region → add 한국어, and make sure the '
          'optional "Speech" feature is included. Then restart Maldari.'
      : 'This device has no Korean (ko-KR) voice installed. Add one in your '
          'system\'s speech settings, then restart Maldari.';

  double _rate = 0.45;

  /// 0.0–1.0. Learner-friendly default is slower than the platform's, which
  /// is tuned for reading sentences, not single words.
  double get rate => _rate;

  Future<void> setRate(double value) async {
    _rate = value.clamp(0.1, 1.0);
    try {
      // iOS/macOS interpret the same range differently — 1.0 there is
      // extremely fast, so the scale is compressed.
      final platformRate =
          (Platform.isIOS || Platform.isMacOS) ? _rate * 0.6 : _rate;
      await _tts.setSpeechRate(platformRate);
    } catch (e) {
      _log('setSpeechRate failed: $e');
    }
  }

  /// Speaks [text]. Any utterance already playing is cut off first, so
  /// tapping through cards quickly doesn't queue up a backlog.
  Future<void> speak(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    if (!_initialized) await init();
    if (!isKoreanAvailable) return;

    try {
      if (_speaking) await _tts.stop();
      _speaking = true;
      await _tts.speak(t);
    } catch (e) {
      _log('speak failed: $e');
    } finally {
      _speaking = false;
    }
  }

  /// What a vocabulary entry should sound like.
  ///
  /// Prefers the 해요체 form when the word has one: 가요 is what a learner
  /// actually says, while the -다 citation form is a dictionary convention
  /// nobody speaks in a sentence.
  Future<void> speakWord(VocabWord word) {
    final polite = word.politeForm.trim();
    return speak(polite.isNotEmpty ? polite : word.hangul);
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {
    } finally {
      _speaking = false;
    }
  }

  void _log(String msg) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[TtsService] $msg');
    }
  }
}
