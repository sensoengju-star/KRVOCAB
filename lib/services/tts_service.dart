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

    // Every probe is guarded on its own. flutter_tts implements a DIFFERENT
    // SUBSET of methods per platform, and an unimplemented one throws
    // MissingPluginException rather than returning null — Windows, for
    // instance, has no `isLanguageAvailable`. A missing *query* says nothing
    // about whether the voice exists, so it must never disable the feature.
    await _quiet(() => _tts.awaitSpeakCompletion(true));

    if (await _hasKoreanVoice() == false) {
      isKoreanAvailable = false;
      unavailableReason = _missingVoiceMessage;
      return;
    }

    // Selecting the language is the operation that genuinely fails when no
    // Korean voice is installed, so its success is the real verdict.
    try {
      await _tts.setLanguage(koreanLocale);
      await _quiet(() => _tts.setPitch(1.0));
      await setRate(_rate);
      isKoreanAvailable = true;
    } catch (e) {
      isKoreanAvailable = false;
      unavailableReason = '$_missingVoiceMessage\n\n($e)';
      _log('setLanguage failed: $e');
    }
  }

  /// Whether a Korean voice exists: true / false / null when this platform
  /// can't be asked.
  Future<bool?> _hasKoreanVoice() async {
    // Android, iOS and macOS answer this directly.
    try {
      final direct = await _tts.isLanguageAvailable(koreanLocale);
      if (direct is bool) return direct;
    } catch (e) {
      _log('isLanguageAvailable unsupported here ($e) — falling back');
    }

    // Windows doesn't implement the check above, but does list its voices.
    try {
      final langs = await _tts.getLanguages;
      if (langs is List && langs.isNotEmpty) {
        return langs.any(
          (l) => '$l'.toLowerCase().replaceAll('_', '-').startsWith('ko'),
        );
      }
    } catch (e) {
      _log('getLanguages unsupported here ($e)');
    }

    return null; // Unknown — let setLanguage decide.
  }

  /// Runs a call whose failure shouldn't matter (an optional tuning knob the
  /// current platform may not implement).
  Future<void> _quiet(Future<dynamic> Function() call) async {
    try {
      await call();
    } catch (e) {
      _log('optional call failed: $e');
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
    if (!_initialized) return; // Restored from prefs before init ran.
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

  /// The form a learner actually SAYS: 해요체 when the word has one, since
  /// the -다 citation form is a dictionary convention nobody utters in a
  /// sentence.
  Future<void> speakWord(VocabWord word) {
    final polite = word.politeForm.trim();
    return speak(polite.isNotEmpty ? polite : word.hangul);
  }

  /// The form the word is FILED under: 가다, never 가요.
  ///
  /// This is what review speaks. A flashcard is testing recall of the entry
  /// as written on the card, so hearing a conjugation the card doesn't show
  /// makes the prompt and the audio disagree.
  Future<void> speakDictionaryForm(VocabWord word) => speak(word.hangul);

  Future<void> stop() async {
    // Skip the platform hop when nothing is playing — this is called on every
    // card change, and an idle round-trip still costs a beat on the UI thread.
    if (!_speaking) return;
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
