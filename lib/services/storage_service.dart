import 'dart:async';
import 'dart:io';

import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/block_entry.dart';
import '../models/grammar_topic.dart';
import '../models/vocab_word.dart';
import '../models/word_detail.dart';

class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  static const String _primaryBox = 'vocab_words_v1';
  static const String _blocksBoxName = 'blocks_v1';
  static const String _grammarBoxName = 'grammar_v1';
  static const String _detailsBoxName = 'word_details_v1';
  Box<VocabWord>? _box;
  Box<BlockEntry>? _blocksBox;
  Box<GrammarTopic>? _grammarBox;
  Box<String>? _detailsBox;

  /// Directory the boxes live in — needed to quarantine a damaged file.
  String? _dir;

  /// Debounced durability: see [_armAutoFlush].
  Timer? _flushTimer;
  final List<StreamSubscription<BoxEvent>> _watchers = [];

  /// Human-readable notes about anything repaired at startup. Empty on a
  /// normal launch; surfaced in Settings when not.
  final List<String> recoveryNotes = [];

  Box<VocabWord> get box {
    final b = _box;
    if (b == null) {
      throw StateError('StorageService not initialized — call init() first.');
    }
    return b;
  }

  Box<BlockEntry> get blocksBox {
    final b = _blocksBox;
    if (b == null) {
      throw StateError('StorageService not initialized — call init() first.');
    }
    return b;
  }

  Box<GrammarTopic> get grammarBox {
    final b = _grammarBox;
    if (b == null) {
      throw StateError('StorageService not initialized — call init() first.');
    }
    return b;
  }

  /// Cached word pages (JSON), keyed by word id. Plain strings — no adapter.
  Box<String> get detailsBox {
    final b = _detailsBox;
    if (b == null) {
      throw StateError('StorageService not initialized — call init() first.');
    }
    return b;
  }

  /// The cached Korean study page for [wordId], or null if it was never
  /// generated (or the stored JSON no longer parses).
  WordDetail? wordDetail(String wordId) {
    final raw = detailsBox.get(wordId);
    if (raw == null) return null;
    return WordDetail.decode(raw);
  }

  Future<void> putWordDetail(String wordId, WordDetail detail) =>
      detailsBox.put(wordId, detail.encode());

  Future<void> deleteWordDetail(String wordId) => detailsBox.delete(wordId);

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _dir = dir.path;
    await Hive.initFlutter(dir.path);

    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(VocabWordAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(BlockEntryAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(GrammarTopicAdapter());
    }

    _box = await _openRecovering<VocabWord>(_primaryBox);
    _blocksBox = await _openRecovering<BlockEntry>(_blocksBoxName);
    _grammarBox = await _openRecovering<GrammarTopic>(_grammarBoxName);
    _detailsBox = await _openRecovering<String>(_detailsBoxName);

    // From here on, every write is flushed to disk shortly after it lands.
    _armAutoFlush();

    // Seed the starter words AT MOST ONCE in the lifetime of the install. If
    // the user later deletes everything (e.g. "Delete all learned words" or
    // clearing every Learning word), we must not re-seed on next launch —
    // that would resurrect words they intentionally removed.
    //
    // The flag is set whenever we've made the seeding decision, NOT only when
    // we actually seed. This covers users upgrading from a build that had no
    // flag: their box already has words, so we skip seeding but still mark the
    // install initialized — otherwise emptying the box later would reseed.
    final prefs = await SharedPreferences.getInstance();
    final didSeed = prefs.getBool('did_seed_starters_v1') ?? false;
    if (!didSeed) {
      // `seen_onboarding` is written only after a user finishes onboarding, so
      // its presence means this is NOT a fresh install. Seed only on a genuine
      // first run — this also protects users who emptied their box under an
      // older build (no flag) from getting the starters resurrected once.
      final isFreshInstall = !prefs.containsKey('seen_onboarding');
      if (box.isEmpty && isFreshInstall) {
        await _seedStarterWords();
      }
      await prefs.setBool('did_seed_starters_v1', true);
    }

    await _clearNonVerbPoliteForms(prefs);
    await _foldLearnedIntoLearning(prefs);
  }

  /// One-time migration: the app used to have three states (learning →
  /// learned → reinforcement) and a Learned tab. It now toggles between
  /// Learning and Reinforcement only, so any word still carrying the retired
  /// `learned` status is folded back into Learning — otherwise it would exist
  /// in the box with no tab able to show it.
  Future<void> _foldLearnedIntoLearning(SharedPreferences prefs) async {
    if (prefs.getBool('did_fold_learned_v1') ?? false) return;
    final box = this.box;
    for (final w in box.values.toList()) {
      if (w.status == WordStatus.learned) {
        await box.put(w.id, w.copyWith(status: WordStatus.learning));
      }
    }
    await prefs.setBool('did_fold_learned_v1', true);
  }

  /// One-time cleanup: a present polite form only applies to verbs and
  /// descriptive verbs, but earlier auto-fills sometimes stored a copula form
  /// for nouns (e.g. "문제예요" on 문제). Strip those once.
  Future<void> _clearNonVerbPoliteForms(SharedPreferences prefs) async {
    if (prefs.getBool('did_clear_noun_polite_v1') ?? false) return;
    final box = this.box;
    for (final w in box.values.toList()) {
      final pos = w.partOfSpeech;
      final isVerb =
          pos == PartsOfSpeech.verb || pos == PartsOfSpeech.descriptiveVerb;
      if (!isVerb && w.politeForm.trim().isNotEmpty) {
        await box.put(w.id, w.copyWith(politeForm: ''));
      }
    }
    await prefs.setBool('did_clear_noun_polite_v1', true);
  }

  /// Opens [name], recovering from a file left half-written by an abrupt
  /// termination — a power cut, a task-manager kill, an OS shutdown that
  /// doesn't wait for us.
  ///
  /// Hive appends frames and each frame carries its own checksum, so the only
  /// damage an interrupted write can do is leave a torn frame at the tail.
  /// `crashRecovery` truncates exactly that and keeps everything before it.
  ///
  /// If the file is damaged beyond that, we NEVER delete it: it is renamed
  /// aside as `<name>.corrupt-<timestamp>.hive` and a fresh box is opened, so
  /// the user's words still exist on disk and can be recovered by hand. (An
  /// earlier version called `deleteBoxFromDisk` here, which turned a torn
  /// tail into total data loss.)
  Future<Box<T>> _openRecovering<T>(String name) async {
    try {
      return await Hive.openBox<T>(name, crashRecovery: true);
    } catch (e) {
      recoveryNotes.add('$name: $e');

      // Drop any half-registered handle before touching the files.
      try {
        await Hive.box<T>(name).close();
      } catch (_) {}

      final quarantined = await _quarantine(name);
      try {
        final box = await Hive.openBox<T>(name, crashRecovery: true);
        recoveryNotes.add(quarantined == null
            ? '$name: reopened after recovery.'
            : '$name: damaged file kept as ${quarantined.split(Platform.pathSeparator).last}.');
        return box;
      } catch (_) {
        // Couldn't even reopen under the same name — most often a file lock
        // (OneDrive mid-sync on Windows). Use a timestamped box so the app
        // still starts; the original file is untouched.
        final fallback = '${name}_${DateTime.now().millisecondsSinceEpoch}';
        recoveryNotes.add('$name: locked — running on $fallback instead.');
        return await Hive.openBox<T>(fallback, crashRecovery: true);
      }
    }
  }

  /// Renames the box's file out of the way instead of deleting it. Returns
  /// the new path, or null if there was nothing to move.
  Future<String?> _quarantine(String name) async {
    final dir = _dir;
    if (dir == null) return null;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    String? moved;
    try {
      final file = File('$dir${Platform.pathSeparator}$name.hive');
      if (file.existsSync()) {
        final target = '$dir${Platform.pathSeparator}$name.corrupt-$stamp.hive';
        await file.rename(target);
        moved = target;
      }
      // The lock file carries no data — it can go.
      final lock = File('$dir${Platform.pathSeparator}$name.lock');
      if (lock.existsSync()) await lock.delete();
    } catch (_) {
      // Rename can fail if something else holds the file; the caller falls
      // back to a timestamped box, so this is not fatal.
    }
    return moved;
  }

  /// Forces every open box's pending writes down to the OS and onto disk.
  ///
  /// Hive writes each `put` to the file handle immediately, which already
  /// survives the process being killed, but NOT the machine losing power.
  /// Flushing closes that window.
  Future<void> flushAll() async {
    _flushTimer?.cancel();
    for (final b in <BoxBase<Object?>?>[
      _box,
      _blocksBox,
      _grammarBox,
      _detailsBox,
    ]) {
      if (b == null || !b.isOpen) continue;
      try {
        await b.flush();
      } catch (_) {
        // A flush failure must never take the app down — the write is still
        // in the OS buffer and will land unless the machine dies first.
      }
    }
  }

  /// Every box write schedules a flush shortly after. Debounced so a bulk
  /// operation (import, merge duplicates, delete-all) costs one fsync rather
  /// than one per record.
  void _armAutoFlush() {
    for (final b in <BoxBase<Object?>?>[
      _box,
      _blocksBox,
      _grammarBox,
      _detailsBox,
    ]) {
      if (b == null) continue;
      _watchers.add(b.watch().listen((_) => _scheduleFlush()));
    }
  }

  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: 400), flushAll);
  }

  Future<void> _seedStarterWords() async {
    final now = DateTime.now();
    final seeds = <VocabWord>[
      VocabWord(
        id: 'seed-1',
        hangul: '밥',
        romanization: 'bap',
        englishMeaning: 'rice; meal',
        partOfSpeech: PartsOfSpeech.noun,
        dateAdded: now,
      ),
      VocabWord(
        id: 'seed-2',
        hangul: '물',
        romanization: 'mul',
        englishMeaning: 'water',
        partOfSpeech: PartsOfSpeech.noun,
        dateAdded: now,
      ),
      VocabWord(
        id: 'seed-3',
        hangul: '책',
        romanization: 'chaek',
        englishMeaning: 'book',
        partOfSpeech: PartsOfSpeech.noun,
        dateAdded: now,
      ),
      VocabWord(
        id: 'seed-4',
        hangul: '학교',
        romanization: 'hakgyo',
        englishMeaning: 'school',
        partOfSpeech: PartsOfSpeech.noun,
        dateAdded: now,
      ),
      VocabWord(
        id: 'seed-5',
        hangul: '친구',
        romanization: 'chingu',
        englishMeaning: 'friend',
        partOfSpeech: PartsOfSpeech.noun,
        dateAdded: now,
      ),
      VocabWord(
        id: 'seed-6',
        hangul: '가다',
        romanization: 'gada',
        englishMeaning: 'to go',
        partOfSpeech: PartsOfSpeech.verb,
        dateAdded: now,
      ),
      VocabWord(
        id: 'seed-7',
        hangul: '먹다',
        romanization: 'meokda',
        englishMeaning: 'to eat',
        partOfSpeech: PartsOfSpeech.verb,
        dateAdded: now,
      ),
      VocabWord(
        id: 'seed-8',
        hangul: '마시다',
        romanization: 'masida',
        englishMeaning: 'to drink',
        partOfSpeech: PartsOfSpeech.verb,
        dateAdded: now,
      ),
      VocabWord(
        id: 'seed-9',
        hangul: '예쁘다',
        romanization: 'yeppeuda',
        englishMeaning: 'pretty; beautiful',
        partOfSpeech: PartsOfSpeech.descriptiveVerb,
        dateAdded: now,
      ),
      VocabWord(
        id: 'seed-10',
        hangul: '크다',
        romanization: 'keuda',
        englishMeaning: 'big; large',
        partOfSpeech: PartsOfSpeech.descriptiveVerb,
        dateAdded: now,
      ),
    ];
    for (final w in seeds) {
      await box.put(w.id, w);
    }
  }

  /// Graceful shutdown. Everything here is best-effort: if the process is
  /// killed before or during it, the boxes on disk are still consistent —
  /// closing is an optimisation, not a requirement for durability.
  Future<void> close() async {
    _flushTimer?.cancel();
    for (final w in _watchers) {
      await w.cancel();
    }
    _watchers.clear();
    await flushAll();
    try {
      await _box?.close();
      await _blocksBox?.close();
      await _grammarBox?.close();
      await _detailsBox?.close();
    } on FileSystemException {
      // ignore — already closed or OneDrive locked
    }
  }
}
