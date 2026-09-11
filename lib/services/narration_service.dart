import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'elevenlabs_service.dart';
import 'tts_service.dart';

/// How much narration plays per press.
enum NarrationMode {
  /// Read the story straight through.
  whole,

  /// Read one sentence and stop, so it can be absorbed before the next.
  sentence,
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
    this.completedId,
  });

  /// Which story is loaded — null when nothing is playing.
  final String? storyId;

  /// Sentence currently being spoken.
  final int index;
  final bool playing;

  /// True while a cloud clip is being fetched (never for local speech).
  final bool loading;
  final String? error;

  /// Set for one update when EVERY sentence of a story has been heard —
  /// however the listener got there, straight through or stepping. Listeners
  /// use it to record that the story was actually played in full.
  final String? completedId;

  bool isActive(String id) => storyId == id;

  NarrationState copyWith({
    String? storyId,
    int? index,
    bool? playing,
    bool? loading,
    String? error,
    String? completedId,
    bool clearError = false,
    bool clearStory = false,
  }) =>
      NarrationState(
        storyId: clearStory ? null : (storyId ?? this.storyId),
        index: index ?? this.index,
        playing: playing ?? this.playing,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
        completedId: completedId,
      );
}

/// Plays a story through ElevenLabs, one sentence at a time.
///
/// Narration is deliberately the ONLY thing that uses ElevenLabs: it's the
/// one place a voice worth listening to for a paragraph is worth paying for.
/// Word taps, the flashcard answer and the word page all speak through the
/// free local engine — see [TtsService] — so nothing else spends credits.
class NarrationController extends ValueNotifier<NarrationState> {
  NarrationController() : super(const NarrationState());

  final AudioPlayer _player = AudioPlayer();

  /// Invalidates an in-flight playback loop when a new one starts.
  int _run = 0;

  /// Sentences heard for [_heardStoryId]. Deleting a story requires having
  /// played all of it, and jumping straight to the last line shouldn't
  /// count — so completion is the SET of lines heard, not just reaching the
  /// end. Session-scoped: it backs the persisted flag, it isn't the flag.
  final Set<int> _heard = <int>{};
  String? _heardStoryId;

  /// Records sentence [i] of [storyId] as heard; returns true when that
  /// completes the story.
  bool _noteHeard(String storyId, int i, int total) {
    if (_heardStoryId != storyId) {
      _heardStoryId = storyId;
      _heard.clear();
    }
    _heard.add(i);
    return _heard.length >= total;
  }

  /// Plays [sentences] from [from].
  ///
  /// In [NarrationMode.sentence] exactly one sentence is read and playback
  /// stops on it, so the next press continues from the following line.
  Future<void> play(
    String storyId,
    List<String> sentences, {
    int from = 0,
    NarrationMode mode = NarrationMode.whole,
  }) async {
    if (sentences.isEmpty) return;
    final myRun = ++_run;
    await _silence();

    // Stepping past the last line ends the story rather than wrapping.
    if (from >= sentences.length) {
      value = const NarrationState();
      return;
    }

    value = NarrationState(
      storyId: storyId,
      index: from.clamp(0, sentences.length - 1),
      playing: true,
    );

    for (var i = value.index; i < sentences.length; i++) {
      if (myRun != _run) return; // superseded
      value = value.copyWith(index: i, clearError: true);

      try {
        await _speakCloud(sentences, i, myRun, prefetch: mode == NarrationMode.whole);
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

      final finished = _noteHeard(storyId, i, sentences.length);
      if (finished) {
        value = value.copyWith(completedId: storyId);
      }

      if (mode == NarrationMode.sentence) {
        // Hold on the line just read: it stays highlighted so it's obvious
        // what was heard, and the next press picks up from the one after.
        value = value.copyWith(playing: false, loading: false);
        return;
      }
    }

    if (myRun == _run) {
      value = const NarrationState(); // finished — back to idle
    }
  }

  /// Fetches (or reuses a cached) clip and plays it to completion, warming
  /// the NEXT sentence meanwhile so there's no gap at the full stop.
  Future<void> _speakCloud(
    List<String> sentences,
    int i,
    int myRun, {
    bool prefetch = true,
  }) async {
    value = value.copyWith(loading: true);
    final file = await ElevenLabsService.instance.audioFor(
      sentences[i],
      previousText: i > 0 ? sentences[i - 1] : null,
      nextText: i + 1 < sentences.length ? sentences[i + 1] : null,
    );
    if (myRun != _run) return;
    value = value.copyWith(loading: false);

    // Set per clip rather than once: the setting can change between
    // sentences, and a story is played one file at a time.
    try {
      await _player.setVolume(await ElevenLabsService.instance.volume());
    } catch (e) {
      // A player that will not take a volume should still play the story.
      debugPrint('[Narration] could not set volume: $e');
    }
    await _player.play(DeviceFileSource(file.path));

    // Prefetch the next line while this one plays. Failures are swallowed:
    // the main loop will surface them properly when it reaches that line.
    // Skipped when stepping — there's no telling if the next line is wanted,
    // and synthesizing it anyway would spend credits on a guess.
    if (prefetch && i + 1 < sentences.length) {
      unawaited(() async {
        try {
          // Same neighbours the main loop will ask for, so the prefetched
          // clip is the one it actually uses.
          await ElevenLabsService.instance.audioFor(
            sentences[i + 1],
            previousText: sentences[i],
            nextText: i + 2 < sentences.length ? sentences[i + 2] : null,
          );
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
    // A word tap and a story shouldn't talk over each other.
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
