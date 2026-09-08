import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/vocab_word.dart';
import 'claude_service.dart';
import 'import_log.dart';
import 'storage_service.dart';

/// Picks up words captured on the phone and files them into the collection.
///
/// The phone writes a file into a cloud-synced folder; the sync client puts it
/// on this disk; this reads it. There is no server and no account — the sync
/// client is the transport.
///
/// A file can be either:
///
///   * a plain list of words, one per line — what a two-action Shortcut
///     produces. [ClaudeService] fills in the readings and meanings here on
///     import, so the phone has nothing to assemble.
///   * full JSON, if something else already did that work.
///
/// Which pile a word lands in is decided by WHERE the file is, so the choice
/// travels with the capture instead of living in a setting that can change
/// before the import runs:
///
///   * `<inbox>/reinforced/` — always reinforced
///   * `<inbox>/learning/`   — always learning
///   * `<inbox>/`            — whatever [defaultStatus] says at import time
///
/// A file is consumed exactly once: it is moved into `processed/` only after
/// its words are in the box, so a crash mid-import means the file is simply
/// picked up again next launch.
class InboxService {
  InboxService._();
  static final InboxService instance = InboxService._();

  static const _kFolder = 'inbox_folder';
  static const _kStatus = 'inbox_status';

  /// Subfolder names that force a status. Two spellings of the second one, so
  /// the folder name isn't a trap.
  static const learningFolder = 'learning';
  static const reinforcedFolder = 'reinforced';
  static const _reinforcedAlias = 'reinforcement';

  /// Set while the settings panel is open, and honoured ONLY by the automatic
  /// import.
  ///
  /// The window-focus import is a race against whoever is configuring it:
  /// clicking away to the phone and back mid-setup used to consume the inbox
  /// using whatever status happened to be saved at that instant, which is not
  /// what the person staring at the half-configured screen intended. Manual
  /// imports are never paused — pressing the button is unambiguous.
  bool autoImportPaused = false;

  /// Where iCloud for Windows puts iCloud Drive on a default install. Only a
  /// hint — the real path is whatever the user sets in Settings.
  ///
  /// iCloud rather than another service because of an iOS limitation, not a
  /// preference: a shortcut can only write to a folder unattended if that
  /// folder is in iCloud Drive. Anywhere else, Save File has to ask the user
  /// where to put it on every single capture.
  static const defaultFolder = r'C:\Users\<you>\iCloudDrive\Maldari';

  Future<String?> folder() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString(_kFolder)?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> setFolder(String path) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kFolder, path.trim());
  }

  Future<void> clearFolder() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kFolder);
  }

  /// Where a word goes when nothing more specific says otherwise — a file
  /// dropped straight in the inbox rather than in one of the two subfolders.
  Future<WordStatus> defaultStatus() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kStatus) == 'reinforcement'
        ? WordStatus.reinforcement
        : WordStatus.learning;
  }

  Future<void> setDefaultStatus(WordStatus s) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _kStatus, s == WordStatus.reinforcement ? 'reinforcement' : 'learning');
  }

  /// Creates the two status subfolders, each with a note inside.
  ///
  /// The note is not decoration: an empty folder does not reliably sync
  /// through iCloud — it never appears in the phone's folder picker — so a
  /// folder we want the phone to see must contain a file. `.md` is ignored by
  /// the importer, which is why it is safe to leave there.
  Future<void> ensureFolders() async {
    final path = await folder();
    if (path == null) return;
    final root = Directory(path);
    if (!root.existsSync()) return;

    for (final entry in const [
      (learningFolder, 'always imported as Learning'),
      (reinforcedFolder, 'always imported as Reinforced'),
    ]) {
      try {
        final dir =
            Directory('${root.path}${Platform.pathSeparator}${entry.$1}');
        if (!dir.existsSync()) dir.createSync(recursive: true);
        final note = File('${dir.path}${Platform.pathSeparator}README.md');
        if (!note.existsSync()) {
          note.writeAsStringSync(
            '# ${entry.$1}\n\n'
            'Words saved here are ${entry.$2}, whatever the "Words arrive as" '
            'setting says.\n\n'
            'Point a second Shortcut at this folder and choosing the pile '
            'becomes which icon you tap.\n\n'
            'This file only exists so the folder syncs — an empty folder does '
            'not reliably appear on the phone. Maldari ignores it.\n',
          );
        }
      } catch (e) {
        debugPrint('[InboxService] could not create ${entry.$1}: $e');
      }
    }
  }

  /// Reads every file in the inbox and adds the words it doesn't already
  /// have, asking the cloud model for anything the file didn't carry. Safe to
  /// call as often as you like — importing the same file twice adds nothing,
  /// and neither does a word already in the collection.
  Future<InboxResult> importNow() async {
    final path = await folder();
    if (path == null) {
      return const InboxResult(configured: false);
    }

    final root = Directory(path);
    if (!root.existsSync()) {
      return InboxResult(errors: ['Folder not found: $path']);
    }

    final fallbackStatus = await defaultStatus();
    final sources = _sourcesUnder(root);

    final box = StorageService.instance.box;
    // Dedupe on the same key the merge tool uses, so an import can't create
    // the duplicates that tool exists to clean up.
    final known = <String>{
      for (final w in box.values) w.hangul.trim().toLowerCase(),
    };

    var addedLearning = 0;
    var addedReinforced = 0;
    var skipped = 0;
    var handled = 0;
    var defined = 0;
    final errors = <String>[];
    final corrections = <String>[];

    for (final source in sources) {
      final files = <File>[
        for (final e in source.dir.listSync())
          if (e is File && _isCandidate(e)) e,
      ]..sort((a, b) => a.path.compareTo(b.path));

      for (final file in files) {
        final label = _label(file, root);
        List<Map<String, dynamic>> entries;
        final ignoredLines = <String>[];
        try {
          entries = _parse(await file.readAsString(), ignoredLines);
        } catch (e) {
          // Most often a file still syncing — leave it alone and try again on
          // the next run rather than importing half of it.
          errors.add('$label: ${_short(e)}');
          continue;
        }

        // Loud, not silent: a line that was not numbered is a word the user
        // believes they captured, and it is about to not exist.
        if (ignoredLines.isNotEmpty) {
          final shown = ignoredLines.take(3).join(', ');
          errors.add(
            '$label: ignored ${ignoredLines.length} unnumbered '
            'line${ignoredLines.length == 1 ? '' : 's'} ($shown'
            '${ignoredLines.length > 3 ? ', …' : ''}) — number every line',
          );
        }

        defined += await _define(entries, label, errors, corrections);

        var wroteAny = false;
        for (final entry in entries) {
          final hangul = (entry['hangul'] ?? '').toString().trim();
          if (hangul.isEmpty) continue;
          final key = hangul.toLowerCase();
          if (!known.add(key)) {
            skipped++;
            continue;
          }
          try {
            final word = _wordFrom(
              entry,
              hangul,
              fallbackStatus,
              forced: source.forced,
            );
            await box.put(word.id, word);
            if (word.status == WordStatus.reinforcement) {
              addedReinforced++;
            } else {
              addedLearning++;
            }
            wroteAny = true;
          } catch (e) {
            known.remove(key);
            errors.add('$hangul: ${_short(e)}');
          }
        }

        // Retire the file once its words are in the box — or once it is clear
        // there were never any to find.
        //
        // Two different "no words" cases, and conflating them was a bug. A
        // file with lines we READ but rejected (unnumbered, say) is fully
        // readable and never going to improve: retire it now, so its
        // complaint is made exactly once instead of on every import until a
        // timer expires. A file that came back completely empty might be one
        // the sync client has not finished writing, so that one waits.
        final rejected = entries.isEmpty && ignoredLines.isNotEmpty;
        final blank = entries.isEmpty && ignoredLines.isEmpty && _settled(file);
        if (wroteAny || entries.isNotEmpty || rejected || blank) {
          if (await _archive(file, root)) handled++;
        }
      }
    }

    // Words that just landed must survive a crash a second later, not in 400
    // milliseconds' time.
    if (addedLearning + addedReinforced > 0) {
      await StorageService.instance.flushAll();
    }

    final result = InboxResult(
      addedLearning: addedLearning,
      addedReinforced: addedReinforced,
      skipped: skipped,
      files: handled,
      defined: defined,
      corrections: corrections,
      errors: errors,
    );
    // Logged here rather than at each call site: an import can be triggered
    // from four places, and a log that depends on the caller remembering is a
    // log with holes in it.
    await ImportLog.instance.record(result);
    return result;
  }

  /// The inbox root plus whichever status subfolders exist, each carrying the
  /// status it forces. `processed/` is deliberately not among them.
  List<({Directory dir, WordStatus? forced})> _sourcesUnder(Directory root) {
    final out = <({Directory dir, WordStatus? forced})>[
      (dir: root, forced: null),
    ];
    const named = <String, WordStatus>{
      learningFolder: WordStatus.learning,
      reinforcedFolder: WordStatus.reinforcement,
      _reinforcedAlias: WordStatus.reinforcement,
    };
    for (final entry in named.entries) {
      final dir = Directory('${root.path}${Platform.pathSeparator}${entry.key}');
      if (dir.existsSync()) out.add((dir: dir, forced: entry.value));
    }
    return out;
  }

  /// Fills in whatever the file didn't carry. Returns how many words were
  /// completed; on failure the bare words are still imported, because losing
  /// the capture would be worse than importing a word you can auto-fill later.
  Future<int> _define(
    List<Map<String, dynamic>> entries,
    String label,
    List<String> errors,
    List<String> corrections,
  ) async {
    final bare = [
      for (final e in entries)
        if (_needsDefining(e)) (e['hangul'] ?? '').toString().trim(),
    ]..removeWhere((w) => w.isEmpty);

    if (bare.isEmpty || !await ClaudeService.instance.isConfigured) return 0;

    try {
      // Keyed on the ECHOED input, not on the answer: a corrected word comes
      // back under a spelling that was never sent, and matching on that would
      // quietly drop exactly the entries that needed the most help.
      final byInput = <String, Map<String, dynamic>>{
        for (final d in await ClaudeService.instance.define(bare))
          (d['input'] ?? d['hangul'] ?? '').toString().trim(): d,
      };
      var count = 0;
      for (final e in entries) {
        final typed = (e['hangul'] ?? '').toString().trim();
        final match = byInput[typed];
        if (match == null) continue;

        // Adopt the corrected spelling. This happens before the collection is
        // checked for duplicates, so a typo of a word you already have is
        // recognised as that word rather than added beside it.
        final fixed = (match['hangul'] ?? '').toString().trim();
        if (fixed.isNotEmpty && fixed != typed) {
          e['hangul'] = fixed;
          corrections.add('$typed → $fixed');
        }

        for (final field in const [
          'romanization',
          'englishMeaning',
          'partOfSpeech',
          'politeForm',
        ]) {
          final v = (match[field] ?? '').toString();
          if ((e[field] ?? '').toString().trim().isEmpty && v.isNotEmpty) {
            e[field] = v;
          }
        }
        count++;
      }
      return count;
    } catch (e) {
      errors.add('$label: definitions unavailable — ${_short(e)}');
      return 0;
    }
  }

  /// Files worth looking at. Extension-tolerant on purpose — one fewer thing
  /// to get exactly right on the phone — but sync clients and Explorer leave
  /// their own droppings in every folder, and those are not vocabulary.
  static bool _isCandidate(File f) {
    final name = _name(f).toLowerCase();
    if (name.startsWith('.') || name.startsWith('~\$')) return false;
    if (name == 'desktop.ini' || name == 'thumbs.db') return false;
    return name.endsWith('.json') ||
        name.endsWith('.txt') ||
        !name.contains('.');
  }

  /// A numbered line: `1. 가다`, `2) 가다`, `3 가다`, `4.가다`.
  ///
  /// The number is the thing that makes a line a word. Requiring it is a
  /// deliberate filter: a captured file is whatever was in a text field on a
  /// phone, and without a marker there is no way to tell a vocabulary word
  /// from a stray line, an autocorrect artefact or a note to self. Numbering
  /// is cheap to type and unambiguous to read.
  static final RegExp _numbered = RegExp(r'^\s*\d+\s*[.)\]:]?\s*(.+)$');

  /// Accepts JSON — a bare array or `{"words": [...]}` — or a NUMBERED list of
  /// words, one per line. Anything unnumbered is collected into [ignored] for
  /// the caller to report; it is never imported.
  List<Map<String, dynamic>> _parse(String raw, List<String> ignored) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const [];

    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      final decoded = jsonDecode(trimmed);
      final list = decoded is List
          ? decoded
          : (decoded is Map
              ? (decoded['words'] as List? ?? const [])
              : const []);
      return [
        for (final e in list)
          if (e is Map) Map<String, dynamic>.from(e),
      ];
    }

    final out = <Map<String, dynamic>>[];
    for (final line in trimmed.split(RegExp(r'[\r\n]+'))) {
      if (line.trim().isEmpty) continue;
      final match = _numbered.firstMatch(line);
      final word = (match?.group(1) ?? '').trim();
      if (match == null || word.isEmpty) {
        ignored.add(line.trim());
        continue;
      }
      out.add({'hangul': word});
    }
    return out;
  }

  /// True when an entry is just a word with no reading or meaning yet.
  static bool _needsDefining(Map<String, dynamic> e) =>
      (e['romanization'] ?? '').toString().trim().isEmpty ||
      (e['englishMeaning'] ?? e['english'] ?? '').toString().trim().isEmpty;

  VocabWord _wordFrom(
    Map<String, dynamic> e,
    String hangul,
    WordStatus fallbackStatus, {
    WordStatus? forced,
  }) {
    final pos = (e['partOfSpeech'] ?? '').toString().trim();
    final status = (e['status'] ?? '').toString().trim().toLowerCase();

    return VocabWord(
      // Same shape the add sheet uses, with a suffix so a batch landing in the
      // same millisecond can't collide.
      id: 'w-${DateTime.now().millisecondsSinceEpoch}-${_seq++}',
      hangul: hangul,
      romanization: (e['romanization'] ?? '').toString().trim(),
      englishMeaning: (e['englishMeaning'] ?? e['english'] ?? '')
          .toString()
          .trim(),
      partOfSpeech:
          PartsOfSpeech.all.contains(pos) ? pos : PartsOfSpeech.noun,
      politeForm: (e['politeForm'] ?? '').toString().trim(),
      dateAdded: DateTime.now(),
      // Folder beats file beats setting. The folder is the most deliberate of
      // the three — you chose it at capture time, one tap on the phone — and
      // the setting is the least, since it can change before the import runs.
      status: forced ??
          switch (status) {
            'reinforcement' || 'reinforced' => WordStatus.reinforcement,
            'learning' => WordStatus.learning,
            _ => fallbackStatus,
          },
    );
  }

  int _seq = 0;

  /// Moves a consumed file into the root's `processed/`, wherever it came
  /// from. Never deletes: the same rule the rest of the app follows, and a
  /// mis-parsed import is recoverable by hand.
  Future<bool> _archive(File file, Directory root) async {
    try {
      final done = Directory('${root.path}${Platform.pathSeparator}processed');
      if (!done.existsSync()) done.createSync(recursive: true);
      var target = '${done.path}${Platform.pathSeparator}${_name(file)}';
      if (File(target).existsSync()) {
        target = '$target.${DateTime.now().millisecondsSinceEpoch}';
      }
      await file.rename(target);
      return true;
    } catch (e) {
      // A file the sync client still holds open stays put and is skipped next
      // time by the hangul dedupe, so nothing is imported twice.
      debugPrint('[InboxService] could not archive ${_name(file)}: $e');
      return false;
    }
  }

  /// True when a file has not been touched for a couple of minutes — long
  /// enough that a sync in progress would have finished.
  static bool _settled(File f) {
    try {
      return DateTime.now().difference(f.lastModifiedSync()) >
          const Duration(minutes: 2);
    } catch (_) {
      return false;
    }
  }

  static String _name(File f) => f.path.split(Platform.pathSeparator).last;

  /// How a file is named in reports: relative to the inbox root, so a file in
  /// a status subfolder is distinguishable from one beside it in the root.
  ///
  /// Two captures of the same word land as `서성이다.txt` and
  /// `reinforced. 서성이다.txt`, and a report naming only the last path
  /// segment makes those look like the same file — which turns "this one was
  /// rejected" into "your numbering did not work".
  static String _label(File f, Directory root) {
    final prefix = root.path.endsWith(Platform.pathSeparator)
        ? root.path
        : '${root.path}${Platform.pathSeparator}';
    return f.path.startsWith(prefix)
        ? f.path.substring(prefix.length)
        : _name(f);
  }

  static String _short(Object e) {
    final s = e.toString();
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }
}

@immutable
class InboxResult {
  const InboxResult({
    this.addedLearning = 0,
    this.addedReinforced = 0,
    this.skipped = 0,
    this.files = 0,
    this.defined = 0,
    this.corrections = const [],
    this.errors = const [],
    this.configured = true,
  });

  /// Counted separately, because one import can now land in both piles — and
  /// which pile a word went to is exactly the thing that is hard to notice
  /// and tedious to undo.
  final int addedLearning;
  final int addedReinforced;

  int get added => addedLearning + addedReinforced;

  /// Words the collection already had.
  final int skipped;

  /// Files consumed and moved to `processed/`.
  final int files;

  /// Words the cloud model filled in on the way through.
  final int defined;

  /// Spellings the model changed, as "typed → kept". Surfaced rather than
  /// applied silently: a correction is a judgement about what you meant, and
  /// you should get to see the ones it made.
  final List<String> corrections;

  final List<String> errors;

  /// False when no inbox folder has been set yet.
  final bool configured;

  bool get changedAnything => added > 0;
  bool get isEmpty => added == 0 && skipped == 0 && errors.isEmpty;

  String get summary {
    if (!configured) return 'No inbox folder set.';
    if (isEmpty) return 'Nothing new in the inbox.';
    final parts = <String>[
      if (addedLearning > 0) '$addedLearning added to Learning',
      if (addedReinforced > 0) '$addedReinforced added to Reinforced',
      if (defined > 0) '$defined defined',
      if (corrections.isNotEmpty) '${corrections.length} corrected',
      if (skipped > 0) '$skipped already known',
      if (errors.isNotEmpty) '${errors.length} problem'
          '${errors.length == 1 ? '' : 's'}',
    ];
    return parts.join(' · ');
  }
}
