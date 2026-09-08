import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/vocab_word.dart';
import 'claude_service.dart';
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
/// A file is consumed exactly once: it is moved into `processed/` only after
/// its words are in the box, so a crash mid-import means the file is simply
/// picked up again next launch.
class InboxService {
  InboxService._();
  static final InboxService instance = InboxService._();

  static const _kFolder = 'inbox_folder';
  static const _kStatus = 'inbox_status';

  /// Where Google Drive for desktop mounts by default. Only a starting point —
  /// the real path is whatever the user sets in Settings.
  static const defaultFolder = r'G:\My Drive\Maldari\inbox';

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

  /// Which pile phone words land in. A plain word list carries no status, and
  /// asking the phone to express one is exactly the complexity this design
  /// removes — so it is a setting here instead.
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

  /// Reads every file in the inbox and adds the words it doesn't already
  /// have, asking the cloud model for anything the file didn't carry. Safe to
  /// call as often as you like — importing the same file twice adds nothing,
  /// and neither does a word already in the collection.
  Future<InboxResult> importNow() async {
    final path = await folder();
    if (path == null) {
      return const InboxResult(configured: false);
    }

    final dir = Directory(path);
    if (!dir.existsSync()) {
      return InboxResult(
        errors: ['Folder not found: $path'],
      );
    }

    final files = <File>[
      for (final e in dir.listSync())
        if (e is File && _isCandidate(e)) e,
    ]..sort((a, b) => a.path.compareTo(b.path));

    if (files.isEmpty) return const InboxResult();

    final box = StorageService.instance.box;
    // Dedupe on the same key the merge tool uses, so an import can't create
    // the duplicates that tool exists to clean up.
    final known = <String>{
      for (final w in box.values) w.hangul.trim().toLowerCase(),
    };

    var added = 0;
    var skipped = 0;
    var handled = 0;
    var defined = 0;
    final errors = <String>[];
    final fallbackStatus = await defaultStatus();

    for (final file in files) {
      List<Map<String, dynamic>> entries;
      try {
        final raw = await file.readAsString();
        entries = _parse(raw);
      } catch (e) {
        // Most often a file still syncing — leave it alone and try again on
        // the next run rather than importing half of it.
        errors.add('${_name(file)}: ${_short(e)}');
        continue;
      }

      // A plain word list arrives with nothing but hangul. Ask Claude for the
      // rest before anything is written, so a word is either complete or not
      // imported at all.
      final bare = [
        for (final e in entries)
          if (_needsDefining(e)) (e['hangul'] ?? '').toString().trim(),
      ]..removeWhere((w) => w.isEmpty);

      if (bare.isNotEmpty && await ClaudeService.instance.isConfigured) {
        try {
          final byWord = <String, Map<String, dynamic>>{
            for (final d in await ClaudeService.instance.define(bare))
              (d['hangul'] ?? '').toString().trim(): d,
          };
          for (final e in entries) {
            final match = byWord[(e['hangul'] ?? '').toString().trim()];
            if (match == null) continue;
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
            defined++;
          }
        } catch (e) {
          // Import the bare words anyway: losing the capture would be worse
          // than importing a word you can auto-fill later.
          errors.add('${_name(file)}: definitions unavailable — ${_short(e)}');
        }
      }

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
          final word = _wordFrom(entry, hangul, fallbackStatus);
          await box.put(word.id, word);
          added++;
          wroteAny = true;
        } catch (e) {
          known.remove(key);
          errors.add('$hangul: ${_short(e)}');
        }
      }

      // Only retire the file once its words are actually in the box.
      if (wroteAny || entries.isNotEmpty) {
        final moved = await _archive(file, dir);
        if (moved) handled++;
      }
    }

    // Words that just landed must survive a crash a second later, not in 400
    // milliseconds' time.
    if (added > 0) await StorageService.instance.flushAll();

    return InboxResult(
      added: added,
      skipped: skipped,
      files: handled,
      defined: defined,
      errors: errors,
    );
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

  /// Accepts JSON — a bare array or `{"words": [...]}` — or a plain list of
  /// words, one per line. The plain list is what the phone actually sends;
  /// JSON is for anything that already knows the full shape.
  List<Map<String, dynamic>> _parse(String raw) {
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

    // Plain text. Split on lines and commas so either habit works, and drop
    // anything that isn't a word — bullet characters, numbering, stray dashes.
    return [
      for (final line in trimmed.split(RegExp(r'[\r\n,]+')))
        if (_cleanWord(line).isNotEmpty) {'hangul': _cleanWord(line)},
    ];
  }

  static String _cleanWord(String line) =>
      line.trim().replaceAll(RegExp(r'^[-*•\d.)\s]+'), '').trim();

  /// True when an entry is just a word with no reading or meaning yet.
  static bool _needsDefining(Map<String, dynamic> e) =>
      (e['romanization'] ?? '').toString().trim().isEmpty ||
      (e['englishMeaning'] ?? e['english'] ?? '').toString().trim().isEmpty;

  VocabWord _wordFrom(
    Map<String, dynamic> e,
    String hangul,
    WordStatus fallbackStatus,
  ) {
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
      // An explicit status in the file wins; a plain word list has none, and
      // takes the pile chosen in Settings.
      status: switch (status) {
        'reinforcement' || 'reinforced' => WordStatus.reinforcement,
        'learning' => WordStatus.learning,
        _ => fallbackStatus,
      },
    );
  }

  int _seq = 0;

  /// Moves a consumed file into `processed/`. Never deletes: the same rule the
  /// rest of the app follows, and a mis-parsed import is recoverable by hand.
  Future<bool> _archive(File file, Directory dir) async {
    try {
      final done = Directory('${dir.path}${Platform.pathSeparator}processed');
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

  static String _name(File f) => f.path.split(Platform.pathSeparator).last;

  static String _short(Object e) {
    final s = e.toString();
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }
}

@immutable
class InboxResult {
  const InboxResult({
    this.added = 0,
    this.skipped = 0,
    this.files = 0,
    this.defined = 0,
    this.errors = const [],
    this.configured = true,
  });

  /// Words written to the collection.
  final int added;

  /// Words the collection already had.
  final int skipped;

  /// Files consumed and moved to `processed/`.
  final int files;

  /// Words the cloud model filled in on the way through.
  final int defined;

  final List<String> errors;

  /// False when no inbox folder has been set yet.
  final bool configured;

  bool get changedAnything => added > 0;
  bool get isEmpty => added == 0 && skipped == 0 && errors.isEmpty;

  String get summary {
    if (!configured) return 'No inbox folder set.';
    if (isEmpty) return 'Nothing new in the inbox.';
    final parts = <String>[
      if (added > 0) '$added added',
      if (defined > 0) '$defined defined',
      if (skipped > 0) '$skipped already known',
      if (errors.isNotEmpty) '${errors.length} problem'
          '${errors.length == 1 ? '' : 's'}',
    ];
    return parts.join(' · ');
  }
}
