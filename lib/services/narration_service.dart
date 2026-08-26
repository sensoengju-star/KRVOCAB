import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'elevenlabs_service.dart';
import 'tts_service.dart';

/// Where story narration gets its audio.
///
/// ONLY story narration ever consults this. Tapping a word, the flashcard's
/// auto-pronunciation and the word page all go straight to [TtsService] and
/// stay free — a paid API must never be spent on single words.
enum NarrationSource {
  /// The OS speech engine — free, offline, instant.
  local,

  /// ElevenLabs — far better Korean prosody, costs credits per character.
  elevenLabs,
}

/// Splits Korean prose into sentences for sentence-at-a-time narration.
///
/// Sentence-level chunking (rather than handing over the whole story) is what
/// makes the current line highlightable, lets a single sentence be replayed,
/// and keeps ElevenLabs requests small enough to cache usefully.
List<String> splitSentences(String text) {
  final out = <String>[];
  final buffer = StringBuffer();

  for (final ch in text.trim().split('')) {
    buffer.write(ch);
    // Korean prose uses the same terminators as English.
    if (ch == '.' || ch == '!' || ch == '?' || ch == '\n' || ch == '…') {
      final s = buffer.toString().trim();
      if (s.isNotEmpty) out.add(s);
      buffer.clear();
    }
  }
  final tail = buffer.toString().trim();
  if (tail.isNotEmpty) out.add(tail);

  return out.where((s) => s.replaceAll(RegExp(r'[\s.!?…]'), '').isNotEmpty).toList();
}

@immutable
class NarrationState {
  const NarrationState({
    this.storyId,
    this.index = 0,
    this.playing = false,
    this.loading = false,
    this.error,
  });

  /// Which story is loaded — null when nothing is playing.
  final String? storyId;

  /// Sentence currently being spoken.
  final int index;
  final bool playing;

  /// True while a cloud clip is being fetched (never for local speech).
  final bool loading;
  final String? error;

  bool isActive(String id) => storyId == id;

  NarrationState copyWith({
    String? storyId,
    int? index,
    bool? playing,
    bool? loading,
    String? error,
    bool clearError = false,
    bool clearStory = false,
  }) =>
      NarrationState(
        storyId: clearStory ? null : (storyId ?? this.storyId),
        index: index ?? this.index,
        playing: playing ?? this.playing,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Plays a story one sentence at a time, from either source.
class NarrationController extends ValueNotifier<NarrationState> {
  NarrationController() : super(const NarrationState());

  final AudioPlayer _player = AudioPlayer();

  /// Invalidates an in-flight playback loop when a new one starts.
  int _run = 0;

  NarrationSource source = NarrationSource.local;

  /// Starts (or restarts) [sentences] at [from].
  Future<void> play(
    String storyId,
    List<String> sentences, {
    int from = 0,
  }) async {
    if (sentences.isEmpty) return;
    final myRun = ++_run;
    await _silence();

    value = NarrationState(
      storyId: storyId,
      index: from.clamp(0, sentences.length - 1),
      playing: true,
    );

    for (var i = value.index; i < sentences.length; i++) {
      if (myRun != _run) return; // superseded
      value = value.copyWith(index: i, clearError: true);

      try {
        if (source == NarrationSource.elevenLabs) {
          await _speakCloud(sentences, i, myRun);
        } else {
          await TtsService.instance.speak(sentences[i]);
        }
      } catch (e) {
        if (myRun != _run) return;
        value = value.copyWith(
          playing: false,
          loading: false,
          error: e is ElevenLabsException ? e.message : '$e',
        );
        return;
      }
      if (myRun != _run) return;
    }

    if (myRun == _run) {
      value = const NarrationState(); // finished — back to idle
    }
  }

  /// Fetches (or reuses a cached) clip and plays it to completion, warming
  /// the NEXT sentence meanwhile so there's no gap at the full stop.
  Future<void> _speakCloud(List<String> sentences, int i, int myRun) async {
    value = value.copyWith(loading: true);
    final file = await ElevenLabsService.instance.audioFor(sentences[i]);
    if (myRun != _run) return;
    value = value.copyWith(loading: false);

    await _player.play(DeviceFileSource(file.path));

    // Prefetch the next line while this one plays. Failures are swallowed:
    // the main loop will surface them properly when it reaches that line.
    if (i + 1 < sentences.length) {
      unawaited(() async {
        try {
          await ElevenLabsService.instance.audioFor(sentences[i + 1]);
        } catch (_) {}
      }());
    }

    await _player.onPlayerComplete.first;
  }

  Future<void> pause() async {
    _run++; // stop the loop advancing
    await _silence();
    value = value.copyWith(playing: false, loading: false);
  }

  Future<void> stop() async {
    _run++;
    await _silence();
    value = const NarrationState();
  }

  Future<void> _silence() async {
    await TtsService.instance.stop();
    try {
      await _player.stop();
    } catch (_) {}
  }

  @override
  void dispose() {
    _run++;
    _player.dispose();
    super.dispose();
  }
}
